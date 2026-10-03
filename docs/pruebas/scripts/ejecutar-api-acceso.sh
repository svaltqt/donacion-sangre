#!/usr/bin/env bash
# Tercera tanda por API: OBS-02 (historial ajeno), OBS-03 (admin de otro banco), P-05 (radio),
# P-13 (métricas globales), P-15 (admin de banco) y CF-11 (donación de 200 ml).
# Los reportes P-16/P-17 los ejecuta reportes-excel.cjs (Node), que se lanza al final.
# Requiere cargar-datos.sh + ejecutar-api.sh + ejecutar-api-citas.sh ya ejecutados.
# Resultado: evidencias/verificaciones-acceso.log
#
# [SUPUESTO] admin.envigado y admin.bello (datos personales inventados), donante Prueba200,
# datos de las pruebas de propiedad (B-, A- en Envigado). Lo creado en Envigado durante
# OBS-03 se elimina al final con el super admin (limpieza, fuera de la evidencia de los casos).
# Nota: no es repetible sin reiniciar la BD (crea usuarios y una donación).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$(cd "$DIR/.." && pwd)/evidencias/verificaciones-acceso.log"
source "$DIR/lib-api.sh"
: > "$LOG"

HOY=$(date +%F)
id_de() { echo "$LAST_BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2; }
donacion_json() { echo "{\"usuarioId\":$1,\"bancoId\":${6:-1},\"solicitudId\":$2,\"fechaDonacion\":\"$3\",\"tipoSangre\":\"$4\",\"cantidadMl\":$5}"; }
admin_json() { # nombre apellido correo doc clave
  echo "{\"nombre\":\"$1\",\"apellido\":\"$2\",\"correo\":\"$3\",\"celular\":\"31000000${4: -2}\",\"tipoDocumento\":\"CC\",\"numeroDocumento\":\"$4\",\"contrasena\":\"$5\",\"ciudad\":\"Medell${U}00edn\",\"departamento\":\"Antioquia\"}"
}
haversine() { awk -v a="$1" -v b="$2" -v c="$3" -v d="$4" 'BEGIN{r=6371;p=atan2(0,-1)/180;dl=(c-a)*p;dn=(d-b)*p;x=sin(dl/2)^2+cos(a*p)*cos(c*p)*sin(dn/2)^2;printf "%.2f",2*r*atan2(sqrt(x),sqrt(1-x))}'; }

CASO="PREP"; mkdir -p "$EVID/PREP"
paso "Login admin de banco (Medellin)" POST /api/v1/auth/login "" "$(login_json admin.banco@test.com 'Banco123*')"; TOKEN_ADMIN=$(token)
paso "Login super admin" POST /api/v1/auth/login "" "$(login_json super.admin@test.com 'Admin123*')"; TOKEN_SUPER=$(token)
paso "Login Ana" POST /api/v1/auth/login "" "$(login_json ana.prueba@test.com 'Prueba123*')"; TOKEN_ANA=$(token); ANA=$(uid)
paso "Login Omar" POST /api/v1/auth/login "" "$(login_json omar.negativo@test.com 'Prueba123*')"; OMAR=$(uid)
paso "Login Dona90" POST /api/v1/auth/login "" "$(login_json dona90@test.com 'Prueba123*')"; TOKEN_D90=$(token); D90=$(uid)
rm -rf "$EVID/PREP"
[ -n "$TOKEN_ADMIN" ] && [ -n "$TOKEN_SUPER" ] && [ -n "$TOKEN_ANA" ] && [ -n "$OMAR" ] || { echo "Faltan datos: ¿se ejecutaron los scripts anteriores?"; exit 1; }
banco_id() { # nit -> id (en el JSON del banco "admin" va anidado: se usa id, nombre y nit consecutivos)
  mkdir -p "$EVID/PREP"; CASO="PREP"; paso "buscar banco" GET /api/bancos "$TOKEN_SUPER" >/dev/null; rm -rf "$EVID/PREP"
  echo "$LAST_BODY" | grep -o "\"id\":[0-9]*,\"nombre\":\"[^\"]*\",\"nit\":\"$1\"" | head -1 | grep -o '"id":[0-9]*' | cut -d: -f2
}
dist_de() { # nombre-banco -> distanciaKm (el primero que sigue al nombre en LAST_BODY)
  echo "$LAST_BODY" | grep -o "\"nombre\":\"$1\".*" | grep -o '"distanciaKm":[0-9.]*' | head -1 | cut -d: -f2
}
# asegurar_admin nombre apellido correo doc clave -> ADM_ID. Crea el admin; si ya existe (repeticion) lo busca.
asegurar_admin() {
  paso "Crear administrador $3" POST /api/usuarios/admin-banco "$TOKEN_SUPER" "$(admin_json "$1" "$2" "$3" "$4" "$5")"
  case "$LAST_STATUS" in
    200|201) ADM_CREADO=1; ADM_ID=$(id_de) ;;
    *) ADM_CREADO=0
       paso "Administrador $3 ya existia: buscarlo" GET /api/usuarios/rol/ADMIN_BANCO "$TOKEN_SUPER"
       ADM_ID=$(objeto_con "\"correo\":\"$3\"" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2) ;;
  esac
}
MEDELLIN=$(banco_id 900000001-1); ENVIGADO=$(banco_id 900000004-1); BOGOTA=$(banco_id 900000002-1); BELLO=$(banco_id 900000003-1)
echo "Bancos: Medellin=$MEDELLIN Envigado=$ENVIGADO Bogota=$BOGOTA Bello=$BELLO"

# ══ OBS-02  Donante consulta el historial de otro (PRD §7: acceso por propiedad) ═
caso OBS-02
paso "Control: Ana lee su propio historial" GET "/api/donaciones/usuario/$ANA/historial" "$TOKEN_ANA"
estado_es "Un donante puede leer su propio historial" 200
paso "Ana lee el historial de Omar (otro donante)" GET "/api/donaciones/usuario/$OMAR/historial" "$TOKEN_ANA"
if [ "$LAST_STATUS" = "403" ] || [ "$LAST_STATUS" = "401" ]; then registrar "Se bloquea el historial ajeno" PASA "HTTP $LAST_STATUS"; else registrar "Se bloquea el historial ajeno" FALLA "HTTP $LAST_STATUS; devolvio $(cuenta '"id":') donaciones de Omar con datos clinicos"; fi
paso "Ana lee las donaciones de Omar (sin /historial)" GET "/api/donaciones/usuario/$OMAR" "$TOKEN_ANA"
if [ "$LAST_STATUS" = "403" ] || [ "$LAST_STATUS" = "401" ]; then registrar "Se bloquea la lista de donaciones ajena" PASA "HTTP $LAST_STATUS"; else registrar "Se bloquea la lista de donaciones ajena" FALLA "HTTP $LAST_STATUS"; fi
DON_OMAR=$(echo "$LAST_BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
if [ -n "$DON_OMAR" ]; then
  paso "Ana lee una donacion concreta de Omar por id ($DON_OMAR)" GET "/api/donaciones/$DON_OMAR" "$TOKEN_ANA"
  if [ "$LAST_STATUS" = "403" ] || [ "$LAST_STATUS" = "401" ]; then registrar "Se bloquea la donacion ajena por id" PASA "HTTP $LAST_STATUS"; else registrar "Se bloquea la donacion ajena por id" FALLA "HTTP $LAST_STATUS; $(echo "$LAST_BODY" | grep -o '"hemoglobina":[^,]*\|"presionArterial":"[^"]*"' | tr '\n' ' ')"; fi
fi
paso "Dona90 lee el historial de Ana" GET "/api/donaciones/usuario/$ANA/historial" "$TOKEN_D90"
if [ "$LAST_STATUS" = "403" ] || [ "$LAST_STATUS" = "401" ]; then registrar "Otro donante tampoco puede leer el historial de Ana" PASA "HTTP $LAST_STATUS"; else registrar "Otro donante tampoco puede leer el historial de Ana" FALLA "HTTP $LAST_STATUS"; fi
paso "Ana intenta listar las donaciones de un banco" GET "/api/donaciones/banco/$MEDELLIN" "$TOKEN_ANA"
estado_es "Un donante no puede listar las donaciones de un banco (control de rol)" 403

# ══ OBS-03  Admin de un banco gestiona otro banco ════════════════════════════
caso OBS-03
# Preparacion: la carga asigno a admin.banco TODOS los bancos como administrador; para que la prueba
# sea valida se crea un administrador propio para Envigado y se le asigna ese banco.
asegurar_admin Admin Envigado admin.envigado@test.com 1000000031 'Banco123*'
[ -n "$ADM_ID" ] && registrar "Preparacion: administrador de Envigado disponible" PASA "id $ADM_ID (creado ahora: $ADM_CREADO)" || registrar "Preparacion: administrador de Envigado disponible" FALLA ""
ADM_ENV=$ADM_ID
paso "Preparacion: asignar admin.envigado al banco de Envigado" PUT "/api/bancos/$ENVIGADO" "$TOKEN_SUPER" \
  "{\"nombre\":\"Banco de Sangre Envigado\",\"nit\":\"900000004-1\",\"direccion\":\"Carrera 43A # 35-20\",\"ciudad\":\"Envigado\",\"departamento\":\"Antioquia\",\"telefono\":\"6040000004\",\"correo\":\"contacto.900000004@test.com\",\"latitud\":6.1759,\"longitud\":-75.5917,\"horarioApertura\":\"07:00:00\",\"horarioCierre\":\"18:00:00\",\"activo\":true,\"adminId\":$ADM_ENV}"
estado_es "Envigado queda administrado por admin.envigado" 200
paso "Login admin.envigado" POST /api/v1/auth/login "" "$(login_json admin.envigado@test.com 'Banco123*')"; TOKEN_ENV=$(token)
paso "Verificar que admin.banco ya no administra Envigado" GET "/api/bancos/$ENVIGADO" "$TOKEN_SUPER"
contiene "El administrador de Envigado es admin.envigado" 'admin.envigado@test.com'
no_contiene "admin.banco ya no es administrador de Envigado" '"correo":"admin.banco@test.com"'

paso "Control: admin.envigado crea inventario B- en su banco" POST /api/inventario "$TOKEN_ENV" "{\"bancoId\":$ENVIGADO,\"tipoSangre\":\"B-\",\"unidadesDisponibles\":6,\"unidadesMinimas\":5}"
estado_es "El admin del banco puede gestionar su inventario" 200 201
INV_B=$(id_de)
paso "Control: admin.envigado crea una solicitud en su banco" POST /api/solicitudes "$TOKEN_ENV" \
  "{\"bancoId\":$ENVIGADO,\"tipoSangre\":\"B-\",\"unidadesNecesarias\":2,\"urgencia\":\"BAJA\",\"motivo\":\"Control OBS-03\",\"fechaLimite\":\"$(date -d '+5 days' +%F)\"}"
estado_es "El admin del banco puede crear solicitudes en su banco" 200 201
SOL_ENV=$(id_de)

permite_o_bloquea() { # texto  (esperado 403 ; si 2xx -> FALLA)
  case "$LAST_STATUS" in 403|401) registrar "$1" PASA "HTTP $LAST_STATUS";; 2*) registrar "$1" FALLA "HTTP $LAST_STATUS: la accion se ejecuto";; *) registrar "$1" FALLA "HTTP $LAST_STATUS (respuesta inesperada)";; esac
}
paso "Admin de Medellin crea inventario A- en Envigado" POST /api/inventario "$TOKEN_ADMIN" "{\"bancoId\":$ENVIGADO,\"tipoSangre\":\"A-\",\"unidadesDisponibles\":9,\"unidadesMinimas\":5}"
permite_o_bloquea "Admin de Medellin NO puede crear inventario en Envigado"; INV_A=$(id_de)
paso "Admin de Medellin ajusta inventario B- de Envigado (+1)" PATCH "/api/inventario/ajustar?bancoId=$ENVIGADO&tipoSangre=B-&cantidad=1" "$TOKEN_ADMIN"
permite_o_bloquea "Admin de Medellin NO puede ajustar inventario de Envigado"
paso "Admin de Medellin modifica inventario B- de Envigado (PUT)" PUT "/api/inventario/$INV_B" "$TOKEN_ADMIN" "{\"bancoId\":$ENVIGADO,\"tipoSangre\":\"B-\",\"unidadesDisponibles\":0,\"unidadesMinimas\":5}"
permite_o_bloquea "Admin de Medellin NO puede editar inventario de Envigado"
paso "Admin de Medellin crea solicitud en Envigado" POST /api/solicitudes "$TOKEN_ADMIN" \
  "{\"bancoId\":$ENVIGADO,\"tipoSangre\":\"AB-\",\"unidadesNecesarias\":9,\"urgencia\":\"ALTA\",\"motivo\":\"Prueba OBS-03\",\"fechaLimite\":\"$(date -d '+5 days' +%F)\"}"
permite_o_bloquea "Admin de Medellin NO puede crear solicitudes de Envigado"; SOL_X=$(id_de)
paso "Admin de Medellin cancela la solicitud de Envigado" PATCH "/api/solicitudes/$SOL_ENV/estado?estado=CANCELADA" "$TOKEN_ADMIN"
permite_o_bloquea "Admin de Medellin NO puede cambiar el estado de una solicitud de Envigado"
paso "Admin de Medellin edita la solicitud de Envigado (PUT)" PUT "/api/solicitudes/$SOL_ENV" "$TOKEN_ADMIN" \
  "{\"bancoId\":$ENVIGADO,\"tipoSangre\":\"B-\",\"unidadesNecesarias\":99,\"urgencia\":\"ALTA\",\"motivo\":\"Editada por otro banco\",\"fechaLimite\":\"$(date -d '+5 days' +%F)\",\"estado\":\"ACTIVA\"}"
permite_o_bloquea "Admin de Medellin NO puede editar solicitudes de Envigado"
paso "Admin de Medellin lista las donaciones de Envigado (datos clinicos de donantes)" GET "/api/donaciones/banco/$ENVIGADO" "$TOKEN_ADMIN"
permite_o_bloquea "Admin de Medellin NO puede consultar las donaciones de Envigado"
paso "Admin de Medellin lista las donaciones de Envigado por rango" GET "/api/donaciones/banco/$ENVIGADO/rango?inicio=2020-01-01&fin=$HOY" "$TOKEN_ADMIN"
permite_o_bloquea "Admin de Medellin NO puede consultar por rango las donaciones de Envigado"
paso "Estado final del inventario de Envigado (lectura publica)" GET "/api/inventario/banco/$ENVIGADO"

# Limpieza (super admin): borra lo creado en Envigado por esta prueba
CASO="LIMPIEZA"; mkdir -p "$EVID/LIMPIEZA"
for i in $INV_B $INV_A; do [ -n "$i" ] && paso "limpieza inventario $i" DELETE "/api/inventario/$i" "$TOKEN_SUPER" >/dev/null; done
for s in $SOL_ENV $SOL_X; do [ -n "$s" ] && paso "limpieza solicitud $s" DELETE "/api/solicitudes/$s" "$TOKEN_SUPER" >/dev/null; done
rm -rf "$EVID/LIMPIEZA"

# ══ P-05  Mapa de bancos por radio (SD-06) ═══════════════════════════════════
caso P-05
LAT=6.2442; LON=-75.5812
paso "Radio 50 km desde Medellin" GET "/api/bancos/radio?lat=$LAT&lon=$LON&radioKm=50"
contiene "Envigado esta dentro de 50 km" 'Banco de Sangre Envigado'
contiene "Bello esta dentro de 50 km" 'Banco Prueba Bello'
contiene "Medellin esta dentro de 50 km" 'Banco de Sangre Medell'
no_contiene "Bogota queda fuera de 50 km" 'Banco de Sangre Bogot'
ENV_REP=$(dist_de 'Banco de Sangre Envigado')
ENV_REAL=$(haversine $LAT $LON 6.1759 -75.5917)
if awk -v a="$ENV_REP" -v b="$ENV_REAL" 'BEGIN{d=a-b;if(d<0)d=-d;exit !(d<=0.1)}'; then registrar "La distancia a Envigado coincide con un calculo independiente" PASA "API $ENV_REP km; Haversine $ENV_REAL km"; else registrar "La distancia a Envigado coincide con un calculo independiente" FALLA "API $ENV_REP km; Haversine $ENV_REAL km"; fi
BEL_REP=$(dist_de 'Banco Prueba Bello')
BEL_REAL=$(haversine $LAT $LON 6.3373 -75.5579)
if awk -v a="$BEL_REP" -v b="$BEL_REAL" 'BEGIN{d=a-b;if(d<0)d=-d;exit !(d<=0.1)}'; then registrar "La distancia a Bello coincide con un calculo independiente" PASA "API $BEL_REP km; Haversine $BEL_REAL km"; else registrar "La distancia a Bello coincide con un calculo independiente" FALLA "API $BEL_REP km; Haversine $BEL_REAL km"; fi
PRIMERO=$(echo "$LAST_BODY" | grep -o '"nombre":"[^"]*"' | head -1)
if echo "$PRIMERO" | grep -q 'Medell'; then registrar "El banco mas cercano (Medellin) aparece primero" PASA "$PRIMERO"; else registrar "El banco mas cercano (Medellin) aparece primero" FALLA "$PRIMERO"; fi
contiene "Cada banco trae direccion, telefono y horario para el marcador" '"direccion".*"telefono".*"horarioApertura"'
paso "Radio por defecto (sin parametro; la UI usa 20 km)" GET "/api/bancos/radio?lat=$LAT&lon=$LON"
contiene "Con el radio por defecto aparecen Medellin y Envigado" 'Banco de Sangre Envigado'
no_contiene "Con el radio por defecto no aparece Bogota" 'Banco de Sangre Bogot'
paso "Radio 5 km (solo Medellin, a 0 km)" GET "/api/bancos/radio?lat=$LAT&lon=$LON&radioKm=5"
contiene "Con 5 km aparece Medellin" 'Banco de Sangre Medell'
no_contiene "Con 5 km no aparece Envigado" 'Banco de Sangre Envigado'
paso "Radio 1000 km (incluye Bogota)" GET "/api/bancos/radio?lat=$LAT&lon=$LON&radioKm=1000"
contiene "Con 1000 km aparece Bogota" 'Banco de Sangre Bogot'
paso "Inventario publico del banco de Medellin (informacion del marcador)" GET "/api/inventario/banco/$MEDELLIN"
estado_es "El stock del banco se consulta sin autenticacion" 200
paso "Radio negativo (-5 km)" GET "/api/bancos/radio?lat=$LAT&lon=$LON&radioKm=-5"
observado "Radio negativo: HTTP $LAST_STATUS, $(cuenta '"nombre":') bancos" "PRD no define limites del radio; la UI limita el control deslizante"
bloqueado "Permiso de ubicacion del navegador, centro del mapa, marcadores y circulo (parte de UI)" "no ejecutable por API"

# ══ P-13  Dashboard global (SD-14) ═══════════════════════════════════════════
caso P-13
paso "Metrica 1: todos los bancos" GET /api/bancos "$TOKEN_SUPER"
TOT_B=$(cuenta '"nit":'); ACT_B=$(cuenta '"activo":true')
paso "Metrica 2: bancos activos (consulta publica que usa la UI)" GET /api/bancos/activos
ACT_UI=$(cuenta '"nit":')
paso "Metrica 3: solicitudes activas (consulta publica que usa la UI)" GET /api/solicitudes/activas
SOL_UI=$(cuenta '"estado":"ACTIVA"')
paso "Metrica 4: bajo stock global" GET /api/inventario/bajo-stock "$TOKEN_SUPER"
BAJO_UI=$(cuenta '"bajoStock":true'); BAJO_FILAS=$(cuenta '"tipoSangre":')
paso "Contraste: todas las solicitudes (super admin)" GET /api/solicitudes "$TOKEN_SUPER"
SOL_REAL=$(cuenta '"estado":"ACTIVA"')
BAJO_REAL=0
for b in $MEDELLIN $ENVIGADO $BOGOTA $BELLO; do
  paso "Contraste: inventario del banco $b" GET "/api/inventario/banco/$b"; BAJO_REAL=$((BAJO_REAL+$(cuenta '"bajoStock":true')))
done
[ "$ACT_UI" = "$ACT_B" ] && registrar "Bancos activos de la UI = bancos con activo=true" PASA "$ACT_UI" || registrar "Bancos activos de la UI = bancos con activo=true" FALLA "UI $ACT_UI vs $ACT_B"
[ "$SOL_UI" = "$SOL_REAL" ] && registrar "Solicitudes activas de la UI = ACTIVA en el listado completo" PASA "$SOL_UI" || registrar "Solicitudes activas de la UI = ACTIVA en el listado completo" FALLA "UI $SOL_UI vs $SOL_REAL"
[ "$BAJO_UI" = "$BAJO_REAL" ] && registrar "Tipos bajo stock del panel = suma de bajoStock por banco" PASA "$BAJO_UI" || registrar "Tipos bajo stock del panel = suma de bajoStock por banco" FALLA "panel $BAJO_UI vs $BAJO_REAL"
[ "$BAJO_FILAS" = "$BAJO_UI" ] && registrar "El endpoint de bajo stock global solo devuelve filas en bajo stock" PASA "" || registrar "El endpoint de bajo stock global solo devuelve filas en bajo stock" FALLA "$BAJO_FILAS filas, $BAJO_UI en bajo stock"
observado "Metricas del panel con los datos actuales: bancos=$TOT_B, bancos activos=$ACT_UI, solicitudes activas=$SOL_UI, tipos bajo stock=$BAJO_UI" "PRD no define las metricas (HU-S02 no disponible): consulta funcional"
paso "Un admin de banco no accede a las metricas globales" GET /api/inventario/bajo-stock "$TOKEN_ADMIN"
estado_es "Bajo stock global solo para super admin" 403
bloqueado "Presentacion del panel y accesos rapidos a gestion de bancos y reportes (parte de UI)" "no ejecutable por API"

# ══ P-15  Crear administrador de banco y asociarlo (SD-16) ═══════════════════
caso P-15
asegurar_admin Admin Bello admin.bello@test.com 1000000032 'Banco123*'
if [ "$ADM_CREADO" = "1" ]; then
  registrar "El administrador se crea" PASA "HTTP $LAST_STATUS"
  contiene "Se crea con rol ADMIN_BANCO" '"rol":"ADMIN_BANCO"'
else
  observado "admin.bello ya existia (creado en una ejecucion anterior de este script; la peticion y respuesta de su creacion estan en 00-creacion-admin-bello-1a-ejecucion.txt)" "repeticion"
  contiene "Su rol es ADMIN_BANCO" '"rol":"ADMIN_BANCO"'
fi
ADM_BEL=$ADM_ID
paso "Lista de administradores para el selector del banco" GET /api/usuarios/rol/ADMIN_BANCO "$TOKEN_SUPER"
contiene "admin.bello aparece en el selector" 'admin.bello@test.com'
paso "Asociar admin.bello al banco de Bello" PUT "/api/bancos/$BELLO" "$TOKEN_SUPER" \
  "{\"nombre\":\"Banco Prueba Bello\",\"nit\":\"900000003-1\",\"direccion\":\"Calle 50 # 50-50\",\"ciudad\":\"Bello\",\"departamento\":\"Antioquia\",\"telefono\":\"6040000099\",\"correo\":\"contacto.bello@test.com\",\"latitud\":6.3373,\"longitud\":-75.5579,\"horarioApertura\":\"07:00:00\",\"horarioCierre\":\"18:00:00\",\"activo\":true,\"adminId\":$ADM_BEL}"
estado_es "La asociacion se acepta" 200
paso "Verificar la asociacion" GET "/api/bancos/$BELLO" "$TOKEN_SUPER"
contiene "El banco de Bello muestra a admin.bello como administrador" 'admin.bello@test.com'
paso "Login de admin.bello" POST /api/v1/auth/login "" "$(login_json admin.bello@test.com 'Banco123*')"
estado_es "El nuevo administrador inicia sesion" 200
contiene "Con rol ADMIN_BANCO" '"rol":"ADMIN_BANCO"'; TOKEN_BEL=$(token)
paso "admin.bello consulta las solicitudes de su banco" GET "/api/solicitudes/banco/$BELLO" "$TOKEN_BEL"
estado_es "Accede a su banco" 200
paso "Bancos activos: la UI localiza el banco por admin.id" GET /api/bancos/activos
echo "$LAST_BODY" | grep -o '"nit":"900000003-1"[^]]*"admin":{"id":[0-9]*' | grep -q "\"id\":$ADM_BEL" && registrar "HomeBanco encontraria el banco de Bello para admin.bello (admin.id coincide)" PASA "" || registrar "HomeBanco encontraria el banco de Bello para admin.bello (admin.id coincide)" FALLA "no coincide admin.id"
paso "Validacion: correo repetido" POST /api/usuarios/admin-banco "$TOKEN_SUPER" "$(admin_json Otro Admin admin.bello@test.com 1000000033 'Banco123*')"
rechazado "Correo repetido se rechaza"
paso "Validacion: documento repetido" POST /api/usuarios/admin-banco "$TOKEN_SUPER" "$(admin_json Otro Admin otro.admin@test.com 1000000032 'Banco123*')"
rechazado "Documento repetido se rechaza"
paso "Validacion: contrasena de 7 caracteres" POST /api/usuarios/admin-banco "$TOKEN_SUPER" "$(admin_json Otro Admin otro.admin@test.com 1000000034 'Banco12')"
rechazado "Contrasena corta se rechaza"
paso "Validacion: sin nombre" POST /api/usuarios/admin-banco "$TOKEN_SUPER" "$(admin_json '' Admin otro.admin@test.com 1000000034 'Banco123*')"
rechazado "Sin nombre se rechaza"
paso "Un admin de banco intenta crear otro administrador" POST /api/usuarios/admin-banco "$TOKEN_ADMIN" "$(admin_json Otro Admin otro.admin@test.com 1000000035 'Banco123*')"
estado_es "Solo el super admin crea administradores" 403
bloqueado "Formulario del banco: creacion del administrador y seleccion en el desplegable (parte de UI)" "no ejecutable por API"

# ══ CF-11  Donacion de 200 ml: ¿cuenta como unidad recibida sin sumar stock? ══
caso CF-11
paso "Registrar donante Prueba200b (O+)" POST /api/v1/auth/registro "" "$(registro_json 1000000042 Prueba DoscientosB prueba200b@test.com 3000000042 'Prueba123*' 'O+' 60)"
estado_es "Donante Prueba200 registrado" 200 201
P200=$(uid); TOKEN_P200=$(token)
paso "Inventario O+ antes" GET "/api/inventario/banco/$MEDELLIN"
O_ANTES=$(objeto_con '"tipoSangre":"O+"' | grep -o '"unidadesDisponibles":[0-9]*' | cut -d: -f2)
paso "Solicitud B+ (id 3) antes" GET /api/solicitudes/3 "$TOKEN_ADMIN"
R_ANTES=$(echo "$LAST_BODY" | grep -o '"unidadesRecibidas":[0-9]*' | cut -d: -f2)
echo "    (antes: inventario O+ = $O_ANTES; solicitud B+ recibidas = $R_ANTES)"
paso "Agendar donacion de 200 ml (solicitud B+)" POST /api/donaciones "$TOKEN_P200" "$(donacion_json $P200 3 $HOY 'O+' 200)"
estado_es "La donacion de 200 ml se acepta (minimo permitido)" 200 201
D200=$(id_de)
paso "Completar la donacion de 200 ml" PATCH "/api/donaciones/$D200/estado?estado=COMPLETADA" "$TOKEN_ADMIN"
estado_es "Se completa" 200
paso "Inventario O+ despues" GET "/api/inventario/banco/$MEDELLIN"
O_DESP=$(objeto_con '"tipoSangre":"O+"' | grep -o '"unidadesDisponibles":[0-9]*' | cut -d: -f2)
paso "Solicitud B+ (id 3) despues" GET /api/solicitudes/3 "$TOKEN_ADMIN"
R_DESP=$(echo "$LAST_BODY" | grep -o '"unidadesRecibidas":[0-9]*' | cut -d: -f2)
if [ "$O_DESP" = "$O_ANTES" ]; then registrar "Una donacion de 200 ml no suma stock al inventario" OBSERVADO "O+ $O_ANTES -> $O_DESP (200/450 = 0 unidades, division entera)"; else registrar "Una donacion de 200 ml suma stock al inventario" OBSERVADO "O+ $O_ANTES -> $O_DESP"; fi
if [ "$R_DESP" = "$((R_ANTES+1))" ]; then registrar "Una donacion de 200 ml cuenta como 1 unidad recibida en la solicitud" OBSERVADO "B+ recibidas $R_ANTES -> $R_DESP"; else registrar "La solicitud no cambia con 200 ml" OBSERVADO "B+ recibidas $R_ANTES -> $R_DESP"; fi
if [ "$O_DESP" = "$O_ANTES" ] && [ "$R_DESP" = "$((R_ANTES+1))" ]; then registrar "CF-11 confirmado: 200 ml cuenta como unidad recibida sin sumar stock" OBSERVADO "inconsistencia entre solicitud e inventario"; else registrar "CF-11 no confirmado" OBSERVADO "ver valores"; fi

# ══ P-16 y P-17  Reportes y Excel (Node) ═════════════════════════════════════
echo; echo "== P-16 / P-17 (reportes-excel.cjs)"
node "$DIR/reportes-excel.cjs"
echo; echo "Resumen:"; cut -d'|' -f1,2 "$LOG" | sort | uniq -c

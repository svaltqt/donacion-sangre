#!/usr/bin/env bash
# Ejecuta por API los casos P-01, P-02, P-07, P-10, P-11, P-12 y P-14 con los datos de
# docs/pruebas/set-de-datos.csv. Requiere haber ejecutado antes cargar-datos.sh sobre una
# BD limpia (banco de Medellín id=1, admin.banco@test.com, super.admin@test.com).
#
# Guarda petición y respuesta de cada paso en docs/pruebas/evidencias/P-XX/NN-paso.txt
# (JWT y contraseñas omitidos) y deja el resultado de cada verificación en
# docs/pruebas/evidencias/verificaciones.log  (formato: CASO|PASA/FALLA|texto|detalle).
#
# NO modifica la aplicación. El JSON se envía solo con ASCII (tildes como escapes unicode).
# Nota: el script NO es idempotente (P-01 crea a Ana). Para repetir: borrar backend/data/,
# reiniciar el backend y ejecutar cargar-datos.sh.

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/lib-api.sh"
: > "$LOG"

# ══ P-01  Registro de donante (SD-01, SD-02) ═════════════════════════════════
caso P-01
paso "SD-01 registro de Ana (peso 50 kg, limite)" POST /api/v1/auth/registro "" \
  "$(registro_json 1000000001 Ana Prueba ana.prueba@test.com 3000000001 'Prueba123*' 'O+' 50)"
estado_es "Registro valido con peso 50 kg se acepta" 200 201
contiene "La cuenta se crea con rol DONANTE" '"rol":"DONANTE"'
[ -n "$(token)" ] && registrar "Se devuelve token" PASA "" || registrar "Se devuelve token" FALLA "sin token"
ANA_ID=$(uid)

paso "SD-02a correo repetido (mismos datos de SD-01)" POST /api/v1/auth/registro "" \
  "$(registro_json 1000000001 Ana Prueba ana.prueba@test.com 3000000001 'Prueba123*' 'O+' 50)"
rechazado "2a: correo repetido se rechaza"
contiene "2a: el mensaje menciona el correo" 'correo'

paso "SD-02b documento repetido (datos nuevos)" POST /api/v1/auth/registro "" \
  "$(registro_json 1000000001 Beto Nuevo beto.nuevo@test.com 3000000011 'Prueba123*' 'A+' 70)"
rechazado "2b: documento repetido se rechaza"
contiene "2b: el mensaje menciona el documento" 'documento'

paso "SD-02c peso 49 kg" POST /api/v1/auth/registro "" \
  "$(registro_json 1000000012 Carla Liviana carla.liviana@test.com 3000000012 'Prueba123*' 'B+' 49)"
rechazado "2c: peso 49 kg se rechaza"
contiene "2c: el mensaje indica el minimo de 50 kg" '50'

paso "SD-02d sin latitud ni longitud" POST /api/v1/auth/registro "" \
  "$(registro_json 1000000013 Diana SinUbicacion diana.sinubicacion@test.com 3000000013 'Prueba123*' 'AB+' 60 '' '')"
rechazado "2d: sin ubicacion se rechaza"
contiene "2d: el mensaje indica que la ubicacion es obligatoria" 'latitud\|longitud\|ubicaci'

paso "Comprobacion: las cuentas rechazadas no se crearon (2b/2c/2d)" POST /api/v1/auth/login "" "$(login_json carla.liviana@test.com 'Prueba123*')"
rechazado "La cuenta rechazada por peso no existe"
# ══ P-02  Inicio y cierre de sesion del donante (SD-03) ══════════════════════
caso P-02
paso "Login valido de Ana" POST /api/v1/auth/login "" "$(login_json ana.prueba@test.com 'Prueba123*')"
estado_es "El login valido responde 200" 200
contiene "El rol devuelto es DONANTE (destino /home-donante lo decide la UI)" '"rol":"DONANTE"'
TOKEN_ANA=$(token)
paso "Vista autenticada con token" GET "/api/donaciones/usuario/$ANA_ID/historial" "$TOKEN_ANA"
estado_es "Con sesion se accede a la vista autenticada" 200
paso "Vista autenticada sin token (equivale a sesion cerrada)" GET "/api/donaciones/usuario/$ANA_ID/historial"
estado_es "Sin token se bloquea el acceso" 401 403
paso "Login con clave incorrecta" POST /api/v1/auth/login "" "$(login_json ana.prueba@test.com 'Clave999*')"
rechazado "Clave incorrecta no da acceso"
no_contiene "No se devuelve token con clave incorrecta" '"token"'
paso "Login con correo inexistente" POST /api/v1/auth/login "" "$(login_json noexiste@test.com 'Prueba123*')"
rechazado "Correo inexistente no da acceso"
no_contiene "No se devuelve token con correo inexistente" '"token"'
registrar "Cerrar sesion y redireccion a /login (parte de UI)" NO_EJECUTABLE_POR_API "El cierre de sesion es solo del cliente (borra localStorage); no hay endpoint de logout"

# ══ P-07  Administrador de banco (SD-08) ═════════════════════════════════════
caso P-07
paso "Login valido del administrador de banco" POST /api/v1/auth/login "" "$(login_json admin.banco@test.com 'Banco123*')"
estado_es "El login valido responde 200" 200
contiene "El rol devuelto es ADMIN_BANCO (destino /home-banco lo decide la UI)" '"rol":"ADMIN_BANCO"'
TOKEN_ADMIN=$(token)
paso "Acceso a inventario del banco (opcion /inventario)" GET /api/inventario/banco/1 "$TOKEN_ADMIN"
estado_es "Admin de banco consulta inventario" 200
paso "Acceso a solicitudes del banco (opcion /solicitudes)" GET /api/solicitudes/banco/1 "$TOKEN_ADMIN"
estado_es "Admin de banco consulta solicitudes" 200
paso "Acceso a donaciones del banco" GET /api/donaciones/banco/1 "$TOKEN_ADMIN"
estado_es "Admin de banco consulta donaciones" 200
paso "Admin de banco intenta listar usuarios (solo SUPER_ADMIN)" GET /api/usuarios "$TOKEN_ADMIN"
estado_es "Se bloquea el acceso a funciones de super admin" 403
paso "Login con clave incorrecta" POST /api/v1/auth/login "" "$(login_json admin.banco@test.com 'Clave999*')"
rechazado "Clave incorrecta no da acceso"
no_contiene "No se devuelve token" '"token"'
registrar "Redireccion a /home-banco y opciones de menu (parte de UI)" NO_EJECUTABLE_POR_API "Solo se verifica por API el rol y el acceso a recursos"

# ══ P-10  Inventario del banco (SD-11) ═══════════════════════════════════════
caso P-10
paso "SD-11a crear AB- con 4 disponibles, minimo 5" POST /api/inventario "$TOKEN_ADMIN" \
  '{"bancoId":1,"tipoSangre":"AB-","unidadesDisponibles":4,"unidadesMinimas":5}'
estado_es "El registro AB- se crea" 200 201
contiene "Se guardan 4 unidades disponibles" '"unidadesDisponibles":4'
paso "Listado del inventario del banco" GET /api/inventario/banco/1 "$TOKEN_ADMIN"
contiene "AB- aparece en el inventario" '"tipoSangre":"AB-"'
paso "Bajo stock del banco (AB- = 4 < 5)" GET /api/inventario/banco/1/bajo-stock "$TOKEN_ADMIN"
contiene "AB- esta en bajo stock" '"tipoSangre":"AB-"'
paso "SD-11b crear O+ duplicado" POST /api/inventario "$TOKEN_ADMIN" \
  '{"bancoId":1,"tipoSangre":"O+","unidadesDisponibles":10,"unidadesMinimas":5}'
rechazado "Duplicado banco+tipo se rechaza"
paso "Comprobacion: O+ conserva sus 3 unidades" GET /api/inventario/banco/1 "$TOKEN_ADMIN"
contiene "O+ sigue con 3 disponibles" '"tipoSangre":"O+"[^}]*"unidadesDisponibles":3\|"unidadesDisponibles":3[^}]*"tipoSangre":"O+"'
paso "SD-11c ajustar AB- en +1" PATCH "/api/inventario/ajustar?bancoId=1&tipoSangre=AB-&cantidad=1" "$TOKEN_ADMIN"
estado_es "El ajuste se aplica" 200
contiene "AB- queda con 5 unidades" '"unidadesDisponibles":5'
paso "Bajo stock tras el ajuste (5 = minimo)" GET /api/inventario/banco/1/bajo-stock "$TOKEN_ADMIN"
no_contiene "AB- con 5 = minimo deja de ser bajo stock" '"tipoSangre":"AB-"'
paso "Extra: ajuste que dejaria stock negativo" PATCH "/api/inventario/ajustar?bancoId=1&tipoSangre=AB-&cantidad=-100" "$TOKEN_ADMIN"
rechazado "El ajuste negativo excesivo se rechaza (no esta en SD-11)"

# ══ P-11  Solicitudes de urgencia (SD-12) ════════════════════════════════════
caso P-11
F7=$(date -d "+7 days" +%F)
F7B=$(date -d "+10 days" +%F)
SOL_JSON="{\"bancoId\":1,\"tipoSangre\":\"O-\",\"unidadesNecesarias\":3,\"urgencia\":\"ALTA\",\"motivo\":\"Cirug${U}00eda programada\",\"pacienteReferencia\":\"PAC-001\",\"fechaLimite\":\"$F7\"}"
paso "SD-12 crear solicitud O- ALTA" POST /api/solicitudes "$TOKEN_ADMIN" "$SOL_JSON"
estado_es "La solicitud se crea" 200 201
contiene "Estado inicial ACTIVA" '"estado":"ACTIVA"'
contiene "Radio por defecto 50 km" '"radioBusquedaKm":50'
SOL_ID=$(echo "$LAST_BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
paso "Vista del donante: urgencias activas" GET /api/solicitudes/activas "$TOKEN_ANA"
contiene "La solicitud nueva aparece al donante" "\"id\":$SOL_ID"
paso "Editar la solicitud (3 -> 4 unidades, urgencia MEDIA, fecha +10 dias)" PUT "/api/solicitudes/$SOL_ID" "$TOKEN_ADMIN" \
  "{\"bancoId\":1,\"tipoSangre\":\"O-\",\"unidadesNecesarias\":4,\"urgencia\":\"MEDIA\",\"motivo\":\"Cirug${U}00eda programada\",\"pacienteReferencia\":\"PAC-001\",\"fechaLimite\":\"$F7B\",\"estado\":\"ACTIVA\"}"
estado_es "La edicion se acepta" 200
contiene "Se guardan 4 unidades" '"unidadesNecesarias":4'
contiene "Se guarda la urgencia MEDIA" '"urgencia":"MEDIA"'
paso "Marcar como COMPLETADA" PATCH "/api/solicitudes/$SOL_ID/estado?estado=COMPLETADA" "$TOKEN_ADMIN"
estado_es "El cambio de estado se acepta" 200
contiene "Estado COMPLETADA" '"estado":"COMPLETADA"'
paso "Vista del donante tras completar" GET /api/solicitudes/activas "$TOKEN_ANA"
no_contiene "La solicitud completada ya no aparece al donante" "\"id\":$SOL_ID,"
paso "Crear segunda solicitud para cancelarla" POST /api/solicitudes "$TOKEN_ADMIN" "$SOL_JSON"
SOL2_ID=$(echo "$LAST_BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
paso "Cancelar la segunda solicitud" PATCH "/api/solicitudes/$SOL2_ID/estado?estado=CANCELADA" "$TOKEN_ADMIN"
contiene "Estado CANCELADA" '"estado":"CANCELADA"'
paso "Vista del donante tras cancelar" GET /api/solicitudes/activas "$TOKEN_ANA"
no_contiene "La solicitud cancelada ya no aparece al donante" "\"id\":$SOL2_ID,"
paso "Donante intenta crear una solicitud" POST /api/solicitudes "$TOKEN_ANA" "$SOL_JSON"
estado_es "Un donante no puede crear solicitudes" 403

# ══ P-12  Superadministrador (SD-13) ═════════════════════════════════════════
caso P-12
paso "Login valido del superadmin" POST /api/v1/auth/login "" "$(login_json super.admin@test.com 'Admin123*')"
estado_es "El login valido responde 200" 200
contiene "El rol devuelto es SUPER_ADMIN (destino /super-admin lo decide la UI)" '"rol":"SUPER_ADMIN"'
TOKEN_SUPER=$(token)
paso "Super admin: listar bancos (opcion /super-admin/bancos)" GET /api/bancos "$TOKEN_SUPER"
estado_es "Accede a la gestion de bancos" 200
paso "Super admin: listar usuarios" GET /api/usuarios "$TOKEN_SUPER"
estado_es "Accede a usuarios" 200
paso "Super admin: bajo stock global" GET /api/inventario/bajo-stock "$TOKEN_SUPER"
estado_es "Accede al bajo stock global" 200
paso "Super admin: todas las donaciones (datos de reportes)" GET /api/donaciones "$TOKEN_SUPER"
estado_es "Accede a las donaciones (base de /super-admin/reportes)" 200
paso "Donante intenta listar bancos (solo SUPER_ADMIN)" GET /api/bancos "$TOKEN_ANA"
estado_es "Se bloquea al donante" 403
paso "Admin de banco intenta listar bancos (solo SUPER_ADMIN)" GET /api/bancos "$TOKEN_ADMIN"
estado_es "Se bloquea al admin de banco" 403
paso "Login con clave incorrecta" POST /api/v1/auth/login "" "$(login_json super.admin@test.com 'Clave999*')"
rechazado "Clave incorrecta no da acceso"
no_contiene "No se devuelve token" '"token"'
registrar "Redireccion a /super-admin y acceso a /super-admin/reportes (parte de UI)" NO_EJECUTABLE_POR_API "El reporte y la exportacion a Excel se generan en el cliente"

# ══ P-14  Gestion de bancos (SD-15) ══════════════════════════════════════════
caso P-14
# [SUPUESTO] direccion, telefono, correo, coordenadas de Bello y horario; adminId=1 (admin.banco)
BELLO_JSON="{\"nombre\":\"Banco Prueba Bello\",\"nit\":\"900000003-1\",\"direccion\":\"Calle 50 # 50-50\",\"ciudad\":\"Bello\",\"departamento\":\"Antioquia\",\"telefono\":\"6040000003\",\"correo\":\"contacto.bello@test.com\",\"latitud\":6.3373,\"longitud\":-75.5579,\"horarioApertura\":\"07:00:00\",\"horarioCierre\":\"18:00:00\",\"activo\":true,\"adminId\":1}"
paso "SD-15 crear Banco Prueba Bello" POST /api/bancos "$TOKEN_SUPER" "$BELLO_JSON"
estado_es "El banco se crea" 200 201
BELLO_ID=$(echo "$LAST_BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
paso "Listado de bancos (tabla)" GET /api/bancos "$TOKEN_SUPER"
contiene "Bello aparece en la tabla" 'Banco Prueba Bello'
paso "Precarga para editar: obtener banco" GET "/api/bancos/$BELLO_ID" "$TOKEN_SUPER"
contiene "Se precargan nombre y NIT" '"nit":"900000003-1"'
paso "Editar Bello (telefono 6040000099)" PUT "/api/bancos/$BELLO_ID" "$TOKEN_SUPER" "${BELLO_JSON/6040000003/6040000099}"
estado_es "La edicion se acepta" 200
paso "Verificar que la edicion persiste" GET "/api/bancos/$BELLO_ID" "$TOKEN_SUPER"
contiene "El telefono nuevo se guarda" '6040000099'
paso "Filtro por ciudad: Bello" GET "/api/bancos/ciudad/Bello" "$TOKEN_SUPER"
contiene "Devuelve Bello" 'Banco Prueba Bello'
no_contiene "No devuelve bancos de otras ciudades" 'Banco de Sangre'
paso "Filtro por ciudad: Medellin" GET "/api/bancos/ciudad/Medell%C3%ADn" "$TOKEN_SUPER"
contiene "Devuelve el banco de Medellin" 'Banco de Sangre Medell'
no_contiene "No devuelve Bello" 'Banco Prueba Bello'
paso "NIT repetido" POST /api/bancos "$TOKEN_SUPER" "${BELLO_JSON/Banco Prueba Bello/Otro Banco}"
rechazado "NIT duplicado se rechaza"
paso "Desactivar Bello" PATCH "/api/bancos/$BELLO_ID/desactivar" "$TOKEN_SUPER"
estado_es "La desactivacion se acepta" 200 204
paso "Consulta publica de bancos activos (vista del donante)" GET /api/bancos/activos
no_contiene "Bello desactivado ya no aparece" 'Banco Prueba Bello'
contiene "Los demas bancos siguen visibles" 'Banco de Sangre Medell'
paso "Consulta publica por radio (50 km de Bello)" GET "/api/bancos/radio?lat=6.3373&lon=-75.5579&radioKm=50"
no_contiene "Bello desactivado no aparece en el radio" 'Banco Prueba Bello'
paso "Restauracion (no es parte del caso): reactivar Bello para P-15" PUT "/api/bancos/$BELLO_ID" "$TOKEN_SUPER" "$BELLO_JSON"

echo; echo "Resumen:"; cut -d'|' -f1,2 "$LOG" | sort | uniq -c

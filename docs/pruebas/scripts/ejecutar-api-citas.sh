#!/usr/bin/env bash
# Ejecuta por API los casos P-06, P-08, P-09 y P-18 (agendamiento, citas, completar/rechazar
# donaciones y flujo end-to-end). Datos: SD-07, SD-09, SD-10 y SD-19.
# Requiere cargar-datos.sh + ejecutar-api.sh ya ejecutados (usa el banco 1, las solicitudes
# 1 (O- ALTA) y 2 (A+ MEDIA) de SD-05 y el inventario de SD-09/SD-11).
# Resultado de las verificaciones: evidencias/verificaciones-citas.log
#
# "Cita" = donación en estado PENDIENTE; "agendar" = POST /api/donaciones (lo que hace
# UrgenciaCard.jsx tras el triaje o el botón SALTAR). Ver resultados.md, Observación 1.
#
# Repetible hasta P-06 (registro y siembra son tolerantes); tras completar P-18 hay que reiniciar la BD.
# [SUPUESTO] Donantes nuevos (Dona89, Dona90, Omar), historial sembrado como ADMIN_BANCO
# con fecha pasada, datos clínicos de SD-19 (14.0 g/dL, 118/78).
# El triaje con IA (POST /api/claude/chat) NO se ejecuta: gemini.api.key es un valor
# ficticio en local y la llamada saldría a un servicio externo.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$(cd "$DIR/.." && pwd)/evidencias/verificaciones-citas.log"
source "$DIR/lib-api.sh"
: > "$LOG"

HOY=$(date +%F); MANANA=$(date -d "+1 day" +%F)
F89=$(date -d "-89 days" +%F); F90=$(date -d "-90 days" +%F)

CASO="PREP"; mkdir -p "$EVID/PREP"
paso "Login admin de banco" POST /api/v1/auth/login "" "$(login_json admin.banco@test.com 'Banco123*')"
TOKEN_ADMIN=$(token)
paso "Login super admin" POST /api/v1/auth/login "" "$(login_json super.admin@test.com 'Admin123*')"
TOKEN_SUPER=$(token)
[ -n "$TOKEN_ADMIN" ] && [ -n "$TOKEN_SUPER" ] || { echo "Sin tokens: ¿se ejecutó cargar-datos.sh?"; exit 1; }
rm -rf "$EVID/PREP"

donacion_json() { # usuarioId solicitudId|null fecha tipo [extra]
  echo "{\"usuarioId\":$1,\"bancoId\":1,\"solicitudId\":$2,\"fechaDonacion\":\"$3\",\"tipoSangre\":\"$4\",\"cantidadMl\":450${5-}}"
}
id_de() { echo "$LAST_BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2; }
# unidades/recibidas dejan el valor en UNI/REC (sin subshell, para que paso numere bien las evidencias)
unidades() { # tipo -> UNI = unidades disponibles en el banco 1
  paso "Leer inventario del banco 1" GET /api/inventario/banco/1 "$TOKEN_ADMIN"
  UNI=$(objeto_con "\"tipoSangre\":\"$1\"" | grep -o '"unidadesDisponibles":[0-9]*' | cut -d: -f2)
}
recibidas() { # solicitudId -> REC = unidades recibidas
  paso "Leer solicitud $1" GET "/api/solicitudes/$1" "$TOKEN_ADMIN"
  REC=$(echo "$LAST_BODY" | grep -o '"unidadesRecibidas":[0-9]*' | cut -d: -f2)
}
registrar_donante() { # doc nombre apellido correo sangre  (si ya existe, inicia sesion)
  paso "Registrar donante $2 $3" POST /api/v1/auth/registro "" "$(registro_json "$1" "$2" "$3" "$4" "30000000${1: -2}" 'Prueba123*' "$5" 60)"
  case "$LAST_STATUS" in
    200|201) registrar "Donante $2 $3 registrado" PASA "HTTP $LAST_STATUS" ;;
    *) paso "Donante $2 $3 ya existia: login" POST /api/v1/auth/login "" "$(login_json "$4" 'Prueba123*')"
       estado_es "Donante $2 $3 ya existia y puede iniciar sesion" 200 ;;
  esac
}
sembrar_historial() { # usuarioId token fecha descripcion (solo si no tiene COMPLETADA)
  paso "Historial previo $4" GET "/api/donaciones/usuario/$1/historial" "$2"
  if echo "$LAST_BODY" | grep -q COMPLETADA; then observado "Historial ya sembrado ($4)" "ejecucion repetida"; return; fi
  paso "Preparacion SD-07: ultima donacion COMPLETADA $4" POST /api/donaciones "$TOKEN_ADMIN"     "$(donacion_json $1 null $3 'O+' ',"estado":"COMPLETADA"')"
  estado_es "Se siembra el historial ($4)" 200 201
}

# ══ P-06  Triaje y programación (SD-07) ══════════════════════════════════════
caso P-06
registrar_donante 1000000021 Dona Ochentaynueve dona89@test.com 'O+'; D89=$(uid)
registrar_donante 1000000022 Dona Noventa dona90@test.com 'O+'; D90=$(uid); TOKEN_D90=$(token)
paso "Login Dona89" POST /api/v1/auth/login "" "$(login_json dona89@test.com 'Prueba123*')"; TOKEN_D89=$(token)
sembrar_historial $D89 "$TOKEN_D89" $F89 "hace 89 dias (Dona89)"
sembrar_historial $D90 "$TOKEN_D90" $F90 "hace 90 dias (Dona90)"

paso "Matching de la solicitud 2 (A+): donantes compatibles y aptitud" GET /api/matching/solicitud/2 "$TOKEN_ADMIN"
if objeto_con 'Noventa' | grep -q '"aptoParaDonar":true'; then registrar "Matching: la donante de 90 dias figura apta" PASA ""; else registrar "Matching: la donante de 90 dias figura apta" FALLA "$(objeto_con Noventa)"; fi
if objeto_con 'Ochentaynueve' | grep -q '"aptoParaDonar":false'; then registrar "Matching: la donante de 89 dias figura NO apta" PASA ""; else registrar "Matching: la donante de 89 dias figura NO apta" FALLA "$(objeto_con Ochentaynueve)"; fi

bloqueado "Triaje con DonaBot (IA) y paso de agenda tras triaje" "gemini.api.key=sin-usar-local en application.properties; ademas es interfaz. No se llamo a /api/claude/chat"

paso "SD-07 90 dias: agendar cita (Dona90, hoy, solicitud A+)" POST /api/donaciones "$TOKEN_D90" "$(donacion_json $D90 2 $HOY 'O+')"
estado_es "Con 90 dias exactos se permite el registro" 200 201
contiene "La cita queda en estado PENDIENTE" '"estado":"PENDIENTE"'
CITA90=$(id_de)
observado "El backend registra la cita sin ningun dato de triaje (la peticion no lo incluye ni se exige); equivale al efecto de SALTAR" "Ver consulta funcional CF-08"
paso "Verificar asociacion de la cita" GET "/api/donaciones/$CITA90" "$TOKEN_D90"
contiene "Asociada a la solicitud 2" '"solicitudId":2'
contiene "Asociada al banco 1" '"bancoId":1'
paso "Citas de la solicitud 2" GET /api/donaciones/solicitud/2 "$TOKEN_ADMIN"
contiene "La cita aparece en la solicitud" "\"id\":$CITA90,"

paso "SD-07 89 dias: agendar cita (Dona89, hoy)" POST /api/donaciones "$TOKEN_D89" "$(donacion_json $D89 2 $HOY 'O+')"
rechazado "Con 89 dias se rechaza el registro"
contiene "El mensaje informa los dias restantes" 'esperar 1 d'
paso "Comprobacion: no se creo cita para Dona89" GET "/api/donaciones/usuario/$D89" "$TOKEN_D89"
if [ "$(cuenta '"id":')" = "1" ]; then registrar "Dona89 solo conserva la donacion sembrada" PASA ""; else registrar "Dona89 solo conserva la donacion sembrada" FALLA "$(cuenta '"id":') registros"; fi

paso "Extra: Dona89 agenda para MANANA (el intervalo hasta esa fecha seria 90 dias)" POST /api/donaciones "$TOKEN_D89" "$(donacion_json $D89 2 $MANANA 'O+')"
if [ "$LAST_STATUS" = "201" ] || [ "$LAST_STATUS" = "200" ]; then
  CITA89=$(id_de)
  observado "El backend acepta agendar con fecha futura que cumple los 90 dias; la UI solo compara contra HOY y mostraria NO_PUEDE" "Ver consulta funcional CF-09"
else
  CITA89=""; observado "El backend rechaza la fecha futura de Dona89" "HTTP $LAST_STATUS $LAST_BODY"
fi
observado "Texto del mensaje de dias restantes: 'esperar 1 días' (plural incorrecto, cosmetico)" "El donante debe esperar 1 días más para volver a donar."

# ══ P-08  Dashboard del banco (SD-09) ════════════════════════════════════════
caso P-08
paso "Inventario del banco 1 (alertas de stock)" GET /api/inventario/banco/1 "$TOKEN_ADMIN"
if objeto_con '"tipoSangre":"O+"' | grep -q '"bajoStock":true'; then registrar "O+ (3 de minimo 5) marcado como bajo stock" PASA ""; else registrar "O+ (3 de minimo 5) marcado como bajo stock" FALLA "$(objeto_con '"tipoSangre":"O+"')"; fi
if objeto_con '"tipoSangre":"A+"' | grep -q '"bajoStock":false'; then registrar "A+ (10 de minimo 5) NO marcado como bajo stock" PASA ""; else registrar "A+ (10 de minimo 5) NO marcado como bajo stock" FALLA "$(objeto_con '"tipoSangre":"A+"')"; fi
TOTAL=$(echo "$LAST_BODY" | grep -o '"unidadesDisponibles":[0-9]*' | cut -d: -f2 | awk '{s+=$1} END{print s}')
BAJOS=$(cuenta '"bajoStock":true')
paso "Donaciones del banco 1 (fuente de las citas pendientes)" GET /api/donaciones/banco/1 "$TOKEN_ADMIN"
PEND=$(cuenta '"estado":"PENDIENTE"')
if [ "$PEND" -ge 1 ]; then registrar "Hay al menos una donacion PENDIENTE (cita) en el banco" PASA "$PEND pendientes"; else registrar "Hay al menos una donacion PENDIENTE (cita) en el banco" FALLA "0 pendientes"; fi
paso "Donaciones PENDIENTES (consulta por estado)" GET /api/donaciones/estado/PENDIENTE "$TOKEN_ADMIN"
if [ "$(cuenta '"estado":"PENDIENTE"')" = "$PEND" ]; then registrar "El conteo por estado coincide con el del banco" PASA ""; else registrar "El conteo por estado coincide con el del banco" FALLA ""; fi
paso "Solicitudes del banco 1" GET /api/solicitudes/banco/1 "$TOKEN_ADMIN"
ACT=$(cuenta '"estado":"ACTIVA"')
observado "Metricas que la UI derivaria de la API: unidades totales=$TOTAL, tipos en bajo stock=$BAJOS, citas pendientes=$PEND, solicitudes activas=$ACT" "PRD no define las metricas del dashboard: consulta funcional CF-10"
bloqueado "Presentacion del dashboard (/home-banco), citas pendientes y alerta visual (parte de UI)" "no ejecutable por API"

# ══ P-09  Completar o rechazar una donacion (SD-10) ══════════════════════════
caso P-09
unidades 'O+'; O_ANTES=$UNI; recibidas 2; R_ANTES=$REC
echo "    (antes: O+ = $O_ANTES unidades; solicitud 2 recibidas = $R_ANTES)"
paso "SD-10 completar: guardar datos clinicos (450 ml, 13.5 g/dL, 120/80)" PUT "/api/donaciones/$CITA90" "$TOKEN_ADMIN" \
  "$(donacion_json $D90 2 $HOY 'O+' ',"hemoglobina":13.5,"presionArterial":"120/80","observaciones":"SD-10","estado":"PENDIENTE"')"
estado_es "Los datos clinicos se aceptan" 200
paso "SD-10 completar: pasar a COMPLETADA" PATCH "/api/donaciones/$CITA90/estado?estado=COMPLETADA" "$TOKEN_ADMIN"
estado_es "El cambio de estado se acepta" 200
contiene "Estado COMPLETADA" '"estado":"COMPLETADA"'
paso "Verificar datos guardados" GET "/api/donaciones/$CITA90" "$TOKEN_ADMIN"
contiene "Se guardan 450 ml" '"cantidadMl":450'
contiene "Se guarda la hemoglobina 13.5" '"hemoglobina":13.5'
contiene "Se guarda la presion 120/80" '"presionArterial":"120/80"'
unidades 'O+'; O_DESP=$UNI
if [ "$O_DESP" = "$((O_ANTES+1))" ]; then registrar "El inventario O+ aumenta en 1 unidad al completar" PASA "$O_ANTES -> $O_DESP"; else registrar "El inventario O+ aumenta en 1 unidad al completar" FALLA "$O_ANTES -> $O_DESP"; fi
recibidas 2; R_DESP=$REC
observado "Solicitud A+ (id 2): unidades recibidas $R_ANTES -> $R_DESP al completar una donacion de donante O+" "La donacion suma al inventario O+ y a la solicitud A+: consulta funcional CF-11"
paso "Extra: completar de nuevo la misma donacion" PATCH "/api/donaciones/$CITA90/estado?estado=COMPLETADA" "$TOKEN_ADMIN"
unidades 'O+'; O_DOBLE=$UNI
if [ "$O_DOBLE" = "$O_DESP" ]; then registrar "Completar dos veces no duplica el inventario" PASA ""; else registrar "Completar dos veces no duplica el inventario" FALLA "$O_DESP -> $O_DOBLE"; fi

if [ -n "$CITA89" ]; then
  paso "SD-10 rechazar: pasar la otra cita a RECHAZADA" PATCH "/api/donaciones/$CITA89/estado?estado=RECHAZADA" "$TOKEN_ADMIN"
  estado_es "El rechazo se acepta" 200
  contiene "Estado RECHAZADA" '"estado":"RECHAZADA"'
  unidades 'O+'; O_RECH=$UNI
  if [ "$O_RECH" = "$O_DOBLE" ]; then registrar "El inventario no cambia al rechazar" PASA "$O_RECH"; else registrar "El inventario no cambia al rechazar" FALLA "$O_DOBLE -> $O_RECH"; fi
  recibidas 2
  if [ "$REC" = "$R_DESP" ]; then registrar "La solicitud no cambia al rechazar" PASA ""; else registrar "La solicitud no cambia al rechazar" FALLA ""; fi
else
  bloqueado "Rechazar una cita PENDIENTE (SD-10, segunda donacion)" "no se pudo crear la segunda cita en P-06"
fi
observado "Datos clinicos: el backend solo valida hemoglobina 7.0-25.0 y 200-550 ml; no hay umbral de aptitud clinica ni validacion de la presion (texto libre)" "SD-10 lo anticipa: no hay umbrales clinicos definidos"
bloqueado "Modal de finalizacion en HomeBanco (campos, mensajes) (parte de UI)" "no ejecutable por API"

# ══ P-18  Flujo end-to-end (SD-19) ═══════════════════════════════════════════
caso P-18
registrar_donante 1000000023 Omar Negativo omar.negativo@test.com 'O-'; OMAR=$(uid); TOKEN_OMAR=$(token)
paso "Matching de la solicitud 1 (O-)" GET /api/matching/solicitud/1 "$TOKEN_ADMIN"
if objeto_con 'Negativo' | grep -q '"aptoParaDonar":true'; then registrar "Omar (O-) figura compatible y apto" PASA ""; else registrar "Omar (O-) figura compatible y apto" FALLA "$(objeto_con Negativo)"; fi
paso "Historial de Omar antes de donar" GET "/api/donaciones/usuario/$OMAR/historial" "$TOKEN_OMAR"
if [ "$LAST_BODY" = "[]" ]; then registrar "Omar no tiene donaciones previas" PASA ""; else registrar "Omar no tiene donaciones previas" FALLA "$LAST_BODY"; fi
bloqueado "Paso 1: completar el triaje (DonaBot, IA)" "gemini.api.key ficticia en local; se agenda directamente por API"
recibidas 1; R1_ANTES=$REC
paso "1. Donante: agendar cita (solicitud O- id 1, banco Medellin)" POST /api/donaciones "$TOKEN_OMAR" "$(donacion_json $OMAR 1 $HOY 'O-')"
estado_es "La cita se crea" 200 201
contiene "Estado PENDIENTE" '"estado":"PENDIENTE"'
CITA_O=$(id_de)
paso "2. Asociacion: citas de la solicitud 1" GET /api/donaciones/solicitud/1 "$TOKEN_ADMIN"
contiene "La cita aparece asociada a la solicitud" "\"id\":$CITA_O,"
paso "2. Asociacion: donaciones del banco 1" GET /api/donaciones/banco/1 "$TOKEN_ADMIN"
contiene "La cita aparece asociada al banco" "\"id\":$CITA_O,"
paso "2. Asociacion: historial de Omar" GET "/api/donaciones/usuario/$OMAR/historial" "$TOKEN_OMAR"
contiene "La cita aparece en el historial del donante" "\"id\":$CITA_O,"
paso "Inventario antes de completar" GET /api/inventario/banco/1 "$TOKEN_ADMIN"
OM_FILA_ANTES=$(cuenta '"tipoSangre":"O-"')
echo "    (filas de inventario O- en el banco 1: $OM_FILA_ANTES)"
paso "3. Admin: guardar datos clinicos (14.0 g/dL, 118/78)" PUT "/api/donaciones/$CITA_O" "$TOKEN_ADMIN" \
  "$(donacion_json $OMAR 1 $HOY 'O-' ',"hemoglobina":14.0,"presionArterial":"118/78","observaciones":"SD-19","estado":"PENDIENTE"')"
estado_es "Los datos clinicos se aceptan" 200
paso "3. Admin: completar la donacion" PATCH "/api/donaciones/$CITA_O/estado?estado=COMPLETADA" "$TOKEN_ADMIN"
estado_es "La donacion se completa" 200
contiene "Estado COMPLETADA" '"estado":"COMPLETADA"'
recibidas 1; R1_DESP=$REC
if [ "$R1_DESP" = "$((R1_ANTES+1))" ]; then registrar "La solicitud O- suma 1 unidad recibida" PASA "$R1_ANTES -> $R1_DESP"; else registrar "La solicitud O- suma 1 unidad recibida" FALLA "$R1_ANTES -> $R1_DESP"; fi
contiene "La solicitud sigue ACTIVA (1 de 5 recibidas)" '"estado":"ACTIVA"'
paso "4. Inventario despues de completar" GET /api/inventario/banco/1 "$TOKEN_ADMIN"
OM_FILA_DESP=$(cuenta '"tipoSangre":"O-"')
if [ "$OM_FILA_ANTES" = "0" ] && [ "$OM_FILA_DESP" = "0" ]; then
  observado "Efecto en inventario no verificable: el banco no tiene fila de inventario O- (SD-19 no la define); al completar la donacion no se crea ni se suma stock y no hay aviso" "Consulta funcional CF-12"
else
  observado "Inventario O- tras completar" "$(objeto_con '"tipoSangre":"O-"')"
fi
paso "5. Super admin: todas las donaciones" GET /api/donaciones "$TOKEN_SUPER"
contiene "La donacion completada figura en el listado global" "\"id\":$CITA_O,"
paso "5. Super admin: donaciones del banco 1 en el rango de hoy" GET "/api/donaciones/banco/1/rango?inicio=$HOY&fin=$HOY" "$TOKEN_SUPER"
contiene "La donacion figura en el reporte por rango" "\"id\":$CITA_O,"
bloqueado "Paso 5: pantalla de reportes y exportacion a Excel (parte de UI)" "no ejecutable por API"
paso "Extra: Omar intenta donar otra vez hoy (intervalo de 90 dias)" POST /api/donaciones "$TOKEN_OMAR" "$(donacion_json $OMAR 1 $HOY 'O-')"
rechazado "La segunda donacion se rechaza por el intervalo de 90 dias"
paso "Extra: matching tras donar" GET /api/matching/solicitud/1 "$TOKEN_ADMIN"
if objeto_con 'Negativo' | grep -q '"aptoParaDonar":false'; then registrar "Omar deja de figurar apto" PASA ""; else registrar "Omar deja de figurar apto" FALLA "$(objeto_con Negativo)"; fi

echo; echo "Resumen:"; cut -d'|' -f1,2 "$LOG" | sort | uniq -c

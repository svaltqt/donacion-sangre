#!/usr/bin/env bash
# Carga el set de datos de docs/pruebas/set-de-datos.csv en el backend local (H2).
#   Usuarios: SD-08 (ADMIN_BANCO), SD-13 (SUPER_ADMIN)
#   Bancos:   SD-06 (Envigado, Bogotá), SD-08/SD-15 (Medellín)
#   Inventario: SD-09     Solicitudes: SD-05
#
# NO carga SD-01 (Ana Prueba): se crea durante P-01.
# NO carga "Banco Prueba Bello": lo crea P-14.
#
# Nota: el JSON se envia solo con ASCII (tildes como escapes unicode) porque en Windows
# curl puede enviar bytes que el backend rechaza como UTF-8 invalido.
#
# Requisitos: backend en $API (por defecto http://localhost:8081) con la BD H2 recién
# creada (roles: 1=DONANTE, 2=ADMIN_BANCO, 3=SUPER_ADMIN, según data-h2.sql).
#
# ⚠ DEPENDENCIA DEL BUG-01 (docs/pruebas/resultados.md):
#   /api/v1/auth/registro acepta `rolId` sin autenticación. Este script lo aprovecha
#   para crear los usuarios ADMIN_BANCO y SUPER_ADMIN (rolId=2 y rolId=3). Si BUG-01 se
#   corrige, esta carga dejará de funcionar y habrá que sembrar los usuarios por SQL
#   (hash BCrypt) en data-h2.sql.
#
# ⚠ SUPUESTOS: todo dato marcado con [SUPUESTO] NO viene del set de datos; se inventó
#   porque la API lo exige o porque el CSV no lo indica.
#
# Idempotente: si un usuario o banco ya existe, no lo duplica; inventario y solicitudes
# solo se cargan cuando el banco de Medellín se crea en esta ejecución.

set -u
API="${API:-http://localhost:8081}"
EVID="$(cd "$(dirname "$0")/.." && pwd)/evidencias/BUG-01"

ROL_DONANTE=1; ROL_ADMIN_BANCO=2; ROL_SUPER_ADMIN=3

# Extrae el primer valor numérico de "id" de un JSON; el token con "token":"..."
primer_id() { grep -o '"id":[0-9]*' | head -1 | cut -d: -f2; }
token_de()  { grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4; }

# req METODO RUTA [TOKEN] [CUERPO] -> imprime "<cuerpo>\n<status>"
req() {
  local metodo="$1" ruta="$2" token="${3:-}" cuerpo="${4:-}"
  local args=(-s -X "$metodo" -w '\n%{http_code}' -H 'Content-Type: application/json')
  [ -n "$token" ]  && args+=(-H "Authorization: Bearer $token")
  [ -n "$cuerpo" ] && args+=(-d "$cuerpo")
  curl "${args[@]}" "$API$ruta"
}
cuerpo_de() { sed '$d'; }
status_de() { tail -n1; }

fallo() { echo "ERROR: $1" >&2; echo "$2" >&2; exit 1; }

curl -s -o /dev/null "$API/api/bancos/activos" || fallo "Backend no responde en $API" ""

# ── 1. Usuarios ──────────────────────────────────────────────────────────────
# registrar_usuario NOMBRE APELLIDO CORREO CLAVE ROL_ID DOC CELULAR TIPO_SANGRE
# Si el correo ya existe, hace login. Imprime el JSON de la respuesta de auth.
# Datos personales no indicados en el CSV: [SUPUESTO] documento, celular, tipo de sangre,
# nacimiento, género, peso, ubicación (Medellín, igual que SD-01).
registrar_usuario() {
  local nombre="$1" apellido="$2" correo="$3" clave="$4" rol="$5" doc="$6" cel="$7" sangre="$8"
  local cuerpo
  cuerpo=$(cat <<JSON
{"tipoDocumento":"CC","numeroDocumento":"$doc","nombre":"$nombre","apellido":"$apellido",
 "correo":"$correo","celular":"$cel","contrasena":"$clave","tipoSangre":"$sangre",
 "fechaNacimiento":"1985-01-15","genero":"MASCULINO","pesoKg":70,
 "latitud":6.2442,"longitud":-75.5812,"ciudad":"Medell\u00edn","departamento":"Antioquia",
 "rolId":$rol}
JSON
)
  local r; r=$(req POST /api/v1/auth/registro "" "$cuerpo")
  if [ "$(echo "$r" | status_de)" = "201" ] || [ "$(echo "$r" | status_de)" = "200" ]; then
    # Evidencia BUG-01: el registro público con rolId de SUPER_ADMIN (sin Authorization).
    if [ "$rol" = "$ROL_SUPER_ADMIN" ]; then
      mkdir -p "$EVID"
      {
        echo "# Petición (sin cabecera Authorization)"
        echo "POST $API/api/v1/auth/registro"
        echo "Content-Type: application/json"
        echo
        echo "$cuerpo" | sed 's/"contrasena":"[^"]*"/"contrasena":"<omitida>"/'
        echo
        echo "# Respuesta (HTTP $(echo "$r" | status_de)); el JWT se sustituye por <JWT>"
        echo "$r" | cuerpo_de | sed 's/"token":"[^"]*"/"token":"<JWT>"/'
      } > "$EVID/peticion-respuesta.txt"
      echo "  evidencia BUG-01 -> $EVID/peticion-respuesta.txt" >&2
    fi
    echo "$r" | cuerpo_de
    return 0
  fi
  # Ya existe (o falló): intentar login
  r=$(req POST /api/v1/auth/login "" "{\"correo\":\"$correo\",\"contrasena\":\"$clave\"}")
  [ "$(echo "$r" | status_de)" = "200" ] || fallo "No se pudo registrar ni iniciar sesión con $correo" "$r"
  echo "  (ya existía: $correo)" >&2
  echo "$r" | cuerpo_de
}

echo "== Usuarios"
# SD-08  Admin de banco  [SUPUESTO] doc 1000000002, cel 3000000002, tipo O+
R_ADMIN=$(registrar_usuario "Admin" "Banco" "admin.banco@test.com" 'Banco123*' $ROL_ADMIN_BANCO 1000000002 3000000002 "O+")
ADMIN_ID=$(echo "$R_ADMIN" | primer_id)
[ -n "$ADMIN_ID" ] || fallo "Sin id de ADMIN_BANCO" "$R_ADMIN"
# SD-13  Superadmin      [SUPUESTO] doc 1000000003, cel 3000000003, tipo O+
R_SUPER=$(registrar_usuario "Super" "Admin" "super.admin@test.com" 'Admin123*' $ROL_SUPER_ADMIN 1000000003 3000000003 "O+")
SUPER_ID=$(echo "$R_SUPER" | primer_id)
[ -n "$SUPER_ID" ] || fallo "Sin id de SUPER_ADMIN" "$R_SUPER"
echo "ADMIN_BANCO id=$ADMIN_ID  SUPER_ADMIN id=$SUPER_ID"

# ── 2. Token del superadmin ──────────────────────────────────────────────────
TOKEN=$(echo "$R_SUPER" | token_de)
[ -n "$TOKEN" ] || fallo "Sin token de super admin" "$R_SUPER"
ROL_OBTENIDO=$(echo "$R_SUPER" | grep -o '"rol":"[^"]*"' | head -1 | cut -d'"' -f4)
[ "$ROL_OBTENIDO" = "SUPER_ADMIN" ] || fallo "El rol del superadmin es '$ROL_OBTENIDO'; ¿data-h2.sql define SUPER_ADMIN con id 3?" "$R_SUPER"

# ── 3. Bancos ────────────────────────────────────────────────────────────────
# crear_banco NOMBRE NIT DIRECCION CIUDAD DEPARTAMENTO LAT LON TELEFONO
# Imprime el id; si el NIT ya existe devuelve el existente y deja BANCO_NUEVO=0.
# Se llama sin subshell para conservar BANCO_NUEVO: el id queda en $BANCO_ID.
# El adminId es el ADMIN_BANCO de SD-08 (el DTO exige un administrador).
# [SUPUESTO] NIT, dirección, teléfono, correo y horario 07:00-18:00 de todos los bancos.
# Del set de datos solo vienen ciudad y coordenadas.
BANCO_NUEVO=0; BANCO_ID=""
crear_banco() {
  local nombre="$1" nit="$2" dir="$3" ciudad="$4" dep="$5" lat="$6" lon="$7" tel="$8"
  local lista existente
  lista=$(req GET /api/bancos "$TOKEN" | cuerpo_de)
  # el JSON del banco anida "admin": se busca id, nombre y nit consecutivos
  existente=$(echo "$lista" | grep -o "\"id\":[0-9]*,\"nombre\":\"[^\"]*\",\"nit\":\"$nit\"" | head -1 | primer_id)
  if [ -n "$existente" ]; then
    echo "  (ya existía banco NIT $nit)" >&2; BANCO_ID="$existente"; BANCO_NUEVO=0; return
  fi
  local cuerpo r
  cuerpo=$(cat <<JSON
{"nombre":"$nombre","nit":"$nit","direccion":"$dir","ciudad":"$ciudad",
 "departamento":"$dep","telefono":"$tel","correo":"contacto.${nit%%-*}@test.com",
 "latitud":$lat,"longitud":$lon,"horarioApertura":"07:00:00","horarioCierre":"18:00:00",
 "activo":true,"adminId":$ADMIN_ID}
JSON
)
  r=$(req POST /api/bancos "$TOKEN" "$cuerpo")
  case "$(echo "$r" | status_de)" in 200|201) ;; *) fallo "No se pudo crear el banco $nombre" "$r";; esac
  BANCO_ID=$(echo "$r" | cuerpo_de | primer_id); BANCO_NUEVO=1
}

echo "== Bancos"
# SD-08/SD-15: banco de Medellín (el del admin y el que SD-15 llama "existente").
# [SUPUESTO] coordenadas del banco: mismas del donante de SD-06 (6.2442, -75.5812).
crear_banco "Banco de Sangre Medell\u00edn" "900000001-1" "Calle 50 # 45-10" "Medell\u00edn" "Antioquia" 6.2442 -75.5812 "6040000001"
MEDELLIN_ID=$BANCO_ID; MEDELLIN_NUEVO=$BANCO_NUEVO
# SD-06: banco dentro del radio de 50 km (Envigado)
crear_banco "Banco de Sangre Envigado" "900000004-1" "Carrera 43A # 35-20" "Envigado" "Antioquia" 6.1759 -75.5917 "6040000004"
# SD-06/SD-15: banco fuera del radio (Bogotá)
crear_banco "Banco de Sangre Bogot\u00e1" "900000002-1" "Carrera 7 # 32-16" "Bogot\u00e1" "Cundinamarca" 4.7110 -74.0721 "6010000002"
echo "Medellín id=$MEDELLIN_ID (nuevo=$MEDELLIN_NUEVO)"

if [ "$MEDELLIN_NUEVO" != "1" ]; then
  echo "Banco de Medellín ya existía: se omiten inventario y solicitudes para no duplicar."
  exit 0
fi

# ── 4. Inventario (SD-09), banco de Medellín ─────────────────────────────────
echo "== Inventario"
inv() {
  local r; r=$(req POST /api/inventario "$TOKEN" \
    "{\"bancoId\":$MEDELLIN_ID,\"tipoSangre\":\"$1\",\"unidadesDisponibles\":$2,\"unidadesMinimas\":$3}")
  case "$(echo "$r" | status_de)" in 200|201) echo "  $1: $2 disponibles, mínimo $3";; *) fallo "Inventario $1" "$r";; esac
}
inv "O+" 3 5    # bajo stock
inv "A+" 10 5   # stock suficiente

# ── 5. Solicitudes (SD-05), banco de Medellín ────────────────────────────────
# [SUPUESTO] 5 unidades necesarias, motivo y fecha límite (+7 días) de cada solicitud.
echo "== Solicitudes"
FECHA_LIMITE=$(date -d "+7 days" +%F 2>/dev/null || date -v+7d +%F)
sol() {
  local r; r=$(req POST /api/solicitudes "$TOKEN" \
    "{\"bancoId\":$MEDELLIN_ID,\"tipoSangre\":\"$1\",\"unidadesNecesarias\":5,\"urgencia\":\"$2\",\"motivo\":\"Datos de prueba SD-05\",\"fechaLimite\":\"$FECHA_LIMITE\"}")
  case "$(echo "$r" | status_de)" in 200|201) ;; *) fallo "Solicitud $1" "$r";; esac
  echo "$r" | cuerpo_de | primer_id
}
sol "O-" ALTA  >/dev/null; echo "  O- ALTA activa"
sol "A+" MEDIA >/dev/null; echo "  A+ MEDIA activa"
sol "B+" BAJA  >/dev/null; echo "  B+ BAJA activa"
sol "AB+" ALTA >/dev/null; echo "  AB+ ALTA activa"
CANC_ID=$(sol "O+" MEDIA)
r=$(req PATCH "/api/solicitudes/$CANC_ID/estado?estado=CANCELADA" "$TOKEN")
[ "$(echo "$r" | status_de)" = "200" ] || fallo "No se pudo cancelar la solicitud $CANC_ID" "$r"
echo "  O+ CANCELADA (id $CANC_ID)"

# ── 6. Verificación ──────────────────────────────────────────────────────────
echo "== Verificación"
ACT=$(req GET /api/solicitudes/activas | cuerpo_de | grep -o '"estado":"ACTIVA"' | wc -l)
echo "Solicitudes activas: $ACT (esperado 4)"
BAJO=$(req GET "/api/inventario/banco/$MEDELLIN_ID/bajo-stock" "$TOKEN" | cuerpo_de | grep -o '"tipoSangre":"[^"]*"' | tr '\n' ' ')
echo "Bajo stock Medellín: $BAJO (esperado solo O+)"
[ "$ACT" = "4" ] || { echo "ATENCIÓN: el conteo de activas no coincide" >&2; exit 1; }
echo "Carga completa."

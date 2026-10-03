#!/usr/bin/env bash
# Funciones comunes de los scripts de ejecucion por API (se usa con "source").
# paso/estado_es/rechazado/contiene/no_contiene registran petición, respuesta y veredicto.

set -u
API="${API:-http://localhost:8081}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
EVID="$RAIZ/evidencias"
LOG="${LOG:-$EVID/verificaciones.log}"

CASO=""; N=0; LAST_BODY=""; LAST_STATUS=""

redactar() {
  sed -E 's/"token":"[^"]*"/"token":"<JWT>"/g; s/(Bearer )[A-Za-z0-9._-]+/\1<JWT>/g; s/"(contrasena|password)":"[^"]*"/"\1":"<omitida>"/g'
}

caso() { CASO="$1"; N=0; mkdir -p "$EVID/$CASO"; rm -f "$EVID/$CASO"/*.txt; echo; echo "=== $CASO ==="; }

# paso "descripcion" METODO RUTA [TOKEN] [CUERPO]  -> LAST_BODY / LAST_STATUS
paso() {
  local desc="$1" metodo="$2" ruta="$3" token="${4:-}" cuerpo="${5:-}"
  N=$((N+1)); local nn; nn=$(printf '%02d' "$N")
  local slug; slug=$(echo "$desc" | tr 'A-Z ' 'a-z-' | tr -cd 'a-z0-9-' | cut -c1-40)
  local f="$EVID/$CASO/$nn-$slug.txt"
  local args=(-s -X "$metodo" -w '\n%{http_code}' -H 'Content-Type: application/json')
  [ -n "$token" ]  && args+=(-H "Authorization: Bearer $token")
  [ -n "$cuerpo" ] && args+=(-d "$cuerpo")
  local r; r=$(curl "${args[@]}" "$API$ruta")
  LAST_STATUS=$(echo "$r" | tail -n1); LAST_BODY=$(echo "$r" | sed '$d')
  {
    echo "# $CASO paso $nn: $desc"
    echo "# Petición"
    echo "$metodo $API$ruta"
    [ -n "$token" ] && echo "Authorization: Bearer <JWT>"
    [ -n "$cuerpo" ] && { echo "Content-Type: application/json"; echo; echo "$cuerpo" | redactar; }
    echo; echo "# Respuesta (HTTP $LAST_STATUS)"
    echo "$LAST_BODY" | redactar
  } > "$f"
  echo "  [$nn] $desc -> HTTP $LAST_STATUS"
}

registrar() { # texto resultado detalle
  echo "$CASO|$2|$1|$3" >> "$LOG"
  echo "    $2: $1${3:+ ($3)}"
}
estado_es() { # texto codigo...
  local t="$1"; shift; local c
  for c in "$@"; do [ "$LAST_STATUS" = "$c" ] && { registrar "$t" PASA "HTTP $LAST_STATUS"; return; }; done
  registrar "$t" FALLA "HTTP $LAST_STATUS; esperado $*"
}
rechazado() { # texto  (cualquier 4xx)
  case "$LAST_STATUS" in 4*) registrar "$1" PASA "HTTP $LAST_STATUS: $(echo "$LAST_BODY" | grep -o '"mensaje":"[^"]*"' | head -1)";;
    *) registrar "$1" FALLA "HTTP $LAST_STATUS; se esperaba un rechazo 4xx";; esac
}
contiene() { # texto patron
  echo "$LAST_BODY" | grep -qi -- "$2" && registrar "$1" PASA "" || registrar "$1" FALLA "no aparece $2"
}
no_contiene() {
  echo "$LAST_BODY" | grep -q -- "$2" && registrar "$1" FALLA "aparece $2" || registrar "$1" PASA ""
}
dato() { echo "$LAST_BODY" | grep -o "\"$1\":\"\?[^,\"}]*" | head -1 | sed -E "s/\"$1\":\"?//"; }
token() { echo "$LAST_BODY" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4; }
uid()   { echo "$LAST_BODY" | grep -o '"usuario":{"id":[0-9]*' | grep -o '[0-9]*$'; }

U="\\u"   # prefijo de escape unicode para JSON
MEDELLIN_JSON="Medell${U}00edn"

registro_json() { # doc nombre apellido correo cel clave sangre peso [lat lon]
  local lat="${9-6.2442}" lon="${10--75.5812}" ubic=""
  [ -n "$lat" ] && ubic="\"latitud\":$lat,\"longitud\":$lon,"
  echo "{\"tipoDocumento\":\"CC\",\"numeroDocumento\":\"$1\",\"nombre\":\"$2\",\"apellido\":\"$3\",\"correo\":\"$4\",\"celular\":\"$5\",\"contrasena\":\"$6\",\"tipoSangre\":\"$7\",\"fechaNacimiento\":\"1995-05-10\",\"genero\":\"FEMENINO\",\"pesoKg\":$8,$ubic\"ciudad\":\"$MEDELLIN_JSON\",\"departamento\":\"Antioquia\"}"
}
login_json() { echo "{\"correo\":\"$1\",\"contrasena\":\"$2\"}"; }


# Veredictos que no son PASA/FALLA
observado() { registrar "$1" OBSERVADO "$2"; }   # comportamiento no especificado por el PRD (consulta funcional)
bloqueado() { registrar "$1" BLOQUEADO "$2"; }   # no se puede ejecutar en este entorno
# Objeto JSON (sin anidar) del array en LAST_BODY que contiene un texto
objeto_con() { echo "$LAST_BODY" | grep -o "{[^{}]*$1[^{}]*}" | head -1; }
cuenta() { echo "$LAST_BODY" | grep -o "$1" | wc -l | tr -d ' '; }

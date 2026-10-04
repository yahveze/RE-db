#!/usr/bin/env bash
# =============================================================================
# Pruebas de operacion (Fase 6) que no caben en un archivo SQL: necesitan abrir
# conexiones con y sin clave, leer el log del servidor (docker compose logs) o
# ejecutar los scripts de operacion.
#
#   OPE-20..23  pg_hba.conf: el socket local exige clave (T-43)
#   OPE-24..26  que llega y que no llega al log del servidor (T-13)
#   OPE-27..28  entorno del contenedor: memoria compartida (T-51), rotacion del log
#   OPE-29..31  purga de la auditoria con el script real (archiva, elimina, deja rastro)
#   OPE-32      las claves de .env no estan en el log del contenedor
#
# Como concurrencia.sh, confirma transacciones: la purga elimina tres registros
# de prueba creados aqui y deja un registro propio en la auditoria.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/_lib.sh"

dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
fallos=0
marca="$(date -u +%s)$RANDOM"

echo "### Operacion"

# afirmar <obtenido> <esperado> <descripcion>
afirmar() {
  if [ "$1" = "$2" ]; then
    echo "PASS | $3"
  else
    echo "FAIL | $3 -> esperado '$2', obtenido '$1'"
    fallos=$((fallos + 1))
  fi
}
# Devuelve "si" o "no" segun la condicion de test que recibe.
si_no() { if "$@"; then echo si; else echo no; fi; }

# ----------------------------------------------------------------------------
# Autenticacion por el socket local del contenedor
# ----------------------------------------------------------------------------
# psql -w nunca pide la clave: sin PGPASSWORD la conexion debe fallar.
sin_clave() {
  docker compose exec -T db sh -c 'psql -X -At -w -U "$1" -d "$POSTGRES_DB" -c "SELECT session_user" 2>&1' sh "$1" | tr -d '\r' || true
}
r="$(sin_clave app_backend_user)"
afirmar "$(si_no grep -q 'no password supplied' <<<"$r")" si "OPE-20 app_backend_user sin clave por el socket local: conexion rechazada (T-43)"
r="$(sin_clave "$POSTGRES_USER")"
afirmar "$(si_no grep -q 'no password supplied' <<<"$r")" si "OPE-21 superusuario sin clave por el socket local: conexion rechazada"
r="$(docker compose exec -T -e PGPASSWORD=clave-incorrecta-de-prueba db sh -c 'psql -X -At -w -U app_backend_user -d "$POSTGRES_DB" -c "SELECT session_user" 2>&1' | tr -d '\r' || true)"
afirmar "$(si_no grep -q 'password authentication failed' <<<"$r")" si "OPE-22 app_backend_user con una clave incorrecta: conexion rechazada"
r="$(psql_backend -c "SELECT session_user" 2>&1 | tr -d '\r' || true)"
afirmar "$r" app_backend_user "OPE-23 app_backend_user con la clave de .env: conexion aceptada"

# ----------------------------------------------------------------------------
# Log del servidor. Cada caso lleva un canario unico; despues se cuenta en que
# lineas del log aparece.
# ----------------------------------------------------------------------------
# (a) Sentencia que falla con una clave literal: debe quedar el ERROR, no la sentencia.
psql_super -c "ALTER ROLE rol_inexistente_$marca PASSWORD 'canario-a-$marca'" >/dev/null 2>&1 || true
# (b) Sentencia preparada con parametro, con el log de duracion activado solo en
#     esta sesion: debe quedar la sentencia, no el valor del parametro.
# (c) Lo mismo con el valor escrito como literal: SI queda en el log. Es el
#     riesgo por el que el compose no activa log_min_duration_statement.
psql_super >/dev/null 2>&1 <<SQL || true
SET log_min_duration_statement = 0;
SELECT /* marca-b-$marca */ \$1::text AS valor \bind 'canario-b-$marca' \g
SELECT /* marca-c-$marca */ 'canario-c-$marca'::text AS valor;
RESET log_min_duration_statement;
SELECT pg_sleep(0.5);
SQL
docker compose logs --no-log-prefix --since 10m db > "$dir/log" 2>&1 || true
lineas() { grep -cF -- "$1" "$dir/log" || true; }

afirmar "$(si_no [ "$(lineas "rol_inexistente_$marca")" -ge 1 ])/$(lineas "canario-a-$marca")" "si/0" \
  "OPE-24 una sentencia que falla deja su ERROR en el log pero no su texto: la clave literal no aparece"
afirmar "$(si_no [ "$(lineas "marca-b-$marca")" -ge 1 ])/$(lineas "canario-b-$marca")" "si/0" \
  "OPE-25 con el log de duracion activo, una sentencia con parametros se registra sin el valor del parametro"
afirmar "$(si_no [ "$(lineas "canario-c-$marca")" -ge 1 ])" si \
  "OPE-26 (riesgo conocido) con el log de duracion activo, un valor escrito como literal SI queda en el log"

# ----------------------------------------------------------------------------
# Entorno del contenedor
# ----------------------------------------------------------------------------
shm="$(docker compose exec -T db df -m /dev/shm | awk 'NR == 2 { print $2 }' | tr -d '\r')"
afirmar "$(si_no [ "${shm:-0}" -ge 256 ])" si "OPE-27 el contenedor tiene al menos 256 MB de memoria compartida en /dev/shm (T-51)"
rotacion="$(docker inspect -f '{{ index .HostConfig.LogConfig.Config "max-size" }}/{{ index .HostConfig.LogConfig.Config "max-file" }}' repuestos_exactos_db | tr -d '\r')"
afirmar "$rotacion" "10m/5" "OPE-28 el log del contenedor se rota (5 archivos de 10 MB)"

# ----------------------------------------------------------------------------
# Purga de la auditoria con el script real
# ----------------------------------------------------------------------------
psql_super >/dev/null <<SQL
INSERT INTO auditoria_operacion (ocurrido_en, rol, operacion, tabla, resultado, request_id)
SELECT now() - interval '40 years' - g * interval '1 day', 'prueba', 'INSERT', 'prueba_purga', 'exito', 'ope-purga-$marca'
FROM   generate_series(1, 3) g;
SQL
antes="$(psql_super -At -c "SELECT count(*) FROM auditoria_operacion")"
if salida="$(RESPALDO_DIR="$dir" CONFIRMAR=1 bash db/scripts/purgar_auditoria.sh 30 2>&1)"; then codigo=0; else codigo=$?; fi
archivo="$(ls -1 "$dir"/auditoria_anterior_a_*.csv 2>/dev/null | head -1)"

archivadas="$( [ -n "$archivo" ] && grep -cF "ope-purga-$marca" "$archivo" || true)"
suma_ok="$( [ -n "$archivo" ] && (cd "$dir" && sha256sum --check --quiet "$(basename "$archivo").sha256" >/dev/null 2>&1 && echo si) || echo no)"
afirmar "$codigo/${archivadas:-0}/$suma_ok" "0/3/si" \
  "OPE-29 purga: los registros anteriores al corte se archivan en CSV con su suma sha256 antes de eliminarse"

estado="$(psql_super -At -F / -c "SELECT (SELECT count(*) FROM auditoria_operacion WHERE request_id = 'ope-purga-$marca'), (SELECT count(*) FROM auditoria_operacion) - $antes")"
afirmar "$estado" "0/-2" \
  "OPE-30 purga: se eliminan exactamente los 3 registros antiguos (el total baja en 3 y sube en 1 por el registro de la purga)"

suma_archivo="$( [ -n "$archivo" ] && cut -d' ' -f1 "$archivo.sha256" || true)"
rastro="$(psql_super -At -F / -c "SELECT datos_anteriores->>'registros_eliminados', datos_anteriores->>'sha256' = '$suma_archivo', resultado, tabla FROM auditoria_operacion WHERE request_id = 'purga-auditoria' ORDER BY id DESC LIMIT 1")"
afirmar "$rastro" "3/t/exito/auditoria_operacion" \
  "OPE-31 purga: queda un registro en la auditoria con el corte, la cantidad eliminada y la suma del archivo"
if [ "$codigo" -ne 0 ]; then echo "$salida" | sed 's/^/       /'; fi

# ----------------------------------------------------------------------------
# Secretos en el log del contenedor (solo conteos: el valor nunca se imprime)
# ----------------------------------------------------------------------------
docker compose logs --no-log-prefix db > "$dir/log_completo" 2>&1 || true
total=0
for variable in POSTGRES_PASSWORD APP_BACKEND_PASSWORD CLAVE_DEMO; do
  n="$(grep -cF -- "${!variable}" "$dir/log_completo" || true)"
  total=$((total + n))
done
afirmar "$total" 0 "OPE-32 el log del contenedor no contiene ninguna de las tres claves de .env"

[ "$fallos" -eq 0 ]

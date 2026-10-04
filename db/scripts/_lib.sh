#!/usr/bin/env bash
# Funciones comunes de los scripts. Se incluye con: source "$(dirname "$0")/../scripts/_lib.sh"
set -euo pipefail

# Git Bash en Windows reescribe rutas tipo /db/... al pasarlas a docker; se desactiva.
export MSYS_NO_PATHCONV=1

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$RAIZ"

if [ ! -f .env ]; then
  echo "ERROR: falta .env (copiar .env.example y completar las claves)." >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a

# Ejecuta un programa cliente (psql, pg_dump, pg_restore...) dentro del
# contenedor, autenticado como superusuario. pg_hba.conf exige SCRAM tambien en
# el socket local (T-43): la clave se toma de la variable POSTGRES_PASSWORD que
# el contenedor ya tiene, nunca de la linea de comandos.
en_contenedor() {
  docker compose exec -T -e APP_BACKEND_PASSWORD -e CLAVE_DEMO db sh -c '
    export PGPASSWORD="$POSTGRES_PASSWORD" PGUSER="$POSTGRES_USER"
    exec "$@"' sh "$@"
}

# psql 16 del contenedor, como superusuario, deteniendose en el primer error.
# Los secretos entran al contenedor como variables de entorno (-e NOMBRE, sin
# valor en la linea de comandos del host) y llegan a psql con -v, para usarlos
# en SQL como :'clave_backend' y :'clave_demo'. Dentro del contenedor, /db es
# la carpeta db/ del repositorio.
psql_super() {
  docker compose exec -T -e APP_BACKEND_PASSWORD -e CLAVE_DEMO db sh -c '
    PGPASSWORD="$POSTGRES_PASSWORD" exec psql -X -q -v ON_ERROR_STOP=1 \
      -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      -v clave_backend="$APP_BACKEND_PASSWORD" \
      -v clave_demo="$CLAVE_DEMO" \
      "$@"' sh "$@"
}

# psql como app_backend_user (el rol de conexion del backend), con su clave.
# Sin ON_ERROR_STOP: lo usan guiones que esperan errores.
psql_backend() {
  docker compose exec -T -e APP_BACKEND_PASSWORD db sh -c '
    PGPASSWORD="$APP_BACKEND_PASSWORD" exec psql -X -q -At -v ON_ERROR_STOP=0 \
      -U app_backend_user -d "$POSTGRES_DB" "$@"' sh "$@"
}

# pg_stat_statements guarda el texto de las sentencias de utilidad sin
# normalizar: CREATE ROLE ... PASSWORD '...' y cualquier EXPLAIN con una clave
# literal quedarian legibles para un superusuario. Los scripts que envian
# claves como literal (migraciones, semillas, medicion) lo vacian al terminar.
vaciar_estadisticas_sentencias() {
  psql_super -At -c "SELECT pg_stat_statements_reset()" >/dev/null
}

esperar_db() {
  docker compose up -d --wait
}

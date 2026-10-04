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

# psql 16 del contenedor, como superusuario, deteniendose en el primer error.
# Los secretos entran al contenedor como variables de entorno (-e NOMBRE, sin
# valor en la linea de comandos del host) y llegan a psql con -v, para usarlos
# en SQL como :'clave_backend' y :'clave_demo'. Dentro del contenedor, /db es
# la carpeta db/ del repositorio.
psql_super() {
  docker compose exec -T -e APP_BACKEND_PASSWORD -e CLAVE_DEMO db sh -c '
    exec psql -X -q -v ON_ERROR_STOP=1 \
      -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      -v clave_backend="$APP_BACKEND_PASSWORD" \
      -v clave_demo="$CLAVE_DEMO" \
      "$@"' sh "$@"
}

esperar_db() {
  docker compose up -d --wait
}

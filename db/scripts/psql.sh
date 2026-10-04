#!/usr/bin/env bash
# Abre psql 16 dentro del contenedor como superusuario.
#   bash db/scripts/psql.sh                      -> sesion interactiva
#   bash db/scripts/psql.sh -c "SELECT 1"        -> un comando
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

if [ $# -eq 0 ] && [ -t 0 ]; then
  exec docker compose exec db sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
fi
psql_super "$@"

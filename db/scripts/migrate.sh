#!/usr/bin/env bash
# Aplica db/migrations/V*.sql en orden y se detiene en el primer error.
#   V000         -> superusuario (roles y extensiones).
#   V001 y mas   -> superusuario con SET ROLE app_owner previo, para que los
#                   objetos queden con app_owner como propietario.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

shopt -s nullglob
archivos=(db/migrations/V*.sql)
if [ ${#archivos[@]} -eq 0 ]; then
  echo "migrate: no hay migraciones en db/migrations/"
  exit 0
fi

for archivo in "${archivos[@]}"; do
  nombre="$(basename "$archivo")"
  echo "==> $nombre"
  if [[ "$nombre" == V000__* ]]; then
    psql_super -f "/db/migrations/$nombre"
  else
    psql_super -c "SET ROLE app_owner" -f "/db/migrations/$nombre"
  fi
done
echo "migrate: ${#archivos[@]} migraciones aplicadas"

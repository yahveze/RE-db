#!/usr/bin/env bash
# Carga db/seeds/*.sql en orden, como superusuario (FORCE RLS afecta incluso
# al propietario, por eso las semillas no se cargan como app_owner).
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

shopt -s nullglob
archivos=(db/seeds/*.sql)
if [ ${#archivos[@]} -eq 0 ]; then
  echo "seed: no hay semillas en db/seeds/"
  exit 0
fi

for archivo in "${archivos[@]}"; do
  nombre="$(basename "$archivo")"
  echo "==> $nombre"
  psql_super -f "/db/seeds/$nombre"
done
echo "seed: ${#archivos[@]} archivos cargados"

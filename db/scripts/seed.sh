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

# Las semillas no son re-ejecutables (claves naturales unicas): sobre una base
# ya cargada se avisa en lugar de fallar a mitad de camino.
if [ "$(psql_super -At -c "SELECT count(*) FROM taller")" != "0" ]; then
  echo "seed: la base ya tiene datos; para recargar: bash db/scripts/reset.sh && bash db/scripts/migrate.sh" >&2
  exit 1
fi

for archivo in "${archivos[@]}"; do
  nombre="$(basename "$archivo")"
  echo "==> $nombre"
  psql_super -f "/db/seeds/$nombre"
done
# Las semillas envian la clave de demostracion como literal.
vaciar_estadisticas_sentencias
echo "seed: ${#archivos[@]} archivos cargados"

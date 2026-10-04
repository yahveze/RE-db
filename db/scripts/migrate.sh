#!/usr/bin/env bash
# Aplica db/migrations/V*.sql en orden y se detiene en el primer error.
# Cada archivo corre en UNA transaccion (--single-transaction): si falla, no
# queda aplicado a medias.
#   V000         -> superusuario (roles y extensiones).
#   V001 y mas   -> superusuario con SET ROLE app_owner previo, para que los
#                   objetos queden con app_owner como propietario.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

#   bash db/scripts/migrate.sh          -> todas las migraciones
#   bash db/scripts/migrate.sh V003     -> solo las que empiezan por ese prefijo
shopt -s nullglob
archivos=(db/migrations/"${1:-V}"*.sql)
if [ ${#archivos[@]} -eq 0 ]; then
  echo "migrate: no hay migraciones en db/migrations/"
  exit 0
fi

for archivo in "${archivos[@]}"; do
  nombre="$(basename "$archivo")"
  echo "==> $nombre"
  if [[ "$nombre" == V000__* ]]; then
    psql_super --single-transaction -f "/db/migrations/$nombre"
  else
    psql_super --single-transaction -c "SET ROLE app_owner" -f "/db/migrations/$nombre"
  fi
done
# V000 envia la clave del backend como literal (CREATE ROLE ... PASSWORD).
vaciar_estadisticas_sentencias
echo "migrate: ${#archivos[@]} migraciones aplicadas"

#!/usr/bin/env bash
# =============================================================================
# Respaldo logico de la base (make backup).
#
# Genera en backups/ (carpeta ignorada por Git) tres archivos con la misma marca
# de tiempo UTC:
#   <base>_<marca>.dump           pg_dump en formato custom (-Fc): esquema, datos,
#                                 privilegios, politicas RLS y ACL de la base.
#   <base>_<marca>.globales.sql   roles y membresias del cluster (pg_dumpall
#                                 --globals-only). Los roles NO viajan en el dump
#                                 de una base. Se generan SIN claves
#                                 (--no-role-passwords): al restaurar, la clave
#                                 de app_backend_user se vuelve a fijar desde .env.
#   <base>_<marca>.sha256         suma de verificacion de los dos anteriores.
#
# pg_dump trabaja sobre una instantanea consistente y no bloquea a quienes leen
# o escriben. El respaldo contiene datos personales y hashes de contrasenas:
# debe guardarse cifrado y fuera del equipo (docs/operacion.md seccion 2).
#
# Variables opcionales:
#   RESPALDO_DIR          carpeta de destino (por defecto backups/)
#   RESPALDOS_CONSERVAR   cuantos respaldos se conservan (por defecto 7);
#                         los mas antiguos de esta base se eliminan.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

dir="${RESPALDO_DIR:-$RAIZ/backups}"
conservar="${RESPALDOS_CONSERVAR:-7}"
mkdir -p "$dir"

marca="$(date -u +%Y%m%dT%H%M%SZ)"
base="$dir/${POSTGRES_DB}_${marca}"
inicio=$SECONDS

limpiar_incompleto() { rm -f "$base.dump" "$base.globales.sql" "$base.sha256"; }
trap 'echo "respaldo: FALLO - se elimina el respaldo incompleto" >&2; limpiar_incompleto' ERR

en_contenedor pg_dump -Fc -d "$POSTGRES_DB" > "$base.dump"
en_contenedor pg_dumpall --globals-only --no-role-passwords > "$base.globales.sql"

# Un respaldo que no se puede leer no es un respaldo: se recorre su indice.
objetos="$(en_contenedor pg_restore --list < "$base.dump" | grep -c '^[0-9]' || true)"
if [ "$objetos" -eq 0 ]; then
  echo "respaldo: FALLO - el archivo generado no tiene objetos" >&2
  limpiar_incompleto
  exit 1
fi
if grep -q 'SCRAM-SHA-256' "$base.globales.sql"; then
  echo "respaldo: FALLO - el archivo de roles contiene verificadores de clave" >&2
  limpiar_incompleto
  exit 1
fi

( cd "$dir" && sha256sum "$(basename "$base.dump")" "$(basename "$base.globales.sql")" > "$(basename "$base.sha256")" )
chmod 600 "$base.dump" "$base.globales.sql" "$base.sha256" 2>/dev/null || true
trap - ERR

# Rotacion: se conservan los N mas recientes de esta base (el nombre ordena por fecha).
if [ "$conservar" -gt 0 ]; then
  ls -1 "$dir"/"${POSTGRES_DB}"_*.dump 2>/dev/null | sort -r | tail -n +"$((conservar + 1))" | while read -r viejo; do
    rm -f "$viejo" "${viejo%.dump}.globales.sql" "${viejo%.dump}.sha256"
    echo "respaldo: eliminado por rotacion $(basename "$viejo")"
  done
fi

echo "respaldo: $(basename "$base.dump") ($(wc -c < "$base.dump") bytes, $objetos objetos, $((SECONDS - inicio)) s)"
echo "respaldo: $(basename "$base.globales.sql") ($(grep -c '^CREATE ROLE' "$base.globales.sql") roles, sin claves)"
echo "RESPALDO=$base.dump"

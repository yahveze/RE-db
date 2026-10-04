#!/usr/bin/env bash
# =============================================================================
# Verificacion NO destructiva de un respaldo (make verify-backup).
#
#   bash db/scripts/verificar_respaldo.sh [backups/<archivo>.dump]
#
# Sin argumento usa el respaldo mas reciente de backups/. Restaura el archivo
# en una base temporal <base>_verif, compara su huella de datos (filas y md5
# por tabla, db/ops/huella.sql) con la de la base principal y elimina la base
# temporal. No toca la base principal.
#
# Si la base principal cambio despues del respaldo, las tablas modificadas
# aparecen como diferencia: eso es lo esperado, y se listan. El codigo de
# salida es distinto de cero solo si la restauracion falla o si se exige
# igualdad con EXIGIR_IGUAL=1 y hay diferencias.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

dir="${RESPALDO_DIR:-$RAIZ/backups}"
dump="${1:-$(ls -1 "$dir"/"${POSTGRES_DB}"_*.dump 2>/dev/null | sort -r | head -1)}"
if [ -z "$dump" ] || [ ! -f "$dump" ]; then
  echo "verificar: no hay respaldos en $dir (ejecutar antes: bash db/scripts/respaldar.sh)" >&2
  exit 1
fi
suma="${dump%.dump}.sha256"
if [ -f "$suma" ]; then
  ( cd "$(dirname "$dump")" && sha256sum --check --quiet "$(basename "$suma")" )
  echo "verificar: suma sha256 correcta"
fi

base_verif="${POSTGRES_DB}_verif"
eliminar() { psql_super -d postgres -c "DROP DATABASE IF EXISTS \"$base_verif\" WITH (FORCE)" >/dev/null 2>&1 || true; }
trap eliminar EXIT

eliminar
psql_super -d postgres -c "CREATE DATABASE \"$base_verif\" TEMPLATE template0"
inicio=$SECONDS
en_contenedor pg_restore --exit-on-error -d "$base_verif" < "$dump"
echo "verificar: $(basename "$dump") restaurado en $base_verif ($((SECONDS - inicio)) s)"

huella_respaldo="$(psql_super -d "$base_verif" -At -f /db/ops/huella.sql)"
huella_actual="$(psql_super -At -f /db/ops/huella.sql)"

tablas="$(grep -vc '^secuencia ' <<<"$huella_respaldo" || true)"
filas="$(grep -v '^secuencia ' <<<"$huella_respaldo" | awk -F'|' '{ n += $2 } END { print n + 0 }')"
echo "verificar: el respaldo contiene $tablas tablas y $filas filas"

if [ "$huella_respaldo" = "$huella_actual" ]; then
  echo "verificar: la huella del respaldo es IDENTICA a la de la base principal"
else
  echo "verificar: el respaldo DIFIERE de la base principal (cambio despues del respaldo) en:"
  # diff termina con 1 cuando hay diferencias: no es un error del script.
  { diff <(echo "$huella_respaldo") <(echo "$huella_actual") || true; } | grep '^[<>]' | cut -d'|' -f1 | sed 's/^[<>] //' | sort -u | sed 's/^/  - /'
  if [ "${EXIGIR_IGUAL:-0}" = "1" ]; then
    exit 1
  fi
fi

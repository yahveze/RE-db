#!/usr/bin/env bash
# =============================================================================
# Medicion de rendimiento (make perf).
#
# No toca la base principal: crea <base>_perf como copia de ella (esquema +
# semillas), le carga volumen sintetico, mide y la elimina. Requiere la base
# principal migrada y con semillas, y que ninguna otra sesion este conectada a
# ella mientras se copia.
#
#   1. CREATE DATABASE <base>_perf TEMPLATE <base>
#   2. db/perf/volumen.sql            carga masiva (triggers desactivados)
#   3. VACUUM (ANALYZE)               estadisticas y mapa de visibilidad
#   4. db/perf/medir.sql              EXPLAIN (ANALYZE, BUFFERS) de las sentencias
#                                     de db/queries con el rol del backend
#   5. db/perf/experimentos_indices.sql   cada indice dudoso, con y sin el
#   6. uso de indices y tamanios
#
# Evidencia: docs/evidencia/fase5_medidas.txt, fase5_indices.txt, fase5_resumen.txt
#
# Variables de entorno opcionales:
#   PERF_SESIONES_GRANDE (150000)  PERF_SESIONES_CHICO (8000)
#   PERF_TALLERES (20)             PERF_AUDITORIA (2000000)
#   PERF_CONSERVAR=1               no elimina la base de rendimiento al terminar
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/_lib.sh"

base_perf="${POSTGRES_DB}_perf"

psql_perf() {
  docker compose exec -T -e CLAVE_DEMO db sh -c '
    PGPASSWORD="$POSTGRES_PASSWORD" exec psql -X -q -v ON_ERROR_STOP=1 \
      -U "$POSTGRES_USER" -d "${POSTGRES_DB}_perf" \
      -v clave_demo="$CLAVE_DEMO" \
      "$@"' sh "$@"
}

if [ "$(psql_super -At -c "SELECT count(*) FROM taller")" = "0" ]; then
  echo "perf: la base no tiene semillas (ejecutar antes: bash db/scripts/seed.sh)" >&2
  exit 1
fi

eliminar() {
  # medir.sql ejecuta EXPLAIN de q_login con la clave de demostracion literal.
  vaciar_estadisticas_sentencias || true
  if [ "${PERF_CONSERVAR:-0}" = "1" ]; then
    echo "perf: se conserva la base $base_perf (PERF_CONSERVAR=1)"
  else
    psql_super -c "DROP DATABASE IF EXISTS $base_perf WITH (FORCE)" >/dev/null 2>&1 || true
    echo "perf: base $base_perf eliminada"
  fi
}
trap eliminar EXIT

echo "perf: creando $base_perf como copia de $POSTGRES_DB"
psql_super -c "DROP DATABASE IF EXISTS $base_perf WITH (FORCE)" >/dev/null 2>&1
psql_super -c "CREATE DATABASE $base_perf TEMPLATE $POSTGRES_DB"

echo "perf: cargando volumen (puede tardar varios minutos)"
inicio=$SECONDS
psql_perf \
  -v sesiones_grande="${PERF_SESIONES_GRANDE:-150000}" \
  -v sesiones_chico="${PERF_SESIONES_CHICO:-8000}" \
  -v talleres="${PERF_TALLERES:-20}" \
  -v auditoria="${PERF_AUDITORIA:-2000000}" \
  -f /db/perf/volumen.sql > "$RAIZ/docs/evidencia/fase5_volumen.tmp" 2>&1
echo "perf: volumen cargado en $((SECONDS - inicio)) s"

# VACUUM paralelo: posible desde que el contenedor tiene shm_size 256 MB (T-51);
# con los 64 MB por defecto de Docker fallaba y habia que usar PARALLEL 0.
psql_perf -c "VACUUM (ANALYZE, VERBOSE)" > "$RAIZ/docs/evidencia/fase5_vacuum.tmp" 2>&1
echo "perf: VACUUM (ANALYZE) terminado; lanzamientos de procesos paralelos: $(grep -c 'parallel vacuum worker' "$RAIZ/docs/evidencia/fase5_vacuum.tmp" || true)"
{ grep 'parallel vacuum worker' "$RAIZ/docs/evidencia/fase5_vacuum.tmp" || true; } | sort | uniq -c | sed 's/^/perf:   /'
rm -f "$RAIZ/docs/evidencia/fase5_vacuum.tmp"
psql_perf -c "SELECT pg_stat_reset()" >/dev/null

cabecera() {
  echo "# $1 (generado por db/perf/run.sh)"
  echo "# Fecha: $(date -u +%Y-%m-%dT%H:%MZ)"
  echo
}

echo "perf: midiendo"
medidas="docs/evidencia/fase5_medidas.txt"
{ cabecera "Rendimiento: planes de ejecucion con volumen"
  cat "$RAIZ/docs/evidencia/fase5_volumen.tmp"
  echo
  psql_perf -f /db/perf/medir.sql
} > "$medidas" 2>&1
rm -f "$RAIZ/docs/evidencia/fase5_volumen.tmp"

indices="docs/evidencia/fase5_indices.txt"
{ cabecera "Rendimiento: indices con y sin, uso y tamanios"
  echo "## Tablas: tamanio total, de indices y filas"
  psql_perf -c "SELECT c.relname AS tabla, pg_size_pretty(pg_total_relation_size(c.oid)) AS total, pg_size_pretty(pg_indexes_size(c.oid)) AS indices, c.reltuples::bigint AS filas, (SELECT count(*) FROM pg_index x WHERE x.indrelid = c.oid) AS n_indices FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r' ORDER BY pg_total_relation_size(c.oid) DESC"
  psql_perf -c "SELECT pg_size_pretty(pg_database_size(current_database())) AS base_de_rendimiento"
  echo
  psql_perf -f /db/perf/experimentos_indices.sql
  echo
  echo "## Indices de rendimiento (ix_): tamanio y recorridos durante la medicion"
  echo "## (idx_scan incluye los sondeos del planificador: no prueba por si solo que un plan lo use)"
  psql_perf -c "SELECT i.relname AS tabla, i.indexrelname AS indice, pg_size_pretty(pg_relation_size(i.indexrelid)) AS tamanio, i.idx_scan AS recorridos FROM pg_stat_user_indexes i WHERE i.schemaname = 'public' AND i.indexrelname LIKE 'ix\_%' ORDER BY i.relname, i.indexrelname"
  echo
} > "$indices" 2>&1

# Resumen: una linea por medida (tiempo de ejecucion y bloques leidos).
resumen="docs/evidencia/fase5_resumen.txt"
{ cabecera "Rendimiento: resumen de fase5_medidas.txt"
  printf '%-6s %12s %12s  %s\n' "medida" "ejecucion_ms" "bloques" "sentencia"
  awk '
    /^## M/ { id = $2; $1 = ""; $2 = ""; sub(/^ +/, ""); titulo = $0; bloques = ""; next }
    id != "" && bloques == "" && /Buffers: shared/ {
      n = 0
      for (i = 1; i <= NF; i++) if ($i ~ /^(hit|read)=/) { split($i, p, "="); n += p[2] }
      bloques = n
    }
    id != "" && /Execution Time:/ { printf "%-6s %12s %12s  %s\n", id, $3, (bloques == "" ? "-" : bloques), titulo; id = "" }
  ' "$medidas"
} > "$resumen"

errores="$(cat "$medidas" "$indices" | grep -c 'ERROR:' || true)"
echo "perf: $medidas ($(wc -l < "$medidas") lineas), $indices ($(wc -l < "$indices") lineas), $resumen"
if [ "$errores" != "0" ]; then
  echo "perf: FALLO - $errores error(es) en la medicion" >&2
  exit 1
fi
cat "$resumen"

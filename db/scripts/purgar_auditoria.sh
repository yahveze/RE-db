#!/usr/bin/env bash
# =============================================================================
# Retencion de la auditoria: archiva y elimina los registros mas antiguos que
# <anios> anios.
#
#   bash db/scripts/purgar_auditoria.sh <anios>               -> simulacion
#   CONFIRMAR=1 bash db/scripts/purgar_auditoria.sh <anios>   -> archiva y purga
#
# El plazo no tiene valor por defecto: es una decision legal del responsable
# (docs/operacion.md seccion 6). Se rechaza un plazo menor que la mayor
# retencion de datos configurada por un taller (taller_configuracion
# .retencion_anios): la bitacora debe cubrir al menos el tiempo que se
# conservan los datos que describe.
#
# Pasos con CONFIRMAR=1:
#   1. Fija el instante de corte (medianoche UTC de hoy menos <anios> anios).
#   2. Archiva las filas anteriores al corte en
#      backups/auditoria_anterior_a_<fecha>_<marca>.csv (con su .sha256).
#   3. En UNA transaccion: elimina esas filas (db/ops/purgar_auditoria.sql) y
#      deja un registro de la purga en la propia auditoria. Solo confirma si
#      las filas eliminadas son exactamente las archivadas.
#   4. VACUUM (ANALYZE) de la tabla.
#
# La auditoria es de solo insercion y sus registros nuevos siempre tienen la
# hora actual: el conjunto "anterior al corte" no cambia entre los pasos 2 y 3.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

anios="${1:-}"
if ! [[ "$anios" =~ ^[0-9]+$ ]] || [ "$anios" -lt 1 ]; then
  echo "uso: [CONFIRMAR=1] bash db/scripts/purgar_auditoria.sh <anios>   (entero mayor que 0)" >&2
  exit 1
fi

minimo="$(psql_super -At -c "SELECT coalesce(max(retencion_anios), 0) FROM taller_configuracion")"
if [ "$anios" -lt "$minimo" ]; then
  echo "purga: rechazada - $anios anios es menos que la mayor retencion de datos de un taller ($minimo anios)" >&2
  exit 1
fi

corte="$(psql_super -At -c "SELECT (date_trunc('day', now() AT TIME ZONE 'UTC') - make_interval(years => $anios))::timestamp || '+00'")"
total="$(psql_super -At -c "SELECT count(*) FROM auditoria_operacion")"
candidatas="$(psql_super -At -c "SELECT count(*) FROM auditoria_operacion WHERE ocurrido_en < '$corte'::timestamptz")"
echo "purga: corte $corte ($anios anios); registros anteriores al corte: $candidatas de $total"

if [ "${CONFIRMAR:-0}" != "1" ]; then
  echo "purga: SIMULACION - no se elimino nada (repetir con CONFIRMAR=1 para archivar y purgar)"
  exit 0
fi
if [ "$candidatas" = "0" ]; then
  echo "purga: nada que purgar"
  exit 0
fi

dir="${RESPALDO_DIR:-$RAIZ/backups}"
mkdir -p "$dir"
archivo="$dir/auditoria_anterior_a_${corte%% *}_$(date -u +%Y%m%dT%H%M%SZ).csv"

# 2. Archivo. Contiene ids internos, no datos personales (docs/privacidad.md seccion 7).
psql_super -c "COPY (SELECT * FROM auditoria_operacion WHERE ocurrido_en < '$corte'::timestamptz ORDER BY id) TO STDOUT WITH (FORMAT csv, HEADER)" > "$archivo"
( cd "$dir" && sha256sum "$(basename "$archivo")" > "$(basename "$archivo").sha256" )
suma="$(cut -d' ' -f1 "$archivo.sha256")"
chmod 600 "$archivo" "$archivo.sha256" 2>/dev/null || true
echo "purga: archivadas en $(basename "$archivo") ($(wc -c < "$archivo") bytes)"

# 3. Purga y registro de la purga, en una transaccion.
resultado="$(psql_super -At -v corte="$corte" -v esperadas="$candidatas" -v archivo="$(basename "$archivo")" -v suma="$suma" <<'SQL'
BEGIN;
\i /db/ops/purgar_auditoria.sql
\set eliminadas :purga_eliminadas
SELECT :eliminadas = :esperadas AS coincide \gset
\if :coincide
  INSERT INTO auditoria_operacion (rol, operacion, tabla, datos_anteriores, resultado, request_id)
  VALUES (session_user, 'DELETE', 'auditoria_operacion',
          jsonb_build_object('purga_por_retencion', true, 'corte', :'corte', 'registros_eliminados', :eliminadas,
                             'archivo', :'archivo', 'sha256', :'suma'),
          'exito', 'purga-auditoria');
  COMMIT;
  \echo eliminadas=:eliminadas
\else
  ROLLBACK;
  \echo revertida=:eliminadas
\endif
SQL
)"
if [[ "$resultado" != eliminadas=* ]]; then
  echo "purga: FALLO - se iban a eliminar ${resultado#revertida=} filas y se archivaron $candidatas; transaccion revertida" >&2
  exit 1
fi
echo "purga: ${resultado#eliminadas=} registros eliminados; la purga quedo registrada en la auditoria"

# 4. Espacio reutilizable y estadisticas.
psql_super -c "VACUUM (ANALYZE) auditoria_operacion"
echo "purga: quedan $(psql_super -At -c "SELECT count(*) FROM auditoria_operacion") registros"

#!/usr/bin/env bash
# =============================================================================
# Genera la evidencia de la Fase 6 (operacion) sobre una base migrada y con
# semillas:
#   docs/evidencia/fase6_respaldo.txt        respaldo, perdida del volumen,
#                                            restauracion, comparacion y suite;
#                                            verificacion no destructiva
#   docs/evidencia/fase6_operacion.txt       pg_hba, parametros, contenedor, log,
#                                            secretos, proceso periodico, purga
#                                            de auditoria y mantenimiento
#   docs/evidencia/fase6_observabilidad.txt  salida de db/scripts/estado.sh
#   docs/evidencia/fase6_perf.txt            (solo con FASE6_PERF=1) corrida de
#                                            db/perf/run.sh con VACUUM paralelo
#
# ATENCION: la prueba de restauracion ELIMINA el volumen del proyecto y
# reconstruye la base desde el respaldo (como reset.sh). Los respaldos quedan en
# backups/ (ignorada por Git).
# docs/evidencia/fase6_antes.txt es una captura unica del estado anterior a la
# fase y no se regenera.
# Termina con codigo distinto de cero si algun paso falla.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

generar() {
  local salida="$1" titulo="$2"; shift 2
  local codigo=0
  {
    echo "# $titulo (generado por db/scripts/evidencia_fase6.sh)"
    echo "# Fecha: $(date -u +%Y-%m-%dT%H:%MZ)"
    echo
    "$@" || codigo=$?
    echo
    echo "# codigo de salida: $codigo"
  } > "$salida" 2>&1
  echo "evidencia: $salida ($(wc -l < "$salida") lineas, codigo $codigo)"
  return "$codigo"
}

respaldo() {
  local codigo=0
  bash db/scripts/prueba_restauracion.sh || codigo=$?
  echo
  local anterior
  anterior="$(ls -1 "${RESPALDO_DIR:-$RAIZ/backups}"/"${POSTGRES_DB}"_*.dump | sort -r | head -1)"
  echo "### 8. Verificacion no destructiva: respaldo nuevo, restaurado en una base temporal (debe ser identico)"
  bash db/scripts/respaldar.sh | grep -v '^RESPALDO=' || codigo=$?
  EXIGIR_IGUAL=1 bash db/scripts/verificar_respaldo.sh || codigo=$?
  echo
  echo "### 9. La misma verificacion con el respaldo del paso 2, anterior a la suite del paso 7:"
  echo "###    detecta lo que la suite cambio despues (auditoria, secuencias, contador de inicios de sesion)"
  bash db/scripts/verificar_respaldo.sh "$anterior" || codigo=$?
  echo
  echo "### 10. Archivos del respaldo (backups/ esta ignorada por Git)"
  ( cd "${RESPALDO_DIR:-$RAIZ/backups}" && ls -1 | sed 's/^/  /' )
  git check-ignore -q backups/x.dump && echo "git check-ignore backups/: ignorada"
  return "$codigo"
}

operacion() {
  local codigo=0 v n
  echo "## 1. pg_hba.conf efectivo (pg_hba_file_rules)"
  psql_super -c "SELECT line_number, type, database, user_name, address, auth_method, error FROM pg_hba_file_rules ORDER BY 1"
  echo "## 2. Parametros de registro, mantenimiento y observabilidad (y de donde viene cada valor)"
  psql_super -c "SELECT name AS parametro, setting AS valor, coalesce(unit, '') AS unidad, source AS origen FROM pg_settings WHERE name IN ('log_statement', 'log_min_error_statement', 'log_parameter_max_length', 'log_parameter_max_length_on_error', 'log_min_duration_statement', 'log_lock_waits', 'deadlock_timeout', 'log_line_prefix', 'log_connections', 'log_disconnections', 'log_checkpoints', 'log_autovacuum_min_duration', 'log_destination', 'logging_collector', 'autovacuum', 'track_counts', 'shared_preload_libraries', 'pg_stat_statements.track', 'pg_stat_statements.track_utility', 'password_encryption', 'ssl', 'wal_level', 'archive_mode', 'data_checksums', 'max_parallel_maintenance_workers', 'maintenance_work_mem') ORDER BY 1"
  echo "## 3. Contenedor"
  docker compose exec -T db df -h /dev/shm
  echo "rotacion del log (docker inspect): $(docker inspect -f '{{ .HostConfig.LogConfig.Type }} {{ .HostConfig.LogConfig.Config }}' repuestos_exactos_db | tr -d '\r')"
  echo
  echo "## 4. Log del servidor: esperas de bloqueo registradas (log_lock_waits) durante la prueba de concurrencia"
  docker compose logs --no-log-prefix db > "$RAIZ/docs/evidencia/fase6_log.tmp" 2>&1 || true
  echo "lineas 'still waiting for': $(grep -c 'still waiting for' "$RAIZ/docs/evidencia/fase6_log.tmp" || true)"
  { grep -A1 'still waiting for' "$RAIZ/docs/evidencia/fase6_log.tmp" || true; } | head -4
  echo "lineas STATEMENT (texto de sentencias) en todo el log: $(grep -c 'STATEMENT:' "$RAIZ/docs/evidencia/fase6_log.tmp" || true)"
  echo "lineas ERROR en todo el log (mensaje sin sentencia): $(grep -c 'ERROR:' "$RAIZ/docs/evidencia/fase6_log.tmp" || true)"
  echo
  echo "## 5. Claves de .env en el log del contenedor y en pg_stat_statements (solo conteos)"
  for v in POSTGRES_PASSWORD APP_BACKEND_PASSWORD CLAVE_DEMO; do
    n="$(grep -cF -- "${!v}" "$RAIZ/docs/evidencia/fase6_log.tmp" || true)"
    echo "$v en el log: $n linea(s)"
    [ "$n" = "0" ] || codigo=1
  done
  rm -f "$RAIZ/docs/evidencia/fase6_log.tmp"
  psql_super <<'SQL' || codigo=$?
SELECT count(*) FILTER (WHERE strpos(query, :'clave_backend') > 0) AS sentencias_con_clave_backend,
       count(*) FILTER (WHERE strpos(query, :'clave_demo') > 0)    AS sentencias_con_clave_demo,
       count(*) AS sentencias_registradas
FROM   pg_stat_statements;
SQL
  echo "## 6. Proceso periodico de privacidad (db/scripts/anonimizar_vencidos.sh)"
  bash db/scripts/anonimizar_vencidos.sh || codigo=$?
  echo
  echo "## 7. Retencion de la auditoria (db/scripts/purgar_auditoria.sh)"
  echo "# simulacion con 6 anios:"
  bash db/scripts/purgar_auditoria.sh 6 || codigo=$?
  echo "# plazo menor que la retencion de datos de un taller (debe rechazarse):"
  if bash db/scripts/purgar_auditoria.sh 2; then codigo=1; else echo "(codigo de salida $?)"; fi
  echo "# registros que las purgas reales de la suite (OPE-29 a OPE-31) dejaron en la auditoria:"
  psql_super -c "SELECT id, ocurrido_en::timestamptz(0), rol, operacion, tabla, datos_anteriores - 'sha256' AS datos, resultado FROM auditoria_operacion WHERE request_id = 'purga-auditoria' ORDER BY id"
  echo "## 8. Mantenimiento manual (db/scripts/mantenimiento.sh)"
  bash db/scripts/mantenimiento.sh || codigo=$?
  echo
  echo "## 9. Experimento: log_connections activado durante 10 segundos (se revierte al terminar)"
  psql_super -c "ALTER SYSTEM SET log_connections = on" -c "SELECT pg_reload_conf()" >/dev/null
  psql_super -c "SELECT pg_sleep(10)" >/dev/null || true
  psql_super -c "ALTER SYSTEM RESET log_connections" -c "SELECT pg_reload_conf()" >/dev/null
  docker compose logs --no-log-prefix --since 30s db > "$RAIZ/docs/evidencia/fase6_log.tmp" 2>&1 || true
  echo "lineas 'connection received' en esos segundos: $(grep -c 'connection received' "$RAIZ/docs/evidencia/fase6_log.tmp" || true)"
  echo "lineas 'connection authorized' (conexiones autenticadas): $(grep -c 'connection authorized' "$RAIZ/docs/evidencia/fase6_log.tmp" || true)"
  { grep 'connection received' "$RAIZ/docs/evidencia/fase6_log.tmp" || true; } | head -2
  rm -f "$RAIZ/docs/evidencia/fase6_log.tmp"
  echo "log_connections tras revertir: $(psql_super -At -c "SELECT pg_sleep(0.5)" -c "SHOW log_connections" | tail -1)"
  return "$codigo"
}

fallo=0
generar docs/evidencia/fase6_respaldo.txt       "Respaldo y restauracion probados (db/scripts/prueba_restauracion.sh)" respaldo || fallo=1
generar docs/evidencia/fase6_operacion.txt      "Operacion: acceso, registro, secretos, privacidad, auditoria y mantenimiento" operacion || fallo=1
generar docs/evidencia/fase6_observabilidad.txt "Observabilidad (db/scripts/estado.sh)" bash db/scripts/estado.sh || fallo=1
if [ "${FASE6_PERF:-0}" = "1" ]; then
  # run.sh reescribe fase5_*.txt. Esos archivos son la evidencia que cita
  # docs/evidencia/rendimiento.md (Fase 5) y los tiempos varian entre corridas:
  # se conservan los originales y esta corrida queda solo en fase6_perf.txt.
  guardados="$(mktemp -d)"
  cp docs/evidencia/fase5_medidas.txt docs/evidencia/fase5_indices.txt docs/evidencia/fase5_resumen.txt "$guardados/"
  generar docs/evidencia/fase6_perf.txt "Medicion de rendimiento con shm_size 256 MB y VACUUM paralelo (db/perf/run.sh)" bash db/perf/run.sh || fallo=1
  cp "$guardados"/fase5_*.txt docs/evidencia/
  rm -rf "$guardados"
fi
exit "$fallo"

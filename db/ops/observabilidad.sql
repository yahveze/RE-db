-- =============================================================================
-- Estado de la base: consultas de observabilidad para el operador.
-- Solo lectura. Ejecutar como superusuario: bash db/scripts/estado.sh
-- Las vistas de pg_stat_statements no son legibles por los roles de taller.
-- =============================================================================
\pset pager off
\echo '## 1. Servidor'
SELECT current_setting('server_version') AS version,
       pg_postmaster_start_time()::timestamptz(0) AS iniciado,
       pg_size_pretty(pg_database_size(current_database())) AS tamanio_base,
       (SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend') AS conexiones,
       current_setting('max_connections') AS max_conexiones;

\echo '## 2. Conexiones por rol y estado'
SELECT usename AS rol, state AS estado, count(*) AS conexiones,
       max(now() - state_change)::interval(0) AS mas_antigua_en_estado
FROM   pg_stat_activity
WHERE  backend_type = 'client backend'
GROUP  BY usename, state
ORDER  BY usename, state;

\echo '## 3. Transacciones abiertas hace mas de 1 minuto (retienen bloqueos e impiden el vacuum)'
SELECT pid, usename AS rol, state AS estado, (now() - xact_start)::interval(0) AS abierta_hace,
       left(query, 60) AS ultima_sentencia
FROM   pg_stat_activity
WHERE  xact_start < now() - interval '1 minute' AND backend_type = 'client backend'
ORDER  BY xact_start;

\echo '## 4. Sesiones esperando un bloqueo, y quien las bloquea'
SELECT a.pid AS espera, pg_blocking_pids(a.pid) AS bloqueada_por,
       (now() - a.query_start)::interval(0) AS esperando_hace, left(a.query, 60) AS sentencia
FROM   pg_stat_activity a
WHERE  a.wait_event_type = 'Lock';

\echo '## 5. Tablas: tamanio, filas vivas y muertas, ultimo vacuum y analyze'
SELECT s.relname AS tabla,
       pg_size_pretty(pg_total_relation_size(s.relid)) AS total,
       s.n_live_tup AS vivas, s.n_dead_tup AS muertas,
       coalesce(greatest(s.last_vacuum, s.last_autovacuum)::timestamptz(0)::text, '-')   AS ultimo_vacuum,
       coalesce(greatest(s.last_analyze, s.last_autoanalyze)::timestamptz(0)::text, '-') AS ultimo_analyze
FROM   pg_stat_user_tables s
WHERE  s.schemaname = 'public'
ORDER  BY pg_total_relation_size(s.relid) DESC, s.relname;

\echo '## 6. Indices de rendimiento (ix_) sin recorridos desde el ultimo reinicio de estadisticas'
\echo '##    (candidatos a revisar; idx_scan cuenta tambien los sondeos del planificador)'
SELECT i.relname AS tabla, i.indexrelname AS indice,
       pg_size_pretty(pg_relation_size(i.indexrelid)) AS tamanio, i.idx_scan AS recorridos
FROM   pg_stat_user_indexes i
WHERE  i.schemaname = 'public' AND i.indexrelname LIKE 'ix\_%' AND i.idx_scan = 0
ORDER  BY i.relname, i.indexrelname;

\echo '## 7. Sentencias con mas tiempo acumulado (pg_stat_statements; constantes normalizadas)'
SELECT r.rolname AS rol, s.calls AS llamadas,
       round(s.total_exec_time::numeric, 1) AS total_ms,
       round(s.mean_exec_time::numeric, 2)  AS media_ms,
       round(s.max_exec_time::numeric, 2)   AS max_ms,
       s.rows AS filas,
       left(regexp_replace(s.query, '\s+', ' ', 'g'), 70) AS sentencia
FROM   pg_stat_statements s
JOIN   pg_roles r ON r.oid = s.userid
WHERE  s.dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER  BY s.total_exec_time DESC
LIMIT  10;

\echo '## 8. Actividad de la base: confirmaciones, reversiones, interbloqueos, archivos temporales'
SELECT xact_commit AS confirmadas, xact_rollback AS revertidas, deadlocks AS interbloqueos,
       temp_files AS archivos_temporales, pg_size_pretty(temp_bytes) AS bytes_temporales,
       round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS pct_aciertos_cache,
       coalesce(stats_reset::timestamptz(0)::text, '-') AS estadisticas_desde
FROM   pg_stat_database
WHERE  datname = current_database();

\echo '## 9. Edad de los identificadores de transaccion (autovacuum forzado al llegar al limite)'
SELECT datname AS base, age(datfrozenxid) AS edad_xid,
       current_setting('autovacuum_freeze_max_age') AS limite_autovacuum
FROM   pg_database
WHERE  datname = current_database();

\echo '## 10. Privacidad: bloqueos de titular vencidos sin anonimizar (0 si el proceso periodico corre)'
SELECT count(*) AS bloqueos_vencidos_pendientes
FROM   titular
WHERE  estado_tratamiento = 'bloqueado' AND bloqueado_hasta <= current_date;

\echo '## 11. Auditoria: volumen y antiguedad'
SELECT count(*) AS registros,
       pg_size_pretty(pg_total_relation_size('auditoria_operacion')) AS tamanio,
       coalesce(min(ocurrido_en)::timestamptz(0)::text, '-') AS mas_antiguo,
       coalesce(max(ocurrido_en)::timestamptz(0)::text, '-') AS mas_reciente,
       count(*) FILTER (WHERE resultado <> 'exito') AS no_exitosos
FROM   auditoria_operacion;

\echo '## 12. Accesos: inicios de sesion fallidos de las ultimas 24 horas y cuentas bloqueadas'
SELECT (SELECT count(*) FROM auditoria_operacion
        WHERE operacion = 'LOGIN_FALLIDO' AND ocurrido_en > now() - interval '24 hours') AS login_fallidos_24h,
       (SELECT count(*) FROM usuario_credencial WHERE bloqueado_hasta > now()) AS cuentas_bloqueadas;

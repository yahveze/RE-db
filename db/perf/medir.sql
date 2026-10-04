-- =============================================================================
-- Medicion de rendimiento sobre la base de volumen (la ejecuta db/perf/run.sh).
-- Elige los parametros como plataforma, se conecta como el backend, calienta la
-- cache y mide. Todo dentro de una transaccion que termina en ROLLBACK.
-- =============================================================================
\set ON_ERROR_STOP on
\encoding UTF8
\pset pager off

\echo '# Entorno'
SELECT current_setting('server_version') AS version,
       current_setting('shared_buffers') AS shared_buffers,
       current_setting('work_mem') AS work_mem,
       current_setting('random_page_cost') AS random_page_cost,
       current_setting('max_parallel_workers_per_gather') AS paralelos_por_gather,
       current_setting('jit') AS jit;

-- ----------------------------------------------------------- parametros
SELECT id AS tv FROM taller WHERE nombre = 'Taller Volumen 01' \gset
SELECT id AS u_mec FROM usuario WHERE email = 'mecanico1@volumen01.example' \gset
SELECT id AS u_adm FROM usuario WHERE email = 'admin@volumen01.example' \gset

\echo
\echo '# Taller medido (el grande) frente al total'
SELECT (SELECT count(*) FROM sesion_diagnostico WHERE taller_id = :tv)  AS sesiones_taller,
       (SELECT count(*) FROM sesion_diagnostico)                        AS sesiones_total,
       (SELECT count(*) FROM sesion_diagnostico WHERE taller_id = :tv AND estado = 'pendiente') AS pendientes_taller,
       (SELECT count(*) FROM vehiculo WHERE taller_id = :tv)            AS vehiculos_taller,
       (SELECT count(*) FROM auditoria_operacion WHERE taller_id = :tv) AS auditoria_taller,
       (SELECT count(*) FROM auditoria_operacion)                       AS auditoria_total;

-- Sesion pendiente con borrador, pendiente sin borrador y una completada antigua.
SELECT s.id_publico AS ses_pend, c.id_publico AS cot_borr
FROM   sesion_diagnostico s JOIN cotizacion c ON c.sesion_id = s.id AND c.cerrada_en IS NULL
WHERE  s.taller_id = :tv AND s.estado = 'pendiente' ORDER BY s.id LIMIT 1 \gset
SELECT s.id_publico AS ses_libre
FROM   sesion_diagnostico s
WHERE  s.taller_id = :tv AND s.estado = 'pendiente'
AND    NOT EXISTS (SELECT 1 FROM cotizacion c WHERE c.sesion_id = s.id) ORDER BY s.id LIMIT 1 \gset
SELECT s.id_publico AS ses_comp, c.id_publico AS cot_comp
FROM   sesion_diagnostico s JOIN cotizacion c ON c.sesion_id = s.id AND c.vigente
WHERE  s.taller_id = :tv AND s.estado = 'completado' AND s.id % 5 = 0 ORDER BY s.id LIMIT 1 \gset
-- Cursor de la pagina profunda: la sesion numero 75.000 del historial del taller.
SELECT s.iniciada_en AS cur_ts, s.id_publico AS cur_id
FROM   sesion_diagnostico s WHERE s.taller_id = :tv
ORDER  BY s.iniciada_en DESC, s.id DESC OFFSET 75000 LIMIT 1 \gset
SELECT a.ocurrido_en AS aud_ts, a.id AS aud_id
FROM   auditoria_operacion a WHERE a.taller_id = :tv
ORDER  BY a.ocurrido_en DESC, a.id DESC OFFSET 500000 LIMIT 1 \gset
-- Un vehiculo con VIN, su modelo y su anio.
SELECT v.id_publico AS veh, v.patente, v.vin, v.anio, mo.id_publico AS modelo
FROM   vehiculo v JOIN modelo_vehiculo mo ON mo.id = v.modelo_vehiculo_id
WHERE  v.taller_id = :tv AND v.vin IS NOT NULL AND v.titular_id IS NOT NULL ORDER BY v.id OFFSET 5000 LIMIT 1 \gset
SELECT d.codigo AS dtc
FROM   falla_sesion f JOIN sesion_diagnostico s ON s.id = f.sesion_id JOIN dtc_catalogo d ON d.id = f.dtc_id
WHERE  s.id_publico = :'ses_pend' ORDER BY d.codigo LIMIT 1 \gset
SELECT r.id_publico AS rep FROM repuesto r WHERE r.codigo_fabricante = 'SIN-5-50' \gset
-- Titular con varias sesiones, para la supresion.
SELECT t.id_publico AS tit
FROM   titular t WHERE t.taller_id = :tv AND t.estado_tratamiento = 'activo' ORDER BY t.id OFFSET 100 LIMIT 1 \gset

SET SESSION AUTHORIZATION app_backend_user;
\ir ../queries/preparar.sql
\ir anteriores.sql

BEGIN;

-- Primera pasada: calentar. Salida descartada, cambios revertidos.
SAVEPOINT calentamiento;
\o /dev/null
\ir medidas.sql
\o
ROLLBACK TO calentamiento;

-- Segunda pasada: la que se registra.
\echo
\echo '# Medidas (segunda ejecucion de cada sentencia, cache caliente)'
\ir medidas.sql

ROLLBACK;
RESET SESSION AUTHORIZATION;

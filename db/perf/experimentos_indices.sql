-- =============================================================================
-- Experimentos sobre los indices que las consultas medidas no usan (Fase 5).
-- Para cada uno: la sentencia que deberia aprovecharlo, CON el indice y SIN el
-- (DROP INDEX dentro de la transaccion). Todo termina en ROLLBACK.
-- Se ejecuta sobre la base de volumen (db/perf/run.sh).
-- =============================================================================
\set ON_ERROR_STOP on
\encoding UTF8
\pset pager off

SELECT id AS tv FROM taller WHERE nombre = 'Taller Volumen 01' \gset
SELECT id AS u_adm FROM usuario WHERE email = 'admin@volumen01.example' \gset
SELECT t.id AS tit FROM titular t WHERE t.taller_id = :tv AND t.estado_tratamiento = 'activo' ORDER BY t.id OFFSET 100 LIMIT 1 \gset

\ir ../queries/preparar.sql

BEGIN;

-- ----------------------------------------------------------------------------
\echo
\echo '## E0 Igualdad de enum bajo RLS: por que V009 reemplazo el indice (taller_id, estado, ...) por indices parciales'
SELECT proname AS operador, proleakproof AS leakproof
FROM   pg_proc WHERE proname IN ('enum_eq', 'int8eq', 'uuid_eq', 'texteq', 'timestamptz_ge') ORDER BY 1;
-- Se recrea, solo dentro de esta transaccion, el indice que tenia V006.
DROP INDEX ix_sesion_diagnostico_cotizado;
CREATE INDEX ix_tmp_estado ON sesion_diagnostico (taller_id, estado, iniciada_en DESC, id DESC);
\echo '-- A) indice (taller_id, estado, ...) SIN RLS (plataforma): estado es condicion del indice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM sesion_diagnostico WHERE taller_id = :tv AND estado = 'cotizado';
SET LOCAL ROLE taller_mecanico;
SELECT set_config('app.taller_id', :'tv', true) \gset x_
\echo '-- B) el mismo indice CON RLS (taller_mecanico): estado queda como filtro'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM sesion_diagnostico WHERE estado = 'cotizado';
RESET ROLE;
DROP INDEX ix_tmp_estado;
CREATE INDEX ix_sesion_diagnostico_cotizado ON sesion_diagnostico (taller_id, iniciada_en DESC, id DESC) WHERE estado = 'cotizado';
SET LOCAL ROLE taller_mecanico;
\echo '-- C) indice PARCIAL (WHERE estado = cotizado) CON RLS: el estado no se evalua por fila'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM sesion_diagnostico WHERE estado = 'cotizado';
RESET ROLE;

-- ----------------------------------------------------------------------------
\echo
\echo '## E1 ix_falla_sesion_dtc - comprobacion de la FK al borrar un DTC del catalogo (604.000 fallas)'
INSERT INTO dtc_catalogo (codigo, descripcion, severidad_sugerida) VALUES ('B3FFF', 'DTC sin uso', 'baja');
\echo '-- con el indice'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) DELETE FROM dtc_catalogo WHERE codigo = 'B3FFF';
INSERT INTO dtc_catalogo (codigo, descripcion, severidad_sugerida) VALUES ('B3FFF', 'DTC sin uso', 'baja');
DROP INDEX ix_falla_sesion_dtc;
\echo '-- sin el indice'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) DELETE FROM dtc_catalogo WHERE codigo = 'B3FFF';

-- ----------------------------------------------------------------------------
\echo
\echo '## E2 ix_compatibilidad_repuesto_modelo - FK al borrar un modelo (225.000 compatibilidades)'
INSERT INTO modelo_vehiculo (marca_vehiculo_id, nombre) SELECT min(id), 'Modelo sin uso' FROM marca_vehiculo;
\echo '-- con el indice'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) DELETE FROM modelo_vehiculo WHERE nombre = 'Modelo sin uso';
INSERT INTO modelo_vehiculo (marca_vehiculo_id, nombre) SELECT min(id), 'Modelo sin uso' FROM marca_vehiculo;
DROP INDEX ix_compatibilidad_repuesto_modelo;
\echo '-- sin el indice'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) DELETE FROM modelo_vehiculo WHERE nombre = 'Modelo sin uso';

-- ----------------------------------------------------------------------------
\echo
\echo '## E3 ix_vehiculo_taller_titular - sentencias de la supresion (ultima atencion y anonimizacion de vehiculos)'
\echo '-- con el indice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT max(s.iniciada_en)
FROM   sesion_diagnostico s
JOIN   vehiculo v ON v.id = s.vehiculo_id AND v.taller_id = s.taller_id
WHERE  v.titular_id = :tit AND v.taller_id = :tv AND s.estado <> 'cancelado';
DROP INDEX ix_vehiculo_taller_titular;
\echo '-- sin el indice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT max(s.iniciada_en)
FROM   sesion_diagnostico s
JOIN   vehiculo v ON v.id = s.vehiculo_id AND v.taller_id = s.taller_id
WHERE  v.titular_id = :tit AND v.taller_id = :tv AND s.estado <> 'cancelado';

-- ----------------------------------------------------------------------------
\echo
\echo '## E4 ix_titular_bloqueado_hasta - consulta del proceso de anonimizacion de vencidos (2.000 bloqueados de 37.757)'
UPDATE titular SET estado_tratamiento = 'bloqueado', bloqueado_hasta = current_date + (id % 400)::int - 200
WHERE  taller_id = :tv AND id % 10 = 0;
ANALYZE titular;
\echo '-- con el indice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT t.id FROM titular t
WHERE  t.estado_tratamiento = 'bloqueado' AND t.bloqueado_hasta <= current_date ORDER BY t.id;
DROP INDEX ix_titular_bloqueado_hasta;
\echo '-- sin el indice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT t.id FROM titular t
WHERE  t.estado_tratamiento = 'bloqueado' AND t.bloqueado_hasta <= current_date ORDER BY t.id;

-- ----------------------------------------------------------------------------
\echo
\echo '## E5 ix_consentimiento_titular_taller_titular - revocacion de consentimientos al anonimizar'
\echo '-- con el indice (el planificador elige uq_consentimiento_titular_activo)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT c.id FROM consentimiento_titular c WHERE c.titular_id = :tit AND c.revocado_en IS NULL;
\echo '-- todos los consentimientos de un titular, como los pediria la API (con taller)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT c.id FROM consentimiento_titular c WHERE c.taller_id = :tv AND c.titular_id = :tit;
DROP INDEX ix_consentimiento_titular_taller_titular;
\echo '-- la misma, sin el indice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT c.id FROM consentimiento_titular c WHERE c.taller_id = :tv AND c.titular_id = :tit;

-- ----------------------------------------------------------------------------
\echo
\echo '## E6 ix_usuario_taller (eliminado en V009) - q_usuarios con 3.000 talleres y 30.000 usuarios mas'
SET LOCAL session_replication_role = replica;
INSERT INTO taller (nombre) SELECT 'Taller Escala ' || g FROM generate_series(1, 3000) g;
INSERT INTO usuario (taller_id, email, nombre, rol)
SELECT t.id, 'u' || g || '@escala' || t.id || '.example', 'Usuario ' || g, 'mecanico'
FROM   taller t, generate_series(1, 10) g WHERE t.nombre LIKE 'Taller Escala %';
INSERT INTO solicitud_derecho_titular (taller_id, titular_id, tipo)
SELECT x.taller_id, x.id, 'acceso' FROM titular x;
SET LOCAL session_replication_role = origin;
ANALYZE usuario;
ANALYZE solicitud_derecho_titular;
SET LOCAL ROLE taller_admin;
SELECT set_config('app.taller_id', :'tv', true), set_config('app.usuario_id', :'u_adm', true) \gset x_
\echo '-- sin el indice (estado actual)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) EXECUTE q_usuarios;
\echo
\echo '## E7 ix_solicitud_derecho_titular_taller_titular (eliminado en V009) - q_solicitudes_derecho con 37.757 solicitudes mas'
\echo '-- sin el indice (estado actual)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) EXECUTE q_solicitudes_derecho;
RESET ROLE;
CREATE INDEX ix_usuario_taller ON usuario (taller_id);
CREATE INDEX ix_solicitud_derecho_titular_taller_titular ON solicitud_derecho_titular (taller_id, titular_id);
SET LOCAL ROLE taller_admin;
\echo
\echo '-- E6 con el indice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) EXECUTE q_usuarios;
\echo '-- E7 con el indice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) EXECUTE q_solicitudes_derecho;
RESET ROLE;

ROLLBACK;

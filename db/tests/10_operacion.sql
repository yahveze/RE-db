-- =============================================================================
-- 10. Operacion (Fase 6): configuracion del servidor que la operacion da por
-- supuesta y purga de la auditoria por retencion. Lo que necesita conexiones
-- reales o leer el log del servidor esta en db/tests/operacion.sh.
-- =============================================================================
\ir incluir/inicio.sql
\echo '### 10 Operacion'

\ir incluir/rol_plataforma.sql

-- ----------------------------------------------------------------------------
-- Acceso al servidor
-- ----------------------------------------------------------------------------
\set prueba 'OPE-01 pg_hba.conf: todas las reglas exigen scram-sha-256, tambien el socket local; ninguna usa trust (T-43)'
SELECT count(*) > 0
   AND bool_and(auth_method = 'scram-sha-256')
   AND bool_and(error IS NULL)
   AND count(*) FILTER (WHERE type = 'local') > 0 AS ok
FROM   pg_hba_file_rules \gset
\ir incluir/afirmar.sql

-- ----------------------------------------------------------------------------
-- Registro (log) del servidor
-- ----------------------------------------------------------------------------
\set prueba 'OPE-02 el log no recibe sentencias ni parametros: log_statement none, log_min_error_statement panic, parametros con longitud 0 (T-13)'
SELECT current_setting('log_statement') = 'none'
   AND current_setting('log_min_error_statement') = 'panic'
   AND current_setting('log_parameter_max_length') = '0'
   AND current_setting('log_parameter_max_length_on_error') = '0' AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'OPE-03 el log de sentencias lentas esta apagado: registraria los literales de quien no usa parametros'
SELECT current_setting('log_min_duration_statement') = '-1' AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'OPE-04 el log registra esperas de bloqueo e identifica usuario y base en cada linea'
SELECT current_setting('log_lock_waits') = 'on'
   AND position('%u' IN current_setting('log_line_prefix')) > 0
   AND position('%d' IN current_setting('log_line_prefix')) > 0
   AND position('%m' IN current_setting('log_line_prefix')) > 0 AS ok \gset
\ir incluir/afirmar.sql

-- ----------------------------------------------------------------------------
-- Mantenimiento y observabilidad
-- ----------------------------------------------------------------------------
\set prueba 'OPE-05 mantenimiento automatico activo: autovacuum y track_counts'
SELECT current_setting('autovacuum') = 'on' AND current_setting('track_counts') = 'on' AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'OPE-06 pg_stat_statements esta cargada y ningun rol de la aplicacion puede leerla'
SELECT current_setting('shared_preload_libraries') LIKE '%pg_stat_statements%'
   AND EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements')
   AND NOT bool_or(has_table_privilege(r.rolname, 'pg_stat_statements', 'SELECT'))
   AND NOT bool_or(pg_has_role(r.rolname, 'pg_read_all_stats', 'MEMBER'))
   AND count(*) = 6 AS ok
FROM   pg_roles r
WHERE  r.rolname IN ('app_owner', 'app_funciones', 'app_backend_user', 'taller_admin', 'taller_mecanico', 'taller_auditor') \gset
\ir incluir/afirmar.sql

-- pg_stat_statements normaliza las constantes de SELECT/INSERT/UPDATE/DELETE,
-- pero guarda el texto de las sentencias de utilidad tal cual: el
-- CREATE ROLE ... PASSWORD de V000 quedaria legible. migrate.sh, seed.sh,
-- restaurar.sh y perf/run.sh vacian las estadisticas al terminar.
\set prueba 'OPE-07 pg_stat_statements no contiene las claves de .env (ni la del backend ni la de demostracion)'
SELECT count(*) = 0 AS ok
FROM   pg_stat_statements
WHERE  strpos(query, :'clave_backend') > 0 OR strpos(query, :'clave_demo') > 0 \gset
\ir incluir/afirmar.sql

\set prueba 'OPE-08 el proceso periodico no tiene trabajo atrasado: ningun bloqueo de titular vencido sin anonimizar'
SELECT count(*) = 0 AS ok
FROM   titular
WHERE  estado_tratamiento = 'bloqueado' AND bloqueado_hasta <= current_date \gset
\ir incluir/afirmar.sql

-- ----------------------------------------------------------------------------
-- Retencion de la auditoria: db/ops/purgar_auditoria.sql
-- ----------------------------------------------------------------------------
SELECT count(*) AS aud_antes FROM auditoria_operacion \gset

\set prueba 'OPE-09 preparacion: tres registros de auditoria con 40 anios de antiguedad'
\set esperado 3
INSERT INTO auditoria_operacion (ocurrido_en, rol, operacion, tabla, resultado, request_id)
SELECT now() - interval '40 years' - g * interval '1 day', 'prueba', 'INSERT', 'prueba_purga', 'exito', 'ope-purga'
FROM   generate_series(1, 3) g;
\ir incluir/filas.sql

\set prueba 'OPE-10 un registro antiguo tampoco se puede borrar con un DELETE directo, ni siquiera como superusuario'
\set esperado RE005
DELETE FROM auditoria_operacion WHERE request_id = 'ope-purga';
\ir incluir/error.sql

SELECT (now() - interval '30 years')::text AS corte \gset
\ir ../ops/purgar_auditoria.sql

\set prueba 'OPE-11 la purga elimina exactamente los registros anteriores al corte y ninguno posterior'
SELECT :purga_eliminadas = 3
   AND (SELECT count(*) FROM auditoria_operacion) = :aud_antes
   AND NOT EXISTS (SELECT 1 FROM auditoria_operacion WHERE request_id = 'ope-purga') AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'OPE-12 terminada la purga, la auditoria vuelve a ser inmutable dentro de la misma transaccion'
\set esperado RE005
DELETE FROM auditoria_operacion WHERE id = (SELECT min(id) FROM auditoria_operacion);
\ir incluir/error.sql

\set prueba 'OPE-13 TRUNCATE sigue rechazado despues de la purga'
\set esperado RE005
TRUNCATE auditoria_operacion;
\ir incluir/error.sql

\ir ../ops/purgar_auditoria.sql
\set prueba 'OPE-14 repetir la purga con el mismo corte no elimina nada (idempotente)'
SELECT :purga_eliminadas = 0 AND (SELECT count(*) FROM auditoria_operacion) = :aud_antes AS ok \gset
\ir incluir/afirmar.sql

-- La purga se apoya en session_replication_role, que desactiva los triggers.
-- Solo un superusuario puede fijarlo: ningun rol de la aplicacion puede usar el
-- mismo camino para saltarse la inmutabilidad.
\ir incluir/rol_admin_1.sql
\set prueba 'OPE-15 el administrador del taller no puede desactivar los triggers (session_replication_role)'
\set esperado 42501
SET LOCAL session_replication_role = replica;
\ir incluir/error.sql

\ir incluir/rol_backend.sql
\set prueba 'OPE-16 la conexion del backend tampoco'
\set esperado 42501
SET LOCAL session_replication_role = replica;
\ir incluir/error.sql

\ir incluir/rol_plataforma.sql
SET LOCAL ROLE app_owner;
\set prueba 'OPE-17 ni el propietario de las tablas (app_owner)'
\set esperado 42501
SET LOCAL session_replication_role = replica;
\ir incluir/error.sql
RESET ROLE;

ROLLBACK;

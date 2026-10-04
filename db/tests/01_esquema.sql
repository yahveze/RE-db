-- =============================================================================
-- 01 - Invariantes del esquema (se leen del catalogo del motor).
-- =============================================================================
\ir incluir/inicio.sql
\echo '### 01 Esquema'

\set prueba 'ESQ-01 hay 21 tablas y 1 vista en public'
SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r') = 21
   AND (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'v' AND c.relname LIKE 'v\_%') = 1 AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-02 ninguna columna usa SERIAL (default nextval)'
SELECT count(*) = 0 AS ok
FROM   information_schema.columns
WHERE  table_schema = 'public' AND column_default LIKE 'nextval%' \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-03 toda columna id es BIGINT GENERATED ALWAYS AS IDENTITY'
SELECT count(*) > 0 AND bool_and(data_type = 'bigint' AND is_identity = 'YES' AND identity_generation = 'ALWAYS') AS ok
FROM   information_schema.columns
WHERE  table_schema = 'public' AND column_name = 'id' \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-04 ninguna columna de tiempo es TIMESTAMP sin zona'
SELECT count(*) = 0 AS ok
FROM   information_schema.columns
WHERE  table_schema = 'public' AND data_type = 'timestamp without time zone' \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-05 todas las tablas y todas sus columnas tienen COMMENT'
SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r' AND obj_description(c.oid, 'pg_class') IS NULL) = 0
   AND (SELECT count(*) FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
        AND   col_description(c.oid, a.attnum) IS NULL) = 0 AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-06 toda tabla con taller_id, mas taller y usuario_credencial, tiene RLS activo y forzado'
SELECT count(*) = 14 AND bool_and(c.relrowsecurity AND c.relforcerowsecurity) AS ok
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'public' AND c.relkind = 'r'
AND    (c.relname IN ('taller', 'usuario_credencial')
        OR EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'taller_id' AND NOT a.attisdropped)) \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-07 los 7 catalogos globales no tienen RLS'
SELECT count(*) = 7 AND bool_and(NOT c.relrowsecurity) AS ok
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname = 'public'
AND    c.relname IN ('marca_vehiculo', 'modelo_vehiculo', 'dtc_catalogo', 'componente_repuesto',
                     'dtc_componente', 'repuesto', 'compatibilidad_repuesto') \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-08 usuario_credencial no tiene ninguna politica; el resto de tablas con RLS si'
SELECT (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'usuario_credencial') = 0
   AND (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relrowsecurity AND c.relname <> 'usuario_credencial'
        AND NOT EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = c.relname)) = 0 AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-09 ninguna politica aplica a PUBLIC'
SELECT count(*) = 0 AS ok FROM pg_policies WHERE schemaname = 'public' AND 'public' = ANY (roles) \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-10 hay 6 funciones SECURITY DEFINER, todas de app_funciones y con search_path fijo'
SELECT count(*) = 6
   AND bool_and(pg_get_userbyid(p.proowner) = 'app_funciones')
   AND bool_and(EXISTS (SELECT 1 FROM unnest(p.proconfig) x WHERE x LIKE 'search_path=%')) AS ok
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.prosecdef AND p.proname LIKE 'fn\_%' \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-11 toda funcion fn_ fija search_path y las no definidoras son de app_owner'
SELECT bool_and(EXISTS (SELECT 1 FROM unnest(p.proconfig) x WHERE x LIKE 'search_path=%'))
   AND bool_and(p.prosecdef OR pg_get_userbyid(p.proowner) = 'app_owner') AS ok
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname LIKE 'fn\_%' \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-12 tablas, vista y tipos enumerados pertenecen a app_owner'
SELECT (SELECT bool_and(pg_get_userbyid(c.relowner) = 'app_owner')
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v') AND c.relname NOT LIKE 'pg\_stat\_%')
   AND (SELECT count(*) = 14 AND bool_and(pg_get_userbyid(t.typowner) = 'app_owner' AND t.typname LIKE 'tipo\_%')
        FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public' AND t.typtype = 'e') AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-13 atributos de los roles (LOGIN, BYPASSRLS, SUPERUSER)'
SELECT bool_and(CASE rolname
         WHEN 'app_backend_user' THEN rolcanlogin     AND NOT rolbypassrls AND NOT rolsuper AND NOT rolinherit
         WHEN 'app_funciones'    THEN NOT rolcanlogin AND rolbypassrls     AND NOT rolsuper
         ELSE                         NOT rolcanlogin AND NOT rolbypassrls AND NOT rolsuper
       END) AND count(*) = 6 AS ok
FROM   pg_roles
WHERE  rolname IN ('app_owner', 'app_funciones', 'app_backend_user', 'taller_admin', 'taller_mecanico', 'taller_auditor') \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-14 app_backend_user es miembro de los 3 grupos con INHERIT FALSE y SET TRUE'
SELECT count(*) = 3 AND bool_and(NOT m.inherit_option AND m.set_option AND NOT m.admin_option) AS ok
FROM   pg_auth_members m
WHERE  m.member = 'app_backend_user'::regrole \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-15 app_backend_user y PUBLIC no tienen privilegios sobre ninguna tabla ni columna'
SELECT (SELECT count(*) FROM information_schema.table_privileges
        WHERE table_schema = 'public' AND grantee IN ('app_backend_user', 'PUBLIC')) = 0
   AND (SELECT count(*) FROM information_schema.column_privileges
        WHERE table_schema = 'public' AND grantee IN ('app_backend_user', 'PUBLIC')) = 0 AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-16 PUBLIC no tiene EXECUTE sobre ninguna funcion fn_'
SELECT count(*) = 0 AS ok
FROM   information_schema.routine_privileges
WHERE  routine_schema = 'public' AND routine_name LIKE 'fn\_%' AND grantee = 'PUBLIC' \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-17 el unico privilegio propio de app_backend_user es EXECUTE sobre fn_autenticar_usuario'
SELECT count(*) = 1 AND min(routine_name) = 'fn_autenticar_usuario' AS ok
FROM   information_schema.routine_privileges
WHERE  routine_schema = 'public' AND grantee = 'app_backend_user' \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-18 ningun rol de taller tiene TRUNCATE; el unico DELETE es de taller_mecanico sobre cotizacion_detalle'
SELECT count(*) FILTER (WHERE privilege_type = 'TRUNCATE') = 0
   AND count(*) FILTER (WHERE privilege_type = 'DELETE') = 1
   AND min(grantee || '.' || table_name) FILTER (WHERE privilege_type = 'DELETE') = 'taller_mecanico.cotizacion_detalle' AS ok
FROM   information_schema.table_privileges
WHERE  table_schema = 'public' AND grantee IN ('taller_admin', 'taller_mecanico', 'taller_auditor') \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-19 ningun rol de taller puede escribir en catalogos ni en la auditoria'
SELECT count(*) = 0 AS ok
FROM  (SELECT grantee, table_name, privilege_type FROM information_schema.table_privileges WHERE table_schema = 'public'
       UNION ALL
       SELECT grantee, table_name, privilege_type FROM information_schema.column_privileges WHERE table_schema = 'public') p
WHERE  p.grantee IN ('taller_admin', 'taller_mecanico', 'taller_auditor')
AND    p.privilege_type <> 'SELECT'
AND    p.table_name IN ('marca_vehiculo', 'modelo_vehiculo', 'dtc_catalogo', 'componente_repuesto', 'dtc_componente',
                        'repuesto', 'compatibilidad_repuesto', 'auditoria_operacion', 'usuario_credencial', 'taller') \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-20 ningun CHECK usa now(), current_date ni subconsultas'
SELECT count(*) = 0 AS ok
FROM   pg_constraint c
JOIN   pg_namespace n ON n.oid = c.connamespace
WHERE  n.nspname = 'public' AND c.contype = 'c'
AND    pg_get_constraintdef(c.oid) ~* '(now\(\)|current_date|current_timestamp|clock_timestamp|select )' \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-21 las 10 FK entre tablas de taller son compuestas e incluyen taller_id (aislamiento estructural)'
SELECT count(*) = 10 AND bool_and(EXISTS (
         SELECT 1 FROM pg_attribute a
         WHERE a.attrelid = c.conrelid AND a.attname = 'taller_id' AND a.attnum = ANY (c.conkey))) AS ok
FROM   pg_constraint c
JOIN   pg_namespace n ON n.oid = c.connamespace
WHERE  n.nspname = 'public' AND c.contype = 'f'
AND    c.confrelid <> 'taller'::regclass
AND    c.conrelid  <> 'usuario_credencial'::regclass
AND    EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.confrelid AND a.attname = 'taller_id') \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-22 toda FK es ON DELETE RESTRICT, salvo las dos CASCADE declaradas'
SELECT count(*) FILTER (WHERE c.confdeltype = 'c') = 2
   AND count(*) FILTER (WHERE c.confdeltype NOT IN ('r', 'c')) = 0
   AND bool_and(c.confdeltype <> 'c' OR c.conname IN ('fk_usuario_credencial_usuario', 'fk_cotizacion_detalle_cotizacion')) AS ok
FROM   pg_constraint c
JOIN   pg_namespace n ON n.oid = c.connamespace
WHERE  n.nspname = 'public' AND c.contype = 'f' \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-23 convencion de nombres: restricciones, indices, triggers, politicas'
SELECT (SELECT bool_and(c.conname ~ ('^' || CASE c.contype WHEN 'p' THEN 'pk' WHEN 'f' THEN 'fk' WHEN 'u' THEN 'uq' WHEN 'c' THEN 'ck' END || '_'))
        FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'public' AND c.contype IN ('p', 'f', 'u', 'c'))
   AND (SELECT bool_and(indexname ~ '^(pk|uq|ix)_') FROM pg_indexes WHERE schemaname = 'public')
   AND (SELECT bool_and(t.tgname ~ '^trg_') FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND NOT t.tgisinternal)
   AND (SELECT bool_and(policyname ~ ('^pol_' || tablename || '_(admin|mecanico|auditor|miembros)_(select|insert|update|delete)$'))
        FROM pg_policies WHERE schemaname = 'public') AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-24 las entidades expuestas tienen id_publico UUID NOT NULL con default y UNIQUE'
SELECT count(*) = 12
   AND bool_and(c.data_type = 'uuid' AND c.is_nullable = 'NO' AND c.column_default = 'gen_random_uuid()')
   AND bool_and(EXISTS (SELECT 1 FROM pg_constraint k
                        WHERE k.conname = 'uq_' || c.table_name || '_id_publico' AND k.contype = 'u')) AS ok
FROM   information_schema.columns c
WHERE  c.table_schema = 'public' AND c.column_name = 'id_publico' \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-25 objetos del esquema: 21 funciones fn_, 32 triggers, 49 politicas'
SELECT (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname LIKE 'fn\_%') = 21
   AND (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND NOT t.tgisinternal) = 32
   AND (SELECT count(*) FROM pg_policies WHERE schemaname = 'public') = 49 AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-26 servidor: PostgreSQL 16, UTC, READ COMMITTED, scram-sha-256, log_statement none'
SELECT current_setting('server_version_num')::int BETWEEN 160000 AND 169999
   AND current_setting('TimeZone') IN ('Etc/UTC', 'UTC')
   AND current_setting('default_transaction_isolation') = 'read committed'
   AND current_setting('password_encryption') = 'scram-sha-256'
   AND current_setting('log_statement') = 'none' AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-27 la clave de app_backend_user esta guardada como verificador SCRAM'
SELECT rolpassword LIKE 'SCRAM-SHA-256$%' AS ok FROM pg_authid WHERE rolname = 'app_backend_user' \gset
\ir incluir/afirmar.sql

-- Resguardo del hallazgo de la Fase 5 (V009): bajo RLS la igualdad de un enum no
-- puede ser condicion de busqueda de un indice (enum_eq no es leakproof). En
-- tablas con RLS, un enum solo puede aparecer en el PREDICADO de un indice
-- parcial, nunca como columna clave. No aplica a los indices UNICOS: alli el enum
-- define la regla de unicidad (uq_consentimiento_titular_activo), no una busqueda.
\set prueba 'ESQ-28 ningun indice de busqueda (no unico) de una tabla con RLS tiene un enum como columna clave (V009)'
SELECT count(*) = 0 AS ok
FROM   pg_index x
JOIN   pg_class t ON t.oid = x.indrelid
JOIN   pg_namespace n ON n.oid = t.relnamespace
JOIN   pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY (x.indkey::int2[])
JOIN   pg_type ty ON ty.oid = a.atttypid
WHERE  n.nspname = 'public' AND t.relrowsecurity AND ty.typtype = 'e' AND NOT x.indisunique
AND    a.attnum = ANY ((x.indkey::int2[])[0:x.indnkeyatts - 1]) \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-29 los estados abiertos de la sesion tienen indice parcial propio (pendiente y cotizado)'
SELECT count(*) = 2 AS ok
FROM   pg_indexes
WHERE  schemaname = 'public' AND tablename = 'sesion_diagnostico'
AND    indexname IN ('ix_sesion_diagnostico_pendiente', 'ix_sesion_diagnostico_cotizado')
AND    indexdef ~ 'WHERE \(estado = ''(pendiente|cotizado)''::tipo_estado_atencion\)' \gset
\ir incluir/afirmar.sql

-- Resguardo del hallazgo de la Fase 7 (V010): si pg_temp no se nombra en el
-- search_path de una funcion, se busca PRIMERO para tablas, y una tabla temporal
-- homonima suplanta a la real incluso dentro de una funcion SECURITY DEFINER.
\set prueba 'ESQ-30 las 21 funciones fn_ fijan search_path = pg_catalog, public, pg_temp (pg_temp explicito y al final) (V010)'
SELECT count(*) = 21
   AND bool_and(EXISTS (SELECT 1 FROM unnest(p.proconfig) x WHERE x = 'search_path=pg_catalog, public, pg_temp')) AS ok
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname LIKE 'fn\_%' \gset
\ir incluir/afirmar.sql

\set prueba 'ESQ-31 ningun rol de la aplicacion puede crear tablas temporales en la base (segunda barrera de V010)'
SELECT count(*) = 6 AND bool_and(NOT has_database_privilege(r.rolname, current_database(), 'TEMPORARY')) AS ok
FROM   pg_roles r
WHERE  r.rolname IN ('app_owner', 'app_funciones', 'app_backend_user', 'taller_admin', 'taller_mecanico', 'taller_auditor') \gset
\ir incluir/afirmar.sql

ROLLBACK;

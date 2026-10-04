-- Volcado del esquema real para docs/evidencia/esquema.txt.
-- Uso: bash db/scripts/evidencia_esquema.sh
\pset pager off
\set VERBOSITY terse

\echo '################################################################'
\echo '# 1. Version y parametros'
\echo '################################################################'
SELECT version();
SELECT name, setting FROM pg_settings
WHERE name IN ('shared_preload_libraries', 'password_encryption', 'log_statement',
               'default_transaction_isolation', 'row_security')
ORDER BY name;

\echo '################################################################'
\echo '# 2. Roles (\\du) y membresias'
\echo '################################################################'
\du
SELECT r.rolname AS rol, m.rolname AS miembro, am.inherit_option AS hereda, am.set_option AS puede_set_role,
       am.admin_option AS admin
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE r.rolname LIKE 'app\_%' OR r.rolname LIKE 'taller\_%'
ORDER BY 1, 2;

\echo '################################################################'
\echo '# 3. Tablas y vistas (\\dt, \\dv), tipos enumerados (\\dT+)'
\echo '################################################################'
\dt
\dv v_*
SELECT t.typname AS tipo, string_agg(e.enumlabel, ', ' ORDER BY e.enumsortorder) AS valores
FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid
WHERE t.typnamespace = 'public'::regnamespace
GROUP BY 1 ORDER BY 1;

\echo '################################################################'
\echo '# 4. Detalle de cada tabla (\\d+): columnas, restricciones, indices, triggers, politicas'
\echo '################################################################'
\d+ taller
\d+ taller_configuracion
\d+ usuario
\d+ usuario_credencial
\d+ titular
\d+ consentimiento_titular
\d+ solicitud_derecho_titular
\d+ marca_vehiculo
\d+ modelo_vehiculo
\d+ dtc_catalogo
\d+ componente_repuesto
\d+ dtc_componente
\d+ repuesto
\d+ compatibilidad_repuesto
\d+ v_dtc_repuesto
\d+ vehiculo
\d+ dispositivo_diagnostico
\d+ sesion_diagnostico
\d+ falla_sesion
\d+ cotizacion
\d+ cotizacion_detalle
\d+ auditoria_operacion

\echo '################################################################'
\echo '# 5. Funciones: propietario, SECURITY DEFINER y search_path'
\echo '################################################################'
SELECT p.proname AS funcion,
       pg_get_function_identity_arguments(p.oid) AS argumentos,
       pg_get_userbyid(p.proowner) AS propietario,
       CASE WHEN p.prosecdef THEN 'DEFINER' ELSE 'invoker' END AS seguridad,
       array_to_string(p.proconfig, '; ') AS configuracion
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE 'fn\_%'
ORDER BY p.prosecdef DESC, p.proname;

\echo '-- Funciones SECURITY DEFINER sin search_path fijo (debe ser 0)'
SELECT count(*) AS definidoras_sin_search_path
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE 'fn\_%' AND p.prosecdef
AND NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%');

\echo '################################################################'
\echo '# 6. Privilegios de ejecucion sobre funciones'
\echo '################################################################'
SELECT routine_name AS funcion, string_agg(grantee, ', ' ORDER BY grantee) AS con_execute
FROM information_schema.role_routine_grants
WHERE routine_schema = 'public' AND routine_name LIKE 'fn\_%'
GROUP BY 1 ORDER BY 1;

\echo '################################################################'
\echo '# 7. Privilegios de TABLA (information_schema.role_table_grants)'
\echo '################################################################'
SELECT table_name AS tabla, grantee AS rol, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privilegios
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('taller_admin', 'taller_mecanico', 'taller_auditor', 'app_backend_user', 'app_funciones', 'PUBLIC')
GROUP BY 1, 2 ORDER BY 1, 2;

\echo '-- Privilegios de tabla de app_backend_user y PUBLIC (debe ser 0)'
SELECT count(*) AS privilegios_de_tabla
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND grantee IN ('app_backend_user', 'PUBLIC')
  AND table_name NOT LIKE 'pg\_stat\_statements%';

\echo '-- Privilegios DELETE y TRUNCATE otorgados a roles de taller'
SELECT table_name AS tabla, grantee AS rol, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND privilege_type IN ('DELETE', 'TRUNCATE')
  AND grantee IN ('taller_admin', 'taller_mecanico', 'taller_auditor', 'app_backend_user', 'app_funciones')
ORDER BY 1, 2;

\echo '################################################################'
\echo '# 8. Privilegios por COLUMNA (solo los que no cubre un privilegio de tabla)'
\echo '################################################################'
SELECT c.table_name AS tabla, c.grantee AS rol, c.privilege_type AS privilegio,
       string_agg(c.column_name, ', ' ORDER BY col.ordinal_position) AS columnas
FROM information_schema.column_privileges c
JOIN information_schema.columns col
  ON col.table_schema = c.table_schema AND col.table_name = c.table_name AND col.column_name = c.column_name
WHERE c.table_schema = 'public'
  AND c.grantee IN ('taller_admin', 'taller_mecanico', 'taller_auditor')
  AND NOT EXISTS (
        SELECT 1 FROM information_schema.role_table_grants t
        WHERE t.table_schema = c.table_schema AND t.table_name = c.table_name
          AND t.grantee = c.grantee AND t.privilege_type = c.privilege_type)
GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

\echo '################################################################'
\echo '# 9. RLS: estado por tabla y politicas (pg_policies)'
\echo '################################################################'
SELECT c.relname AS tabla, c.relrowsecurity AS rls, c.relforcerowsecurity AS force,
       (SELECT count(*) FROM pg_policy p WHERE p.polrelid = c.oid) AS politicas
FROM pg_class c
WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
ORDER BY c.relrowsecurity DESC, c.relname;

SELECT tablename AS tabla, policyname AS politica, cmd AS operacion, array_to_string(roles, ', ') AS roles
FROM pg_policies WHERE schemaname = 'public'
ORDER BY 1, 2;

\x on
SELECT tablename AS tabla, policyname AS politica, cmd AS operacion, array_to_string(roles, ', ') AS roles,
       qual AS using, with_check
FROM pg_policies WHERE schemaname = 'public'
ORDER BY 1, 2;
\x off

\echo '################################################################'
\echo '# 10. Indices'
\echo '################################################################'
SELECT tablename AS tabla, indexname AS indice, indexdef AS definicion
FROM pg_indexes WHERE schemaname = 'public'
ORDER BY 1, 2;

\echo '################################################################'
\echo '# 11. Triggers'
\echo '################################################################'
SELECT c.relname AS tabla, t.tgname AS trigger, pg_get_triggerdef(t.oid) AS definicion
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
WHERE NOT t.tgisinternal AND c.relnamespace = 'public'::regnamespace
ORDER BY 1, 2;

\echo '################################################################'
\echo '# 12. Claves foraneas y su regla de borrado'
\echo '################################################################'
SELECT conrelid::regclass AS tabla, conname AS restriccion, confrelid::regclass AS referencia,
       CASE confdeltype WHEN 'r' THEN 'RESTRICT' WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL'
                        WHEN 'a' THEN 'NO ACTION' WHEN 'd' THEN 'SET DEFAULT' END AS on_delete,
       CASE confmatchtype WHEN 's' THEN 'SIMPLE' WHEN 'f' THEN 'FULL' WHEN 'p' THEN 'PARTIAL' END AS match,
       array_length(conkey, 1) AS columnas
FROM pg_constraint
WHERE contype = 'f' AND connamespace = 'public'::regnamespace
ORDER BY 1::text, 2;

\echo '################################################################'
\echo '# 13. Comprobaciones de calidad (todas deben dar 0)'
\echo '################################################################'
SELECT
  (SELECT count(*) FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'v') AND c.relname NOT LIKE 'pg\_%'
      AND a.attnum > 0 AND NOT a.attisdropped AND col_description(a.attrelid, a.attnum) IS NULL) AS columnas_sin_comentario,
  (SELECT count(*) FROM pg_class c
    WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'v') AND c.relname NOT LIKE 'pg\_%'
      AND obj_description(c.oid) IS NULL) AS tablas_sin_comentario,
  (SELECT count(*) FROM pg_class c
    WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'v', 'i', 'S') AND c.relname NOT LIKE 'pg\_%'
      AND pg_get_userbyid(c.relowner) <> 'app_owner') AS objetos_con_otro_propietario,
  (SELECT count(*) FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE c.relnamespace = 'public'::regnamespace AND pg_get_expr(d.adbin, d.adrelid) LIKE 'nextval(%') AS columnas_serial,
  (SELECT count(*) FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
      AND a.atttypid IN ('timestamp'::regtype, 'time'::regtype)) AS columnas_sin_zona_horaria,
  (SELECT count(*) FROM pg_class c
    WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
      AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'taller_id' AND NOT a.attisdropped)
      AND NOT (c.relrowsecurity AND c.relforcerowsecurity)) AS tablas_con_taller_id_sin_rls_forzado;

-- =============================================================================
-- Dictamen de cierre (Fase 7): comprobaciones de catalogo y experimentos.
-- No es parte de la suite: documenta, ejecutandolo, cada hallazgo que cita
-- docs/dictamen.md. Corre sobre las semillas y termina en ROLLBACK.
-- Los errores marcados "se espera error" son el resultado correcto.
-- Uso: bash db/scripts/psql.sh -f /db/tests/humo/fase7_dictamen.sql
-- =============================================================================
\ir ../incluir/inicio.sql
\pset null '(null)'

\echo '######## A. Salud del catalogo (solo lectura) ########'

\echo
\echo '## A1. Claves foraneas sin un indice completo que empiece por la columna que identifica al padre'
\echo '##     (la columna distinta de taller_id; taller_id solo si la FK apunta a taller)'
SELECT f.tabla, f.fk, f.columna, f.padre,
       coalesce((SELECT string_agg(x.indexrelid::regclass::text, ', ' ORDER BY x.indexrelid::regclass::text)
                 FROM   pg_index x
                 WHERE  x.indrelid = f.conrelid AND x.indpred IS NOT NULL
                 AND    f.attnum = ANY ((x.indkey::int2[])[0:1])), '-') AS indice_parcial_que_ayuda
FROM  (SELECT c.conrelid, c.conrelid::regclass AS tabla, c.conname AS fk, c.confrelid::regclass AS padre,
              a.attnum, a.attname AS columna, cardinality(c.conkey) > 1 AS compuesta
       FROM   pg_constraint c
       JOIN   pg_namespace n ON n.oid = c.connamespace
       JOIN   pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
       WHERE  n.nspname = 'public' AND c.contype = 'f'
       AND    (a.attname <> 'taller_id' OR cardinality(c.conkey) = 1)) f
WHERE  NOT EXISTS (
         SELECT 1 FROM pg_index x
         WHERE  x.indrelid = f.conrelid AND x.indpred IS NULL
         AND    ((x.indkey::int2[])[0] = f.attnum
                 -- (taller_id, columna) solo sirve si la FK tambien trae taller_id
                 OR (f.compuesta AND (x.indkey::int2[])[1] = f.attnum
                     AND (SELECT t.attname FROM pg_attribute t
                          WHERE t.attrelid = f.conrelid AND t.attnum = (x.indkey::int2[])[0]) = 'taller_id')))
ORDER  BY 1, 2;

\echo '## A2. Indices con la misma tabla y las mismas columnas clave (duplicados exactos)'
SELECT x.indrelid::regclass AS tabla, array_agg(x.indexrelid::regclass ORDER BY x.indexrelid::regclass::text) AS indices
FROM   pg_index x
JOIN   pg_class t ON t.oid = x.indrelid
JOIN   pg_namespace n ON n.oid = t.relnamespace
WHERE  n.nspname = 'public'
GROUP  BY x.indrelid, x.indkey::text, coalesce(pg_get_expr(x.indpred, x.indrelid), '')
HAVING count(*) > 1;

\echo '## A3. Objetos invalidos o a medio validar; tablas sin clave primaria'
SELECT (SELECT count(*) FROM pg_index x JOIN pg_class t ON t.oid = x.indrelid JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'public' AND (NOT x.indisvalid OR NOT x.indisready)) AS indices_invalidos,
       (SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'public' AND NOT c.convalidated) AS restricciones_sin_validar,
       (SELECT count(*) FROM pg_class t JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'public' AND t.relkind = 'r'
        AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = t.oid AND c.contype = 'p')) AS tablas_sin_pk,
       (SELECT count(*) FROM pg_trigger g JOIN pg_class t ON t.oid = g.tgrelid JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'public' AND NOT g.tgisinternal AND g.tgenabled <> 'O') AS triggers_no_habilitados;

\echo '## A4. search_path de las funciones: cuantas nombran pg_temp de forma explicita'
SELECT count(*) AS funciones_fn,
       count(*) FILTER (WHERE p.prosecdef) AS definidoras,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM unnest(p.proconfig) x WHERE x LIKE 'search_path=%pg_temp%')) AS con_pg_temp_explicito,
       min((SELECT x FROM unnest(p.proconfig) x WHERE x LIKE 'search_path=%')) AS search_path_minimo,
       max((SELECT x FROM unnest(p.proconfig) x WHERE x LIKE 'search_path=%')) AS search_path_maximo
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname LIKE 'fn\_%';

\echo '## A5. Privilegio TEMPORARY sobre la base (de el depende que A4 no sea explotable)'
SELECT r.rolname AS rol, has_database_privilege(r.rolname, current_database(), 'TEMPORARY') AS puede_crear_temporales
FROM   pg_roles r
WHERE  r.rolname IN ('app_backend_user', 'taller_admin', 'taller_mecanico', 'taller_auditor', 'app_owner', 'app_funciones')
ORDER  BY 1;

\echo '## A6. Limites del rol de conexion: tiempos de espera y numero de conexiones'
SELECT r.rolname AS rol, r.rolconnlimit AS limite_conexiones, coalesce(r.rolconfig::text, '(sin configuracion propia)') AS configuracion_del_rol
FROM   pg_roles r
WHERE  r.rolname = 'app_backend_user';
SELECT name AS parametro, setting AS valor, coalesce(unit, '') AS unidad
FROM   pg_settings
WHERE  name IN ('statement_timeout', 'lock_timeout', 'idle_in_transaction_session_timeout', 'max_connections')
ORDER  BY 1;

\echo '## A7. Columnas que un rol de taller puede fijar al insertar y que la base no acota (fechas)'
SELECT grantee AS rol, table_name AS tabla, column_name AS columna
FROM   information_schema.column_privileges
WHERE  table_schema = 'public' AND privilege_type = 'INSERT'
AND    grantee IN ('taller_admin', 'taller_mecanico')
AND    column_name IN ('iniciada_en', 'otorgado_en', 'recibida_en')
ORDER  BY 2, 1;

\echo
\echo '######## B. Experimentos con el rol real del backend ########'

-- Datos de trabajo, leidos como plataforma.
\ir ../incluir/rol_plataforma.sql
SELECT s.id AS ses_completada, s.id_publico AS ses_completada_pub, s.kilometraje AS km_original
FROM   sesion_diagnostico s
WHERE  s.taller_id = :taller_1 AND s.estado = 'completado'
ORDER  BY s.id LIMIT 1 \gset
SELECT d.id AS dtc_libre
FROM   dtc_catalogo d
WHERE  NOT EXISTS (SELECT 1 FROM falla_sesion f WHERE f.sesion_id = :ses_completada AND f.dtc_id = d.id)
ORDER  BY d.id LIMIT 1 \gset
SELECT count(*) AS fallas_antes FROM falla_sesion WHERE sesion_id = :ses_completada \gset

\echo
\echo '## B1. Una sesion COMPLETADA sigue admitiendo cambios en su diagnostico (mecanico)'
\ir ../incluir/rol_mecanico_1.sql
\echo '-- B1a. cambiar el kilometraje de la sesion completada'
UPDATE sesion_diagnostico SET kilometraje = kilometraje + 1 WHERE id = :ses_completada;
\echo sqlstate :SQLSTATE , filas :ROW_COUNT
\echo '-- B1b. agregar una falla (DTC) nueva a la sesion completada'
INSERT INTO falla_sesion (sesion_id, dtc_id, taller_id, severidad) VALUES (:ses_completada, :dtc_libre, :taller_1, 'critica');
\echo sqlstate :SQLSTATE , filas :ROW_COUNT
\echo '-- B1c. cambiar la severidad de las fallas de la sesion completada'
UPDATE falla_sesion SET severidad = 'baja' WHERE sesion_id = :ses_completada;
\echo sqlstate :SQLSTATE , filas :ROW_COUNT
\ir ../incluir/rol_plataforma.sql
SELECT s.estado, s.kilometraje - :km_original AS km_agregados,
       (SELECT count(*) FROM falla_sesion f WHERE f.sesion_id = s.id) - :fallas_antes AS fallas_agregadas,
       (SELECT count(*) FROM auditoria_operacion a WHERE a.request_id = 'prueba' AND a.tabla IN ('sesion_diagnostico', 'falla_sesion')
        AND a.ocurrido_en >= now()) AS cambios_auditados
FROM   sesion_diagnostico s WHERE s.id = :ses_completada;

\echo
\echo '## B2. El mecanico puede fijar la fecha de inicio de una sesion (de ella depende la retencion)'
SELECT v.id AS veh_1 FROM vehiculo v
WHERE  v.taller_id = :taller_1 AND v.anonimizado_en IS NULL
AND    (v.titular_id IS NULL OR EXISTS (SELECT 1 FROM titular t WHERE t.id = v.titular_id AND t.estado_tratamiento = 'activo'))
ORDER  BY v.id LIMIT 1 \gset
\ir ../incluir/rol_mecanico_1.sql
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, metodo_ingreso, kilometraje, iniciada_en)
VALUES (:taller_1, :veh_1, :mec_1, 'manual', 1000, timestamptz '2099-01-01 00:00+00')
RETURNING estado, iniciada_en > now() AS inicio_en_el_futuro;
\echo sqlstate :SQLSTATE

\echo
\echo '## B3. El administrador decide el plazo de retencion y puede anularlo antes de suprimir'
\ir ../incluir/rol_plataforma.sql
SELECT t.id AS tit_reciente
FROM   titular t
WHERE  t.taller_id = :taller_1 AND t.estado_tratamiento = 'activo'
AND    EXISTS (SELECT 1 FROM vehiculo v JOIN sesion_diagnostico s ON s.vehiculo_id = v.id
               WHERE v.titular_id = t.id AND s.estado <> 'cancelado' AND s.iniciada_en < now()
               AND   s.iniciada_en > now() - interval '5 years')
AND    NOT EXISTS (SELECT 1 FROM vehiculo v JOIN sesion_diagnostico s ON s.vehiculo_id = v.id
                   WHERE v.titular_id = t.id AND s.iniciada_en > now())
ORDER  BY t.id LIMIT 1 \gset
\ir ../incluir/rol_admin_1.sql
SAVEPOINT b3;
\echo '-- B3a. con la retencion configurada (6 anios): queda bloqueado'
SELECT fn_solicitar_supresion_titular(:tit_reciente) AS resultado_con_retencion;
ROLLBACK TO SAVEPOINT b3;
\echo '-- B3b. el mismo administrador pone retencion_anios = 0 y repite: anonimizacion inmediata'
UPDATE taller_configuracion SET retencion_anios = 0;
SELECT fn_solicitar_supresion_titular(:tit_reciente) AS resultado_con_retencion_cero;
ROLLBACK TO SAVEPOINT b3;

\echo
\echo '## B4. Un taller puede quedarse sin administrador activo'
\ir ../incluir/rol_admin_1.sql
SAVEPOINT b4;
UPDATE usuario SET activo = false WHERE rol = 'admin';
\echo sqlstate :SQLSTATE , filas :ROW_COUNT
SELECT count(*) FILTER (WHERE rol = 'admin' AND activo) AS administradores_activos FROM usuario;
ROLLBACK TO SAVEPOINT b4;

\echo
\echo '## B5. Sombra de pg_temp en las funciones definidoras'
\echo '-- B5a. estado real: el rol del backend no puede crear tablas temporales (se espera error 42501)'
\ir ../incluir/rol_mecanico_1.sql
CREATE TEMP TABLE auditoria_operacion (x int);
\echo sqlstate :SQLSTATE
\echo '-- B5b. hipotesis: alguien otorga TEMPORARY a los roles de taller (hoy solo lo hace 09_consultas.sql, en su transaccion)'
\ir ../incluir/rol_plataforma.sql
SAVEPOINT b5;
GRANT TEMPORARY ON DATABASE :"DBNAME" TO taller_mecanico;
SELECT count(*) AS auditoria_real_antes FROM public.auditoria_operacion \gset
\ir ../incluir/rol_mecanico_1.sql
CREATE TEMP TABLE auditoria_operacion (
  taller_id bigint, usuario_id bigint, rol text, operacion text, tabla text, registro_id bigint,
  datos_anteriores jsonb, datos_nuevos jsonb, ip_origen inet, resultado text, request_id text);
GRANT INSERT ON pg_temp.auditoria_operacion TO PUBLIC;
\echo '-- escritura auditada del mecanico (kilometraje de una sesion)'
UPDATE sesion_diagnostico SET kilometraje = kilometraje + 1 WHERE id = :ses_completada;
\echo sqlstate :SQLSTATE , filas :ROW_COUNT
SELECT count(*) AS registros_desviados_a_la_tabla_temporal FROM pg_temp.auditoria_operacion;
\ir ../incluir/rol_plataforma.sql
SELECT count(*) - :auditoria_real_antes AS registros_nuevos_en_la_auditoria_real FROM public.auditoria_operacion;
ROLLBACK TO SAVEPOINT b5;

\echo
\echo '######## C. La base queda como estaba ########'
ROLLBACK;
SELECT (SELECT kilometraje FROM sesion_diagnostico WHERE id = :ses_completada) = :km_original AS kilometraje_intacto,
       (SELECT count(*) FROM falla_sesion WHERE sesion_id = :ses_completada) = :fallas_antes AS fallas_intactas,
       has_database_privilege('taller_mecanico', current_database(), 'TEMPORARY') AS mecanico_con_temporary;

-- =============================================================================
-- 07 - Auditoria: solo insercion, contexto registrado y datos personales fuera
--      (RN-70, RN-71).
-- =============================================================================
\ir incluir/inicio.sql
\echo '### 07 Auditoria'
\o /dev/null

-- ----------------------------------------------------------- inmutabilidad
\ir incluir/rol_plataforma.sql
\set prueba 'RN-70 UPDATE de la auditoria como superusuario'
\set esperado RE005
UPDATE auditoria_operacion SET resultado = 'fallo';
\ir incluir/error.sql
\set prueba 'RN-70 DELETE de la auditoria como superusuario'
\set esperado RE005
DELETE FROM auditoria_operacion;
\ir incluir/error.sql
\set prueba 'RN-70 TRUNCATE de la auditoria como superusuario'
\set esperado RE005
TRUNCATE auditoria_operacion;
\ir incluir/error.sql
\set prueba 'RN-70 TRUNCATE de la auditoria como su propietario (app_owner)'
SET LOCAL ROLE app_owner;
\set esperado RE005
TRUNCATE auditoria_operacion;
\ir incluir/error.sql
\ir incluir/rol_plataforma.sql

\set prueba 'La auditoria no tiene claves foraneas (no puede bloquear ni ser arrastrada por un borrado)'
SELECT count(*) = 0 AS ok FROM pg_constraint c
WHERE  c.contype = 'f' AND (c.conrelid = 'auditoria_operacion'::regclass OR c.confrelid = 'auditoria_operacion'::regclass) \gset
\ir incluir/afirmar.sql

\set prueba 'Las 13 tablas auditadas tienen trigger de captura; usuario_credencial y auditoria no'
SELECT count(*) = 13
   AND count(*) FILTER (WHERE c.relname IN ('usuario_credencial', 'auditoria_operacion')) = 0 AS ok
FROM   pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
WHERE  NOT t.tgisinternal AND t.tgname LIKE 'trg\_%\_auditar' \gset
\ir incluir/afirmar.sql

-- ----------------------------------------------- contexto de una operacion
\ir incluir/rol_mecanico_1.sql
EXECUTE ctx(:'taller_1', :'mec_1', '203.0.113.7', 'req-auditoria-1') \gset ctx_
EXECUTE tx_crear_titular('Persona Auditada', '+56912345678', 'persona@correo.example', decode(repeat('ab', 32), 'hex')) \gset t_
UPDATE titular SET telefono = '+56987654321', nombre = 'Persona Auditada Dos' WHERE id_publico = :'t_id_publico';
SELECT mo.id_publico AS modelo FROM modelo_vehiculo mo WHERE mo.nombre = 'Yaris' \gset
EXECUTE tx_crear_vehiculo(:'t_id_publico', :'modelo', 2019, '1.5 Bencina', 'JTDBR32E720999999', 'WXYZ21') \gset v_
EXECUTE tx_crear_sesion(:'v_id_publico', NULL, 5000, '[{"codigo": "P0301", "freeze_frame": {"vin": "JTDBR32E720999999", "rpm": 800}}]') \gset s_
EXECUTE tx_crear_cotizacion(:'s_id_publico', 'dddddddd-0000-4000-8000-000000000001') \gset c_
SELECT r.id_publico AS rep FROM repuesto r WHERE r.codigo_fabricante = 'ILKAR7B11' \gset
EXECUTE tx_guardar_linea(:'c_id_publico', :'rep', 4);
EXECUTE tx_quitar_linea(:'c_id_publico', :'rep');

\ir incluir/rol_plataforma.sql
SELECT t.id AS tit_id FROM titular t WHERE t.id_publico = :'t_id_publico' \gset
SELECT v.id AS veh_id FROM vehiculo v WHERE v.id_publico = :'v_id_publico' \gset
SELECT s.id AS ses_id FROM sesion_diagnostico s WHERE s.id_publico = :'s_id_publico' \gset

\set prueba 'INSERT auditado con taller, usuario, rol real, IP, request_id y resultado'
SELECT count(*) = 1 AND bool_and(a.taller_id = :taller_1 AND a.usuario_id = :mec_1 AND a.rol = 'taller_mecanico'
       AND a.ip_origen = '203.0.113.7' AND a.request_id = 'req-auditoria-1' AND a.resultado = 'exito'
       AND a.datos_anteriores IS NULL AND a.datos_nuevos IS NOT NULL) AS ok
FROM   auditoria_operacion a WHERE a.tabla = 'titular' AND a.registro_id = :tit_id AND a.operacion = 'INSERT' \gset
\ir incluir/afirmar.sql

\set prueba 'T-7 el rol registrado es el del grupo, no app_funciones (propietario de la funcion definidora)'
SELECT count(*) > 0 AND bool_and(a.rol <> 'app_funciones') AS ok FROM auditoria_operacion a \gset
\ir incluir/afirmar.sql

\set prueba 'RN-71 titular: sin nombre, telefono, email ni HMAC; con id, estado y fechas'
SELECT count(*) = 2
   AND bool_and(NOT (COALESCE(a.datos_nuevos, '{}') || COALESCE(a.datos_anteriores, '{}')) ?| ARRAY['nombre', 'telefono', 'email', 'identificador_hmac'])
   AND bool_and(a.datos_nuevos ?& ARRAY['id', 'taller_id', 'estado_tratamiento', 'creado_en']) AS ok
FROM   auditoria_operacion a WHERE a.tabla = 'titular' AND a.registro_id = :tit_id \gset
\ir incluir/afirmar.sql

\set prueba 'UPDATE auditado con datos anteriores y nuevos'
SELECT count(*) = 1 AND bool_and(a.datos_anteriores IS NOT NULL AND a.datos_nuevos IS NOT NULL
       AND a.datos_anteriores ->> 'actualizado_en' IS NOT NULL) AS ok
FROM   auditoria_operacion a WHERE a.tabla = 'titular' AND a.registro_id = :tit_id AND a.operacion = 'UPDATE' \gset
\ir incluir/afirmar.sql

\set prueba 'RN-71 vehiculo: sin patente ni VIN; con anio, motor y modelo'
SELECT count(*) = 1 AND bool_and(NOT a.datos_nuevos ?| ARRAY['patente', 'vin'])
       AND bool_and(a.datos_nuevos ?& ARRAY['anio', 'motor', 'modelo_vehiculo_id', 'titular_id']) AS ok
FROM   auditoria_operacion a WHERE a.tabla = 'vehiculo' AND a.registro_id = :veh_id \gset
\ir incluir/afirmar.sql

\set prueba 'RN-71 falla_sesion: sin freeze_frame; registro_id NULL y la clave completa en datos_nuevos (T-20)'
SELECT count(*) = 1 AND bool_and(NOT a.datos_nuevos ? 'freeze_frame' AND a.registro_id IS NULL
       AND (a.datos_nuevos ->> 'sesion_id')::bigint = :ses_id AND a.datos_nuevos ? 'dtc_id') AS ok
FROM   auditoria_operacion a WHERE a.tabla = 'falla_sesion' AND (a.datos_nuevos ->> 'sesion_id')::bigint = :ses_id \gset
\ir incluir/afirmar.sql

\set prueba 'DELETE auditado con datos anteriores y sin datos nuevos'
SELECT count(*) = 1 AND bool_and(a.datos_anteriores IS NOT NULL AND a.datos_nuevos IS NULL
       AND (a.datos_anteriores ->> 'cantidad')::int = 4) AS ok
FROM   auditoria_operacion a WHERE a.tabla = 'cotizacion_detalle' AND a.operacion = 'DELETE' AND a.ocurrido_en >= now() \gset
\ir incluir/afirmar.sql

\set prueba 'RN-71 el valor personal enviado no aparece en ningun registro de auditoria'
SELECT count(*) = 0 AS ok
FROM   auditoria_operacion a
WHERE  (COALESCE(a.datos_anteriores, '{}')::text || COALESCE(a.datos_nuevos, '{}')::text)
       ~ '(Persona Auditada|56912345678|56987654321|persona@correo|WXYZ21|JTDBR32E720999999|abababab)' \gset
\ir incluir/afirmar.sql

\ir incluir/rol_admin_1.sql
EXECUTE tx_crear_usuario('auditado@losaromos.example', 'Usuario Auditado', 'auditor') \gset u_
\ir incluir/rol_plataforma.sql
\set prueba 'RN-71 usuario: sin email ni nombre; con rol y activo'
SELECT count(*) = 1 AND bool_and(NOT a.datos_nuevos ?| ARRAY['email', 'nombre'] AND a.datos_nuevos ?& ARRAY['rol', 'activo']
       AND a.rol = 'taller_admin' AND a.usuario_id = :admin_1) AS ok
FROM   auditoria_operacion a
WHERE  a.tabla = 'usuario' AND a.registro_id = (SELECT u.id FROM usuario u WHERE u.id_publico = :'u_id_publico') \gset
\ir incluir/afirmar.sql

\set prueba 'RN-71 en TODA la bitacora (semillas incluidas) no hay ninguna columna enmascarada'
SELECT count(*) = 0 AS ok
FROM   auditoria_operacion a,
       LATERAL (SELECT COALESCE(a.datos_nuevos, '{}') || COALESCE(a.datos_anteriores, '{}') AS d) x
WHERE  (a.tabla = 'titular'      AND x.d ?| ARRAY['nombre', 'telefono', 'email', 'identificador_hmac'])
OR     (a.tabla = 'vehiculo'     AND x.d ?| ARRAY['patente', 'vin'])
OR     (a.tabla = 'usuario'      AND x.d ?| ARRAY['email', 'nombre'])
OR     (a.tabla = 'falla_sesion' AND x.d ?  'freeze_frame')
OR     x.d ?| ARRAY['hash_contrasena', 'contrasena'] \gset
\ir incluir/afirmar.sql

-- -------------------------------------------------- operaciones fallidas
\ir incluir/rol_plataforma.sql
SELECT count(*) AS antes FROM auditoria_operacion \gset
\ir incluir/rol_mecanico_1.sql
\set prueba 'Una operacion rechazada (RE001) se revierte entera'
\set esperado RE001
EXECUTE tx_cambiar_estado(:'s_id_publico', 'completado', NULL);
\ir incluir/error.sql
\ir incluir/rol_plataforma.sql
\set prueba 'La operacion rechazada no deja registro: la auditoria comparte la transaccion de la operacion'
SELECT count(*) = :antes AS ok FROM auditoria_operacion \gset
\ir incluir/afirmar.sql

-- ------------------------------------------------------- contexto anomalo
\ir incluir/rol_mecanico_1.sql
EXECUTE ctx(:'taller_1', :'mec_1', 'esto-no-es-una-ip', 'req-auditoria-2') \gset ctx_
\set prueba 'Una IP de origen mal formada no impide la operacion'
UPDATE sesion_diagnostico SET kilometraje = 5001 WHERE id_publico = :'s_id_publico';
\set esperado 1
\ir incluir/filas.sql
\ir incluir/rol_plataforma.sql
\set prueba 'y queda auditada con ip_origen NULL'
SELECT count(*) = 1 AND bool_and(a.ip_origen IS NULL AND a.usuario_id = :mec_1) AS ok
FROM   auditoria_operacion a WHERE a.request_id = 'req-auditoria-2' \gset
\ir incluir/afirmar.sql

\set prueba 'ocurrido_en usa clock_timestamp: avanza dentro de la transaccion y sigue el orden de los ids'
SELECT max(a.ocurrido_en) > now()
   AND bool_and(a.ocurrido_en >= a.anterior) AS ok
FROM  (SELECT ocurrido_en, lag(ocurrido_en) OVER (ORDER BY id) AS anterior
       FROM auditoria_operacion WHERE ocurrido_en >= now()) a
WHERE  a.anterior IS NOT NULL \gset
\ir incluir/afirmar.sql

-- --------------------------------------------- cambios de la plataforma
UPDATE repuesto SET precio_referencia = precio_referencia + 1 WHERE codigo_fabricante = 'ILKAR7B11';
\set prueba 'Un cambio de precio maestro queda auditado con el rol de sesion y sin taller'
SELECT count(*) = 1 AND bool_and(a.rol = session_user AND a.taller_id IS NULL AND a.usuario_id IS NULL
       AND (a.datos_nuevos ->> 'precio_referencia')::bigint = (a.datos_anteriores ->> 'precio_referencia')::bigint + 1) AS ok
FROM   auditoria_operacion a WHERE a.tabla = 'repuesto' AND a.operacion = 'UPDATE' AND a.ocurrido_en >= now() \gset
\ir incluir/afirmar.sql

\ir incluir/rol_admin_1.sql
\set prueba 'Ese registro sin taller no es visible para el administrador de ningun taller'
SELECT count(*) = 0 AS ok FROM auditoria_operacion a WHERE a.tabla = 'repuesto' \gset
\ir incluir/afirmar.sql

\set prueba 'El administrador lee en su bitacora lo que hizo el mecanico de su taller'
SELECT count(*) >= 8 AS ok FROM auditoria_operacion a WHERE a.request_id = 'req-auditoria-1' AND a.usuario_id = :mec_1 \gset
\ir incluir/afirmar.sql

-- ------------------------------------- sombra de pg_temp (Fase 7, V010)
-- Aunque un rol de taller llegara a tener TEMPORARY, una tabla temporal llamada
-- auditoria_operacion no puede desviar los registros: las funciones nombran
-- pg_temp al final de su search_path. Sin V010 el registro iba a la temporal
-- (docs/evidencia/fase7_antes.txt, B5). El GRANT lo revierte el ROLLBACK.
\ir incluir/rol_plataforma.sql
GRANT TEMPORARY ON DATABASE :"DBNAME" TO taller_mecanico;
\ir incluir/rol_mecanico_1.sql
EXECUTE ctx(:'taller_1', :'mec_1', '203.0.113.7', 'req-auditoria-sombra') \gset ctx_
CREATE TEMP TABLE auditoria_operacion (
  taller_id bigint, usuario_id bigint, rol text, operacion text, tabla text, registro_id bigint,
  datos_anteriores jsonb, datos_nuevos jsonb, ip_origen inet, resultado text, request_id text);
GRANT INSERT ON pg_temp.auditoria_operacion TO PUBLIC;
UPDATE sesion_diagnostico SET kilometraje = kilometraje + 1 WHERE id = :ses_id;
\set prueba 'V010 una tabla temporal homonima no recibe el registro de auditoria'
SELECT count(*) = 0 AS ok FROM pg_temp.auditoria_operacion \gset
\ir incluir/afirmar.sql
\ir incluir/rol_plataforma.sql
\set prueba 'V010 la escritura queda en la auditoria real aunque exista la tabla temporal'
SELECT count(*) = 1 AND bool_and(a.tabla = 'sesion_diagnostico' AND a.operacion = 'UPDATE' AND a.usuario_id = :mec_1) AS ok
FROM   public.auditoria_operacion a WHERE a.request_id = 'req-auditoria-sombra' \gset
\ir incluir/afirmar.sql

ROLLBACK;

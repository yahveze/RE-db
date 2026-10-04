-- =============================================================================
-- Prueba de humo de la Fase 2 (no es la suite formal de la Fase 4).
-- Recorre el flujo completo con el rol real del backend y termina en ROLLBACK.
-- Los errores marcados "se espera error" son el resultado correcto.
-- Uso: bash db/scripts/psql.sh -f /db/tests/humo/fase2_humo.sql
-- =============================================================================
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
\set VERBOSITY terse
\pset pager off

BEGIN;

\echo '=== 0. Datos minimos (superusuario) ==='
INSERT INTO taller (nombre) VALUES ('Taller A') RETURNING id AS taller_a \gset
INSERT INTO taller (nombre) VALUES ('Taller B') RETURNING id AS taller_b \gset
INSERT INTO taller_configuracion (taller_id, margen_pct, retencion_anios) VALUES (:taller_a, 30, 6), (:taller_b, 50, 6);
INSERT INTO usuario (taller_id, email, nombre, rol) VALUES (:taller_a, 'admin@a.test', 'Admin A', 'admin') RETURNING id AS admin_a \gset
INSERT INTO usuario (taller_id, email, nombre, rol) VALUES (:taller_a, 'mec@a.test', 'Mecanico A', 'mecanico') RETURNING id AS mec_a \gset
INSERT INTO usuario (taller_id, email, nombre, rol) VALUES (:taller_a, 'aud@a.test', 'Auditor A', 'auditor') RETURNING id AS aud_a \gset
INSERT INTO usuario (taller_id, email, nombre, rol) VALUES (:taller_b, 'mec@b.test', 'Mecanico B', 'mecanico') RETURNING id AS mec_b \gset
INSERT INTO usuario_credencial (usuario_id, hash_contrasena)
SELECT id, crypt(:'clave_demo', gen_salt('bf', 10)) FROM usuario;
INSERT INTO marca_vehiculo (nombre) VALUES ('Toyota') RETURNING id AS marca \gset
INSERT INTO modelo_vehiculo (marca_vehiculo_id, nombre) VALUES (:marca, 'Hilux') RETURNING id AS modelo \gset
INSERT INTO dtc_catalogo (codigo, descripcion, severidad_sugerida) VALUES ('P0301', 'Falla de encendido cilindro 1', 'alta') RETURNING id AS dtc \gset
INSERT INTO componente_repuesto (nombre) VALUES ('Bujia') RETURNING id AS comp \gset
INSERT INTO dtc_componente VALUES (:dtc, :comp);
INSERT INTO repuesto (componente_id, perfil, marca, nombre, codigo_fabricante, durabilidad_estimada_km, riesgo, precio_referencia)
VALUES (:comp, 'genuino', 'Toyota', 'Bujia iridio genuina', '90919-01253', 100000, 'bajo', 18990) RETURNING id AS rep_gen \gset
INSERT INTO repuesto (componente_id, perfil, marca, nombre, codigo_fabricante, durabilidad_estimada_km, riesgo, precio_referencia)
VALUES (:comp, 'generico', 'Generica', 'Bujia cobre', 'GX-100', 30000, 'alto', 3990) RETURNING id AS rep_gx \gset
SELECT count(*) AS filas_v_dtc_repuesto FROM v_dtc_repuesto;

\echo
\echo '=== 1. Rol de conexion del backend: sin contexto no puede nada ==='
SET SESSION AUTHORIZATION app_backend_user;
SELECT current_user, session_user;
\echo '-- 1a. SELECT sin SET LOCAL ROLE (se espera error: permission denied)'
SELECT count(*) FROM sesion_diagnostico;
\echo '-- 1b. login correcto (antes de que exista contexto)'
SELECT autenticado, usuario_id = :mec_a AS es_mec_a, taller_id = :taller_a AS es_taller_a, rol, nombre
FROM fn_autenticar_usuario('MEC@a.test', :'clave_demo');
\echo '-- 1c. login con clave incorrecta y con email inexistente (autenticado = f, sin motivo)'
SELECT autenticado, usuario_id, rol FROM fn_autenticar_usuario('mec@a.test', 'incorrecta');
SELECT autenticado, usuario_id, rol FROM fn_autenticar_usuario('nadie@a.test', 'incorrecta');
\echo '-- 1d. acceso directo a credenciales (se espera error)'
SELECT * FROM usuario_credencial;

\echo
\echo '=== 2. Mecanico del taller A: flujo completo ==='
SET LOCAL ROLE taller_mecanico;
SELECT set_config('app.taller_id', :'taller_a', true) AS taller, set_config('app.usuario_id', :'mec_a', true) AS usuario,
       set_config('app.ip_origen', '10.0.0.7', true) AS ip, set_config('app.request_id', 'req-humo-1', true) AS request;
INSERT INTO titular (taller_id, nombre, telefono) VALUES (:taller_a, 'Juana Perez', '+56911111111') RETURNING id AS titular \gset
INSERT INTO vehiculo (taller_id, titular_id, modelo_vehiculo_id, anio, motor, patente)
VALUES (:taller_a, :titular, :modelo, 2021, '2.4 Diesel', 'BCDF12') RETURNING id AS vehiculo \gset
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, metodo_ingreso, kilometraje)
VALUES (:taller_a, :vehiculo, :mec_a, 'manual', 84500) RETURNING id AS sesion, estado, version \gset
\echo sesion creada: estado :estado version :version
INSERT INTO falla_sesion (sesion_id, dtc_id, taller_id, severidad, freeze_frame)
VALUES (:sesion, :dtc, :taller_a, 'critica', '{"rpm": 850}');

\echo '-- 2a. cotizado sin cotizacion (se espera error RE002)'
SELECT estado FROM fn_cambiar_estado_sesion(:sesion, 'cotizado');
\echo '-- 2b. transicion invalida pendiente -> completado (se espera error RE001)'
UPDATE sesion_diagnostico SET estado = 'completado' WHERE id = :sesion;

\echo '-- 2c. crear cotizacion (idempotente: dos llamadas, una sola fila)'
SELECT id AS cot, numero_revision, vigente, cerrada_en IS NULL AS abierta, total, moneda
FROM fn_crear_cotizacion(:sesion, '11111111-1111-1111-1111-111111111111') \gset
SELECT id = :cot AS misma_cotizacion FROM fn_crear_cotizacion(:sesion, '11111111-1111-1111-1111-111111111111');
SELECT count(*) AS cotizaciones FROM cotizacion WHERE sesion_id = :sesion;

\echo '-- 2d. detalle: el cliente solo envia repuesto y cantidad; el trigger pone el snapshot'
INSERT INTO cotizacion_detalle (cotizacion_id, repuesto_id, taller_id, cantidad) VALUES (:cot, :rep_gen, :taller_a, 4)
RETURNING nombre_snapshot, perfil_snapshot, precio_referencia_snapshot, margen_pct_snapshot, precio_unitario;
\echo '-- 2e. el mecanico intenta fijar el precio (se espera error: permission denied)'
INSERT INTO cotizacion_detalle (cotizacion_id, repuesto_id, taller_id, cantidad, precio_unitario) VALUES (:cot, :rep_gx, :taller_a, 1, 1);
\echo '-- 2f. cerrar: total = 4 x 24687 = 98748'
SELECT numero_revision, vigente, cerrada_en IS NOT NULL AS cerrada, total, version FROM fn_cerrar_cotizacion(:cot);
\echo '-- 2g. cotizacion cerrada: detalle inmutable (se esperan 3 errores RE003)'
INSERT INTO cotizacion_detalle (cotizacion_id, repuesto_id, taller_id, cantidad) VALUES (:cot, :rep_gx, :taller_a, 1);
UPDATE cotizacion_detalle SET cantidad = 99 WHERE cotizacion_id = :cot;
DELETE FROM cotizacion_detalle WHERE cotizacion_id = :cot;
\echo '-- 2h. reabrir la cotizacion cerrada (se espera error RE003)'
UPDATE cotizacion SET cerrada_en = NULL WHERE id = :cot;
\echo '-- 2i. pendiente -> cotizado -> completado'
SELECT estado, cotizada_en IS NOT NULL AS con_fecha, version FROM fn_cambiar_estado_sesion(:sesion, 'cotizado');
\echo '-- 2j. conflicto de version: se envia una version antigua (se espera error RE007)'
SELECT estado FROM fn_cambiar_estado_sesion(:sesion, 'completado', 1);
SELECT estado, completada_en IS NOT NULL AS con_fecha FROM fn_cambiar_estado_sesion(:sesion, 'completado');
\echo '-- 2k. estado terminal: no admite mas cambios ni cotizaciones (se esperan errores RE001 y RE004)'
SELECT estado FROM fn_cambiar_estado_sesion(:sesion, 'cancelado');
SELECT id FROM fn_crear_cotizacion(:sesion, '22222222-2222-2222-2222-222222222222');
\echo '-- 2l. el mecanico no modifica precios maestros ni lee la auditoria (se esperan 2 errores)'
UPDATE repuesto SET precio_referencia = 1 WHERE id = :rep_gen;
SELECT count(*) FROM auditoria_operacion;
RESET ROLE;

\echo
\echo '=== 3. Mecanico del taller B: no ve ni toca datos del taller A ==='
SET LOCAL ROLE taller_mecanico;
SELECT set_config('app.taller_id', :'taller_b', true) AS taller, set_config('app.usuario_id', :'mec_b', true) AS usuario;
SELECT (SELECT count(*) FROM sesion_diagnostico) AS sesiones, (SELECT count(*) FROM vehiculo) AS vehiculos,
       (SELECT count(*) FROM titular) AS titulares, (SELECT count(*) FROM cotizacion) AS cotizaciones,
       (SELECT count(*) FROM taller) AS talleres;
\echo '-- 3a. UPDATE sobre una sesion del taller A (0 filas)'
UPDATE sesion_diagnostico SET kilometraje = 1 WHERE id = :sesion;
\echo '-- 3b. INSERT con taller_id ajeno (se espera error: row-level security)'
INSERT INTO titular (taller_id, nombre) VALUES (:taller_a, 'Intruso');
\echo '-- 3c. FK cruzada: sesion del taller B sobre un vehiculo del taller A (se espera error de FK)'
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, metodo_ingreso, kilometraje)
VALUES (:taller_b, :vehiculo, :mec_b, 'manual', 10);
RESET ROLE;

\echo
\echo '=== 4. Auditor del taller A ==='
SET LOCAL ROLE taller_auditor;
SELECT set_config('app.taller_id', :'taller_a', true) AS taller, set_config('app.usuario_id', :'aud_a', true) AS usuario;
\echo '-- 4a. columnas de identidad del titular (se espera error: permission denied)'
SELECT nombre FROM titular;
\echo '-- 4b. columnas permitidas'
SELECT estado_tratamiento, anonimizado_en FROM titular;
\echo '-- 4c. escribir (se espera error)'
UPDATE sesion_diagnostico SET kilometraje = 1 WHERE id = :sesion;
\echo '-- 4d. auditoria del taller: operaciones, rol registrado y contexto'
SELECT operacion, tabla, rol, usuario_id = :mec_a AS por_mec_a, host(ip_origen) AS ip, request_id, resultado, count(*)
FROM auditoria_operacion GROUP BY 1, 2, 3, 4, 5, 6, 7 ORDER BY min(id);
\echo '-- 4e. columnas enmascaradas: ninguna debe aparecer'
SELECT count(*) AS registros_con_dato_personal
FROM auditoria_operacion
WHERE (tabla = 'titular'      AND (COALESCE(datos_nuevos, '{}') ?| ARRAY['nombre', 'telefono', 'email', 'identificador_hmac']))
   OR (tabla = 'vehiculo'     AND (COALESCE(datos_nuevos, '{}') ?| ARRAY['patente', 'vin']))
   OR (tabla = 'usuario'      AND (COALESCE(datos_nuevos, '{}') ?| ARRAY['email', 'nombre']))
   OR (tabla = 'falla_sesion' AND (COALESCE(datos_nuevos, '{}') ? 'freeze_frame'));
SELECT datos_nuevos FROM auditoria_operacion WHERE tabla = 'vehiculo' AND operacion = 'INSERT';
\echo '-- 4f. auditoria inmutable (se espera error)'
UPDATE auditoria_operacion SET resultado = 'fallo';
RESET ROLE;

\echo
\echo '=== 5. Administrador del taller A: contrasenas y supresion ==='
SET LOCAL ROLE taller_admin;
SELECT set_config('app.taller_id', :'taller_a', true) AS taller, set_config('app.usuario_id', :'admin_a', true) AS usuario;
\echo '-- 5a. fijar contrasena de un usuario de otro taller (se espera error RE009)'
SELECT fn_establecer_contrasena(:mec_b, 'ClaveNueva123');
\echo '-- 5b. fijar contrasena de un usuario propio y autenticar con ella'
SELECT fn_establecer_contrasena(:mec_a, 'ClaveNueva123');
RESET ROLE;
SELECT autenticado FROM fn_autenticar_usuario('mec@a.test', 'ClaveNueva123');
SET LOCAL ROLE taller_admin;
\echo '-- 5c. supresion: hay una atencion completada hoy -> bloqueado por retencion'
SELECT fn_solicitar_supresion_titular(:titular) AS estado_resultante;
SELECT estado_tratamiento, bloqueado_hasta = (current_date + interval '6 years')::date AS vence_en_6_anios FROM titular WHERE id = :titular;
SELECT tipo, estado FROM solicitud_derecho_titular;
\echo '-- 5d. el administrador no puede anonimizar directamente (se espera error)'
SELECT fn_anonimizar_titular(:titular);
\echo '-- 5e. el administrador no puede modificar precios maestros (se espera error)'
UPDATE repuesto SET precio_referencia = 1 WHERE id = :rep_gen;
RESET ROLE;

\echo
\echo '=== 6. Tras el bloqueo, el mecanico ya no ve al titular ni su vehiculo; la sesion sigue visible ==='
SET LOCAL ROLE taller_mecanico;
SELECT set_config('app.taller_id', :'taller_a', true) AS taller, set_config('app.usuario_id', :'mec_a', true) AS usuario;
SELECT (SELECT count(*) FROM titular) AS titulares, (SELECT count(*) FROM vehiculo) AS vehiculos,
       (SELECT count(*) FROM sesion_diagnostico) AS sesiones;
RESET ROLE;

\echo
\echo '=== 6b. Rol asumido pero SIN app.taller_id: cero filas (falla cerrado) ==='
SET LOCAL ROLE taller_mecanico;
SELECT set_config('app.taller_id', '', true) AS taller_vacio;
SELECT (SELECT count(*) FROM sesion_diagnostico) AS sesiones, (SELECT count(*) FROM taller) AS talleres,
       (SELECT count(*) FROM cotizacion) AS cotizaciones;
\echo '-- 6c. app.taller_id con un valor no numerico (se espera error de conversion)'
SELECT set_config('app.taller_id', 'abc', true) AS taller_invalido;
SELECT count(*) FROM sesion_diagnostico;
RESET ROLE;

\echo
\echo '=== 7. Anonimizacion (proceso de mantenimiento) ==='
RESET SESSION AUTHORIZATION;
-- Se adelanta el vencimiento para simular el paso del tiempo.
UPDATE titular SET bloqueado_hasta = current_date WHERE id = :titular;
SET ROLE app_owner;
SELECT fn_anonimizar_vencidos() AS anonimizados;
RESET ROLE;
SELECT nombre, telefono, identificador_hmac, estado_tratamiento, anonimizado_en IS NOT NULL AS con_fecha FROM titular WHERE id = :titular;
SELECT patente, vin, motor, anio, anonimizado_en IS NOT NULL AS anonimizado FROM vehiculo WHERE id = :vehiculo;
SELECT estado FROM solicitud_derecho_titular;
SELECT s.estado, c.total FROM sesion_diagnostico s JOIN cotizacion c ON c.sesion_id = s.id WHERE s.id = :sesion;
\echo '-- 7a. TRUNCATE de la auditoria como superusuario (se espera error RE005)'
TRUNCATE auditoria_operacion;

ROLLBACK;
\echo
\echo '=== 8. SET LOCAL fuera de una transaccion no tiene efecto: falla cerrado ==='
SET SESSION AUTHORIZATION app_backend_user;
SET LOCAL ROLE taller_mecanico;
SELECT current_user AS rol_efectivo;
SELECT count(*) FROM sesion_diagnostico;
RESET SESSION AUTHORIZATION;
SELECT (SELECT count(*) FROM taller) AS talleres_tras_rollback, (SELECT count(*) FROM auditoria_operacion) AS auditoria_tras_rollback;

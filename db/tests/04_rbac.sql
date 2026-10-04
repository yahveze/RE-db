-- =============================================================================
-- 04 - RBAC: que operaciones puede ejecutar cada rol.
-- Matriz rol x sentencia del backend (db/queries) y los privilegios por columna.
-- 42501 = permission denied. Los ids usados son del PROPIO taller del rol: lo
-- que se niega aqui es la operacion, no la fila (eso es RLS, archivo 05).
-- =============================================================================
\ir incluir/inicio.sql
\echo '### 04 RBAC'
\o /dev/null

\ir incluir/rol_plataforma.sql
SELECT s.id AS ses_id, s.id_publico AS ses FROM sesion_diagnostico s
WHERE  s.taller_id = :taller_1 AND s.estado = 'pendiente'
AND    EXISTS (SELECT 1 FROM cotizacion c WHERE c.sesion_id = s.id AND c.cerrada_en IS NULL) \gset
SELECT c.id AS cot_id, c.id_publico AS cot FROM cotizacion c WHERE c.sesion_id = :ses_id \gset
SELECT v.id AS veh_id, v.id_publico AS veh FROM vehiculo v WHERE v.taller_id = :taller_1 AND v.patente = 'LPRS56' \gset
SELECT t.id AS tit_id, t.id_publico AS tit FROM titular t WHERE t.taller_id = :taller_1 AND t.nombre = 'Juana Pérez Soto' \gset
SELECT u.id_publico AS usr FROM usuario u WHERE u.id = :mec_1b \gset
SELECT r.id AS rep_id, r.id_publico AS rep FROM repuesto r WHERE r.codigo_fabricante = 'SC20HR11' \gset
SELECT mo.id_publico AS modelo FROM modelo_vehiculo mo WHERE mo.nombre = 'Hilux' \gset

-- =========================================================== sin asumir rol
\echo '--- conexion del backend sin SET LOCAL ROLE'
\ir incluir/rol_backend.sql

\set prueba 'backend sin rol: no lee tablas operativas'
\set esperado 42501
SELECT count(*) FROM sesion_diagnostico;
\ir incluir/error.sql

\set prueba 'backend sin rol: no lee catalogos'
\set esperado 42501
SELECT count(*) FROM repuesto;
\ir incluir/error.sql

\set prueba 'backend sin rol: no lee credenciales'
\set esperado 42501
SELECT count(*) FROM usuario_credencial;
\ir incluir/error.sql

\set prueba 'backend sin rol: no ejecuta funciones de negocio'
\set esperado 42501
SELECT fn_crear_cotizacion(:ses_id, gen_random_uuid());
\ir incluir/error.sql

\set prueba 'backend sin rol: no puede anonimizar'
\set esperado 42501
SELECT fn_anonimizar_vencidos();
\ir incluir/error.sql

\set prueba 'backend sin rol: no puede asumir app_owner ni app_funciones'
\set esperado 42501
SET LOCAL ROLE app_funciones;
\ir incluir/error.sql

\set prueba 'backend sin rol: si puede autenticar (unico privilegio propio)'
EXECUTE q_login('mecanico1@losaromos.example', :'clave_demo') \gset l_
SELECT :'l_autenticado'::boolean AS ok \gset
\ir incluir/afirmar.sql

-- ================================================================ mecanico
\echo '--- taller_mecanico'
\ir incluir/rol_mecanico_1.sql

\set prueba 'mecanico: q_configuracion'
EXECUTE q_configuracion;
\ir incluir/exito.sql
\set prueba 'mecanico: q_marcas'
EXECUTE q_marcas;
\ir incluir/exito.sql
\set prueba 'mecanico: q_dtc_buscar'
EXECUTE q_dtc_buscar('P0', 5);
\ir incluir/exito.sql
\set prueba 'mecanico: q_repuestos_por_dtc'
EXECUTE q_repuestos_por_dtc('P0301', NULL, NULL);
\ir incluir/exito.sql
\set prueba 'mecanico: q_buscar_vehiculo_patente'
EXECUTE q_buscar_vehiculo_patente('LPRS56');
\ir incluir/exito.sql
\set prueba 'mecanico: q_buscar_vehiculo_vin'
EXECUTE q_buscar_vehiculo_vin('8AJFR22G5B4512345');
\ir incluir/exito.sql
\set prueba 'mecanico: q_buscar_vehiculo_modelo'
EXECUTE q_buscar_vehiculo_modelo(:'modelo', NULL, 5);
\ir incluir/exito.sql
\set prueba 'mecanico: q_historial'
EXECUTE q_historial(5);
\ir incluir/exito.sql
\set prueba 'mecanico: q_historial_estado'
EXECUTE q_historial_estado('pendiente', 5);
\ir incluir/exito.sql
\set prueba 'mecanico: q_historial_siguiente'
EXECUTE q_historial_siguiente(now(), :'ses', 5);
\ir incluir/exito.sql
\set prueba 'mecanico: q_historial_estado_siguiente'
EXECUTE q_historial_estado_siguiente('completado', now(), :'ses', 5);
\ir incluir/exito.sql
\set prueba 'mecanico: q_consentimientos_titular'
EXECUTE q_consentimientos_titular(:'tit');
\ir incluir/exito.sql
\set prueba 'mecanico: q_historial_vehiculo'
EXECUTE q_historial_vehiculo(:'veh', 5);
\ir incluir/exito.sql
\set prueba 'mecanico: q_sesion'
EXECUTE q_sesion(:'ses');
\ir incluir/exito.sql
\set prueba 'mecanico: q_sesion_fallas'
EXECUTE q_sesion_fallas(:'ses');
\ir incluir/exito.sql
\set prueba 'mecanico: q_matriz'
EXECUTE q_matriz(:'ses');
\ir incluir/exito.sql
\set prueba 'mecanico: q_cotizaciones_sesion'
EXECUTE q_cotizaciones_sesion(:'ses');
\ir incluir/exito.sql
\set prueba 'mecanico: q_cotizacion_detalle'
EXECUTE q_cotizacion_detalle(:'cot');
\ir incluir/exito.sql
\set prueba 'mecanico: q_dashboard_resumen'
EXECUTE q_dashboard_resumen(now() - interval '30 days');
\ir incluir/exito.sql
\set prueba 'mecanico: q_dashboard_dtc_frecuentes'
EXECUTE q_dashboard_dtc_frecuentes(now() - interval '90 days', 5);
\ir incluir/exito.sql
\set prueba 'mecanico: q_dispositivos'
EXECUTE q_dispositivos;
\ir incluir/exito.sql

\set prueba 'mecanico: q_usuarios denegada (no lee usuario.email)'
\set esperado 42501
EXECUTE q_usuarios;
\ir incluir/error.sql
\set prueba 'mecanico: q_auditoria denegada'
\set esperado 42501
EXECUTE q_auditoria(NULL, 5);
\ir incluir/error.sql
\set prueba 'mecanico: q_auditoria_siguiente denegada'
\set esperado 42501
EXECUTE q_auditoria_siguiente(NULL, now(), 1, 5);
\ir incluir/error.sql
\set prueba 'mecanico: q_solicitudes_derecho denegada'
\set esperado 42501
EXECUTE q_solicitudes_derecho;
\ir incluir/error.sql
\set prueba 'mecanico: tx_crear_usuario denegada'
\set esperado 42501
EXECUTE tx_crear_usuario('x@losaromos.example', 'X', 'mecanico');
\ir incluir/error.sql
\set prueba 'mecanico: tx_establecer_contrasena denegada'
\set esperado 42501
EXECUTE tx_establecer_contrasena(:'usr', 'Clave-Nueva-123');
\ir incluir/error.sql
\set prueba 'mecanico: tx_cambiar_activo_usuario denegada'
\set esperado 42501
EXECUTE tx_cambiar_activo_usuario(:'usr', false);
\ir incluir/error.sql
\set prueba 'mecanico: tx_actualizar_configuracion denegada'
\set esperado 42501
EXECUTE tx_actualizar_configuracion(NULL, 0, NULL);
\ir incluir/error.sql
\set prueba 'mecanico: tx_registrar_dispositivo denegada'
\set esperado 42501
EXECUTE tx_registrar_dispositivo('00:11:22:33:44:55', 'X', 'Y', '1');
\ir incluir/error.sql
\set prueba 'mecanico: tx_solicitar_supresion denegada'
\set esperado 42501
EXECUTE tx_solicitar_supresion(:'tit');
\ir incluir/error.sql

\set prueba 'mecanico: no modifica precios maestros'
\set esperado 42501
UPDATE repuesto SET precio_referencia = 1 WHERE id = :rep_id;
\ir incluir/error.sql
\set prueba 'mecanico: no inserta en catalogos'
\set esperado 42501
INSERT INTO marca_vehiculo (nombre) VALUES ('Marca falsa');
\ir incluir/error.sql
\set prueba 'mecanico: no lee credenciales'
\set esperado 42501
SELECT hash_contrasena FROM usuario_credencial;
\ir incluir/error.sql
\set prueba 'mecanico: no lee el email de los usuarios'
\set esperado 42501
SELECT email FROM usuario;
\ir incluir/error.sql
\set prueba 'mecanico: no crea una sesion con estado elegido'
\set esperado 42501
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, metodo_ingreso, kilometraje, estado)
VALUES (:taller_1, :veh_id, :mec_1, 'manual', 10, 'completado');
\ir incluir/error.sql
\set prueba 'mecanico: no fija a mano los timestamps de estado (RN-33)'
\set esperado 42501
UPDATE sesion_diagnostico SET cotizada_en = now() WHERE id = :ses_id;
\ir incluir/error.sql
\set prueba 'mecanico: no reasigna una sesion a otro usuario'
\set esperado 42501
UPDATE sesion_diagnostico SET usuario_id = :mec_1b WHERE id = :ses_id;
\ir incluir/error.sql
\set prueba 'mecanico: no cambia la version a mano'
\set esperado 42501
UPDATE sesion_diagnostico SET version = 1 WHERE id = :ses_id;
\ir incluir/error.sql
\set prueba 'mecanico: no escribe el total de una cotizacion'
\set esperado 42501
UPDATE cotizacion SET total = 1 WHERE id = :cot_id;
\ir incluir/error.sql
\set prueba 'mecanico: no cambia el precio de una linea'
\set esperado 42501
UPDATE cotizacion_detalle SET precio_unitario = 1 WHERE cotizacion_id = :cot_id;
\ir incluir/error.sql
\set prueba 'mecanico: no borra cotizaciones'
\set esperado 42501
DELETE FROM cotizacion WHERE id = :cot_id;
\ir incluir/error.sql
\set prueba 'mecanico: no borra fallas'
\set esperado 42501
DELETE FROM falla_sesion WHERE sesion_id = :ses_id;
\ir incluir/error.sql
\set prueba 'mecanico: no borra sesiones (RN-72)'
\set esperado 42501
DELETE FROM sesion_diagnostico WHERE id = :ses_id;
\ir incluir/error.sql
\set prueba 'mecanico: no cambia el estado de tratamiento de un titular'
\set esperado 42501
UPDATE titular SET estado_tratamiento = 'bloqueado', bloqueado_hasta = current_date WHERE id = :tit_id;
\ir incluir/error.sql
\set prueba 'mecanico: no cambia el identificador HMAC de un titular'
\set esperado 42501
UPDATE titular SET identificador_hmac = NULL WHERE id = :tit_id;
\ir incluir/error.sql
\set prueba 'mecanico: no marca un vehiculo como anonimizado'
\set esperado 42501
UPDATE vehiculo SET anonimizado_en = now(), patente = NULL, vin = NULL WHERE id = :veh_id;
\ir incluir/error.sql
\set prueba 'mecanico: no muda un vehiculo de taller'
\set esperado 42501
UPDATE vehiculo SET taller_id = :taller_2 WHERE id = :veh_id;
\ir incluir/error.sql
\set prueba 'mecanico: no anonimiza directamente'
\set esperado 42501
SELECT fn_anonimizar_titular(:tit_id);
\ir incluir/error.sql
\set prueba 'mecanico: no escribe en la auditoria'
\set esperado 42501
SELECT fn_registrar_auditoria(:taller_1, :mec_1, 'UPDATE', 'sesion_diagnostico', 1, NULL, NULL, 'exito');
\ir incluir/error.sql
\set prueba 'mecanico: no hace TRUNCATE'
\set esperado 42501
TRUNCATE cotizacion_detalle;
\ir incluir/error.sql

\set prueba 'mecanico: si corrige el telefono de un titular'
UPDATE titular SET telefono = '+56900000000' WHERE id = :tit_id;
\set esperado 1
\ir incluir/filas.sql
\set prueba 'mecanico: si corrige la severidad de una falla'
UPDATE falla_sesion SET severidad = 'baja' WHERE sesion_id = :ses_id;
\ir incluir/exito.sql
\set prueba 'mecanico: si revoca un consentimiento'
UPDATE consentimiento_titular SET revocado_en = now() WHERE titular_id = :tit_id AND finalidad = 'contacto_seguimiento';
\set esperado 1
\ir incluir/filas.sql

-- =========================================================== administrador
\echo '--- taller_admin'
\ir incluir/rol_admin_1.sql

\set prueba 'admin: q_configuracion'
EXECUTE q_configuracion;
\ir incluir/exito.sql
\set prueba 'admin: q_buscar_vehiculo_patente'
EXECUTE q_buscar_vehiculo_patente('LPRS56');
\ir incluir/exito.sql
\set prueba 'admin: q_historial'
EXECUTE q_historial(5);
\ir incluir/exito.sql
\set prueba 'admin: q_sesion'
EXECUTE q_sesion(:'ses');
\ir incluir/exito.sql
\set prueba 'admin: q_matriz'
EXECUTE q_matriz(:'ses');
\ir incluir/exito.sql
\set prueba 'admin: q_cotizacion_detalle'
EXECUTE q_cotizacion_detalle(:'cot');
\ir incluir/exito.sql
\set prueba 'admin: q_dashboard_resumen'
EXECUTE q_dashboard_resumen(now() - interval '30 days');
\ir incluir/exito.sql
\set prueba 'admin: q_usuarios'
EXECUTE q_usuarios;
\ir incluir/exito.sql
\set prueba 'admin: q_dispositivos'
EXECUTE q_dispositivos;
\ir incluir/exito.sql
\set prueba 'admin: q_solicitudes_derecho'
EXECUTE q_solicitudes_derecho;
\ir incluir/exito.sql
\set prueba 'admin: q_auditoria'
EXECUTE q_auditoria(NULL, 5);
\ir incluir/exito.sql
\set prueba 'admin: q_auditoria_siguiente'
EXECUTE q_auditoria_siguiente(NULL, now(), 1, 5);
\ir incluir/exito.sql
\set prueba 'admin: q_consentimientos_titular'
EXECUTE q_consentimientos_titular(:'tit');
\ir incluir/exito.sql
\set prueba 'admin: tx_cambiar_activo_usuario'
EXECUTE tx_cambiar_activo_usuario(:'usr', false);
\set esperado 1
\ir incluir/filas.sql
\set prueba 'admin: tx_registrar_dispositivo'
EXECUTE tx_registrar_dispositivo('00:11:22:33:44:55', 'Marca', 'Modelo', '1.0');
\set esperado 1
\ir incluir/filas.sql
\set prueba 'admin: tx_actualizar_configuracion'
EXECUTE tx_actualizar_configuracion('oscuro', NULL, NULL);
\set esperado 1
\ir incluir/filas.sql
\set prueba 'admin: tx_crear_titular'
EXECUTE tx_crear_titular('Titular de prueba', NULL, NULL, NULL);
\set esperado 1
\ir incluir/filas.sql

\set prueba 'admin: tx_crear_sesion denegada (solo el mecanico atiende)'
\set esperado 42501
EXECUTE tx_crear_sesion(:'veh', NULL, 10, '[{"codigo": "P0301"}]');
\ir incluir/error.sql
\set prueba 'admin: tx_cambiar_estado denegada (T-32)'
\set esperado 42501
EXECUTE tx_cambiar_estado(:'ses', 'cancelado', NULL);
\ir incluir/error.sql
\set prueba 'admin: tx_crear_cotizacion denegada'
\set esperado 42501
EXECUTE tx_crear_cotizacion(:'ses', gen_random_uuid());
\ir incluir/error.sql
\set prueba 'admin: tx_guardar_linea denegada'
\set esperado 42501
EXECUTE tx_guardar_linea(:'cot', :'rep', 1);
\ir incluir/error.sql
\set prueba 'admin: tx_quitar_linea denegada'
\set esperado 42501
EXECUTE tx_quitar_linea(:'cot', :'rep');
\ir incluir/error.sql
\set prueba 'admin: tx_cerrar_cotizacion denegada'
\set esperado 42501
EXECUTE tx_cerrar_cotizacion(:'cot', NULL);
\ir incluir/error.sql
\set prueba 'admin: no modifica precios maestros (afectarian a otros talleres)'
\set esperado 42501
UPDATE repuesto SET precio_referencia = 1 WHERE id = :rep_id;
\ir incluir/error.sql
\set prueba 'admin: no renombra ni desactiva su taller'
\set esperado 42501
UPDATE taller SET activo = false WHERE id = :taller_1;
\ir incluir/error.sql
\set prueba 'admin: no cambia el taller de su configuracion'
\set esperado 42501
UPDATE taller_configuracion SET taller_id = :taller_2;
\ir incluir/error.sql
\set prueba 'admin: no muda un usuario de taller'
\set esperado 42501
UPDATE usuario SET taller_id = :taller_2 WHERE id = :mec_1b;
\ir incluir/error.sql
\set prueba 'admin: no borra usuarios (baja logica)'
\set esperado 42501
DELETE FROM usuario WHERE id = :mec_1b;
\ir incluir/error.sql
\set prueba 'admin: no lee credenciales'
\set esperado 42501
SELECT hash_contrasena FROM usuario_credencial;
\ir incluir/error.sql
\set prueba 'admin: no escribe credenciales directamente'
\set esperado 42501
UPDATE usuario_credencial SET intentos_fallidos = 0;
\ir incluir/error.sql
\set prueba 'admin: no cambia el estado de tratamiento a mano (solo via funcion)'
\set esperado 42501
UPDATE titular SET estado_tratamiento = 'anonimizado' WHERE id = :tit_id;
\ir incluir/error.sql
\set prueba 'admin: no anonimiza directamente (saltaria la retencion)'
\set esperado 42501
SELECT fn_anonimizar_titular(:tit_id);
\ir incluir/error.sql
\set prueba 'admin: no ejecuta el proceso de anonimizacion de vencidos'
\set esperado 42501
SELECT fn_anonimizar_vencidos();
\ir incluir/error.sql
\set prueba 'admin: no inserta en la auditoria'
\set esperado 42501
INSERT INTO auditoria_operacion (rol, operacion, resultado) VALUES ('x', 'LOGIN', 'exito');
\ir incluir/error.sql
\set prueba 'admin: no modifica la auditoria (RN-70)'
\set esperado 42501
UPDATE auditoria_operacion SET resultado = 'fallo';
\ir incluir/error.sql
\set prueba 'admin: no borra la auditoria (RN-70)'
\set esperado 42501
DELETE FROM auditoria_operacion;
\ir incluir/error.sql

-- ================================================================= auditor
\echo '--- taller_auditor'
\ir incluir/rol_auditor_1.sql

\set prueba 'auditor: q_configuracion'
EXECUTE q_configuracion;
\ir incluir/exito.sql
\set prueba 'auditor: q_historial'
EXECUTE q_historial(5);
\ir incluir/exito.sql
\set prueba 'auditor: q_historial_vehiculo'
EXECUTE q_historial_vehiculo(:'veh', 5);
\ir incluir/exito.sql
\set prueba 'auditor: q_sesion'
EXECUTE q_sesion(:'ses');
\ir incluir/exito.sql
\set prueba 'auditor: q_sesion_fallas'
EXECUTE q_sesion_fallas(:'ses');
\ir incluir/exito.sql
\set prueba 'auditor: q_matriz'
EXECUTE q_matriz(:'ses');
\ir incluir/exito.sql
\set prueba 'auditor: q_cotizaciones_sesion'
EXECUTE q_cotizaciones_sesion(:'ses');
\ir incluir/exito.sql
\set prueba 'auditor: q_cotizacion_detalle'
EXECUTE q_cotizacion_detalle(:'cot');
\ir incluir/exito.sql
\set prueba 'auditor: q_dashboard_resumen'
EXECUTE q_dashboard_resumen(now() - interval '30 days');
\ir incluir/exito.sql
\set prueba 'auditor: q_usuarios'
EXECUTE q_usuarios;
\ir incluir/exito.sql
\set prueba 'auditor: q_dispositivos'
EXECUTE q_dispositivos;
\ir incluir/exito.sql
\set prueba 'auditor: q_solicitudes_derecho'
EXECUTE q_solicitudes_derecho;
\ir incluir/exito.sql
\set prueba 'auditor: q_auditoria'
EXECUTE q_auditoria(NULL, 5);
\ir incluir/exito.sql
\set prueba 'auditor: q_historial_estado'
EXECUTE q_historial_estado('completado', 5);
\ir incluir/exito.sql
\set prueba 'auditor: q_auditoria_siguiente'
EXECUTE q_auditoria_siguiente(NULL, now(), 1, 5);
\ir incluir/exito.sql
\set prueba 'auditor: q_consentimientos_titular (no devuelve identidad del titular)'
EXECUTE q_consentimientos_titular(:'tit');
\ir incluir/exito.sql
\set prueba 'auditor: lee el estado de tratamiento de los titulares'
SELECT count(*) >= 5 AS ok FROM (SELECT id_publico, estado_tratamiento, bloqueado_hasta FROM titular) t \gset
\ir incluir/afirmar.sql

\set prueba 'auditor: no lee el nombre del titular'
\set esperado 42501
SELECT nombre FROM titular;
\ir incluir/error.sql
\set prueba 'auditor: no lee telefono, email ni HMAC del titular'
\set esperado 42501
SELECT telefono, email, identificador_hmac FROM titular;
\ir incluir/error.sql
\set prueba 'auditor: SELECT * FROM titular falla (privilegio por columna)'
\set esperado 42501
SELECT * FROM titular;
\ir incluir/error.sql
\set prueba 'auditor: q_buscar_vehiculo_patente denegada (devuelve el nombre del titular)'
\set esperado 42501
EXECUTE q_buscar_vehiculo_patente('LPRS56');
\ir incluir/error.sql
\set prueba 'auditor: q_buscar_vehiculo_vin denegada'
\set esperado 42501
EXECUTE q_buscar_vehiculo_vin('8AJFR22G5B4512345');
\ir incluir/error.sql
\set prueba 'auditor: q_buscar_vehiculo_modelo denegada'
\set esperado 42501
EXECUTE q_buscar_vehiculo_modelo(:'modelo', NULL, 5);
\ir incluir/error.sql
\set prueba 'auditor: tx_crear_titular denegada'
\set esperado 42501
EXECUTE tx_crear_titular('X', NULL, NULL, NULL);
\ir incluir/error.sql
\set prueba 'auditor: tx_registrar_consentimiento denegada'
\set esperado 42501
EXECUTE tx_registrar_consentimiento(:'tit', 'marketing', 'v1', 'web');
\ir incluir/error.sql
\set prueba 'auditor: tx_crear_vehiculo denegada'
\set esperado 42501
EXECUTE tx_crear_vehiculo(NULL, :'modelo', 2020, '2.4', NULL, 'WXYZ11');
\ir incluir/error.sql
\set prueba 'auditor: tx_crear_sesion denegada'
\set esperado 42501
EXECUTE tx_crear_sesion(:'veh', NULL, 10, '[{"codigo": "P0301"}]');
\ir incluir/error.sql
\set prueba 'auditor: tx_cambiar_estado denegada'
\set esperado 42501
EXECUTE tx_cambiar_estado(:'ses', 'cancelado', NULL);
\ir incluir/error.sql
\set prueba 'auditor: tx_crear_cotizacion denegada'
\set esperado 42501
EXECUTE tx_crear_cotizacion(:'ses', gen_random_uuid());
\ir incluir/error.sql
\set prueba 'auditor: tx_guardar_linea denegada'
\set esperado 42501
EXECUTE tx_guardar_linea(:'cot', :'rep', 1);
\ir incluir/error.sql
\set prueba 'auditor: tx_quitar_linea denegada'
\set esperado 42501
EXECUTE tx_quitar_linea(:'cot', :'rep');
\ir incluir/error.sql
\set prueba 'auditor: tx_cerrar_cotizacion denegada'
\set esperado 42501
EXECUTE tx_cerrar_cotizacion(:'cot', NULL);
\ir incluir/error.sql
\set prueba 'auditor: tx_crear_usuario denegada'
\set esperado 42501
EXECUTE tx_crear_usuario('x@losaromos.example', 'X', 'mecanico');
\ir incluir/error.sql
\set prueba 'auditor: tx_establecer_contrasena denegada'
\set esperado 42501
EXECUTE tx_establecer_contrasena(:'usr', 'Clave-Nueva-123');
\ir incluir/error.sql
\set prueba 'auditor: tx_cambiar_activo_usuario denegada'
\set esperado 42501
EXECUTE tx_cambiar_activo_usuario(:'usr', false);
\ir incluir/error.sql
\set prueba 'auditor: tx_actualizar_configuracion denegada'
\set esperado 42501
EXECUTE tx_actualizar_configuracion(NULL, 0, NULL);
\ir incluir/error.sql
\set prueba 'auditor: tx_registrar_dispositivo denegada'
\set esperado 42501
EXECUTE tx_registrar_dispositivo('00:11:22:33:44:66', 'X', 'Y', '1');
\ir incluir/error.sql
\set prueba 'auditor: tx_solicitar_supresion denegada'
\set esperado 42501
EXECUTE tx_solicitar_supresion(:'tit');
\ir incluir/error.sql
\set prueba 'auditor: no lee credenciales'
\set esperado 42501
SELECT hash_contrasena FROM usuario_credencial;
\ir incluir/error.sql
\set prueba 'auditor: no modifica la auditoria'
\set esperado 42501
UPDATE auditoria_operacion SET resultado = 'fallo';
\ir incluir/error.sql

ROLLBACK;

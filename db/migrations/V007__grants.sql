-- =============================================================================
-- V007 - Privilegios (RBAC): QUE operaciones puede ejecutar cada rol.
-- Que FILAS ve o modifica lo decide RLS (V008).
--
-- Metodo: primero REVOKE ALL a PUBLIC, despues GRANT explicitos por tabla y,
-- donde corresponde, por COLUMNA.
--
-- app_backend_user NO recibe privilegios sobre tablas: solo EXECUTE sobre el
-- login. Para todo lo demas debe asumir un grupo con SET LOCAL ROLE.
-- Nadie recibe DELETE sobre historiales ni TRUNCATE sobre nada.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- 0. REVOKE a PUBLIC (explicito, tabla por tabla)
-- ----------------------------------------------------------------------------
REVOKE ALL ON
  marca_vehiculo, modelo_vehiculo, dtc_catalogo, componente_repuesto, dtc_componente,
  repuesto, compatibilidad_repuesto, v_dtc_repuesto,
  taller, taller_configuracion, usuario, usuario_credencial,
  titular, consentimiento_titular, solicitud_derecho_titular,
  vehiculo, dispositivo_diagnostico, sesion_diagnostico, falla_sesion,
  cotizacion, cotizacion_detalle, auditoria_operacion
FROM PUBLIC;

REVOKE ALL ON FUNCTION
  fn_contexto_taller_id(), fn_contexto_usuario_id(), fn_contexto_rol(), fn_contexto_ip_origen(),
  fn_trg_marcar_actualizado(), fn_trg_incrementar_version(),
  fn_registrar_auditoria(bigint, bigint, tipo_operacion_auditoria, text, bigint, jsonb, jsonb, tipo_resultado_auditoria),
  fn_trg_auditoria_inmutable(), fn_trg_sesion_validar_transicion(),
  fn_cambiar_estado_sesion(bigint, tipo_estado_atencion, integer),
  fn_trg_cotizacion_preparar(), fn_trg_cotizacion_validar_actualizacion(),
  fn_trg_cotizacion_detalle_validar(),
  fn_crear_cotizacion(bigint, uuid), fn_cerrar_cotizacion(bigint, integer)
FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- 1. Catalogos globales: solo lectura para los tres grupos.
--    Los escribe unicamente app_owner (su propietario). Un cambio de precio
--    maestro afecta a todos los talleres, por eso ningun rol de taller escribe.
-- ----------------------------------------------------------------------------
GRANT SELECT ON
  marca_vehiculo, modelo_vehiculo, dtc_catalogo, componente_repuesto, dtc_componente,
  repuesto, compatibilidad_repuesto, v_dtc_repuesto
TO taller_admin, taller_mecanico, taller_auditor;

-- ----------------------------------------------------------------------------
-- 2. taller y taller_configuracion
-- ----------------------------------------------------------------------------
-- Todos leen su taller y su configuracion (moneda, tema, margen para la matriz).
GRANT SELECT ON taller, taller_configuracion
TO taller_admin, taller_mecanico, taller_auditor;

-- Solo el administrador cambia la configuracion; no puede cambiar taller_id.
GRANT UPDATE (moneda, tema, margen_pct, retencion_anios) ON taller_configuracion
TO taller_admin;

-- ----------------------------------------------------------------------------
-- 3. usuario
-- ----------------------------------------------------------------------------
-- El administrador gestiona los usuarios de su taller. No puede cambiar
-- taller_id ni los identificadores.
GRANT SELECT ON usuario TO taller_admin;
GRANT INSERT (taller_id, email, nombre, rol, activo) ON usuario TO taller_admin;
GRANT UPDATE (email, nombre, rol, activo) ON usuario TO taller_admin;

-- El auditor los lee completos (quien hizo que).
GRANT SELECT ON usuario TO taller_auditor;

-- El mecanico ve a sus companeros sin el email.
GRANT SELECT (id, id_publico, taller_id, nombre, rol, activo) ON usuario TO taller_mecanico;

-- usuario_credencial: NINGUN grupo. Solo app_funciones (seccion 10).

-- ----------------------------------------------------------------------------
-- 4. titular, consentimiento, solicitud
-- ----------------------------------------------------------------------------
-- Mecanico y administrador registran y corrigen datos de contacto. El estado
-- de tratamiento, el bloqueo y la anonimizacion solo cambian via funciones.
GRANT SELECT ON titular TO taller_admin, taller_mecanico;
GRANT INSERT (taller_id, nombre, telefono, email, identificador_hmac) ON titular
TO taller_admin, taller_mecanico;
GRANT UPDATE (nombre, telefono, email, identificador_hmac) ON titular TO taller_admin;
GRANT UPDATE (nombre, telefono, email) ON titular TO taller_mecanico;

-- El auditor NO ve las columnas de identidad del titular (grant por columna).
-- Consecuencia: SELECT * FROM titular falla para el auditor; debe pedir columnas.
GRANT SELECT (id, id_publico, taller_id, estado_tratamiento, bloqueado_hasta, anonimizado_en,
              creado_en, actualizado_en)
ON titular TO taller_auditor;

GRANT SELECT ON consentimiento_titular TO taller_admin, taller_mecanico, taller_auditor;
GRANT INSERT (taller_id, titular_id, finalidad, version_terminos, canal, otorgado_en)
ON consentimiento_titular TO taller_admin, taller_mecanico;
-- Revocar es fijar revocado_en; la fila no se borra.
GRANT UPDATE (revocado_en) ON consentimiento_titular TO taller_admin, taller_mecanico;

-- Las solicitudes de derechos las gestiona el administrador.
GRANT SELECT ON solicitud_derecho_titular TO taller_admin, taller_auditor;
GRANT INSERT (taller_id, titular_id, tipo, estado, usuario_responsable_id, recibida_en)
ON solicitud_derecho_titular TO taller_admin;
GRANT UPDATE (estado, usuario_responsable_id, resuelta_en) ON solicitud_derecho_titular TO taller_admin;

-- ----------------------------------------------------------------------------
-- 5. vehiculo y dispositivo
-- ----------------------------------------------------------------------------
GRANT SELECT ON vehiculo TO taller_admin, taller_mecanico, taller_auditor;
-- INSERT/UPDATE limitado: sin taller_id en UPDATE y sin anonimizado_en.
GRANT INSERT (taller_id, titular_id, modelo_vehiculo_id, anio, motor, vin, patente) ON vehiculo
TO taller_admin, taller_mecanico;
GRANT UPDATE (titular_id, modelo_vehiculo_id, anio, motor, vin, patente) ON vehiculo
TO taller_admin, taller_mecanico;

GRANT SELECT ON dispositivo_diagnostico TO taller_admin, taller_mecanico, taller_auditor;
GRANT INSERT (taller_id, mac, estado, fabricante, modelo, firmware) ON dispositivo_diagnostico
TO taller_admin;
GRANT UPDATE (mac, estado, fabricante, modelo, firmware) ON dispositivo_diagnostico
TO taller_admin;

-- ----------------------------------------------------------------------------
-- 6. sesion y fallas
-- ----------------------------------------------------------------------------
GRANT SELECT ON sesion_diagnostico TO taller_admin, taller_mecanico, taller_auditor;
-- El mecanico no puede insertar estado, timestamps de estado ni version:
-- toda sesion nace 'pendiente' (valores por defecto).
GRANT INSERT (taller_id, vehiculo_id, usuario_id, dispositivo_id, metodo_ingreso, kilometraje, iniciada_en)
ON sesion_diagnostico TO taller_mecanico;
-- Solo estado (validado por trigger) y kilometraje. Los timestamps de estado
-- los fija el trigger; el privilegio de columna impide tocarlos a mano.
GRANT UPDATE (estado, kilometraje) ON sesion_diagnostico TO taller_mecanico;

GRANT SELECT ON falla_sesion TO taller_admin, taller_mecanico, taller_auditor;
GRANT INSERT (sesion_id, dtc_id, taller_id, severidad, freeze_frame) ON falla_sesion TO taller_mecanico;
GRANT UPDATE (severidad, freeze_frame) ON falla_sesion TO taller_mecanico;

-- ----------------------------------------------------------------------------
-- 7. cotizacion y detalle
-- ----------------------------------------------------------------------------
GRANT SELECT ON cotizacion TO taller_admin, taller_mecanico, taller_auditor;
-- Revision, moneda, vigente, cerrada_en y total los fija el trigger al insertar.
GRANT INSERT (taller_id, sesion_id, clave_idempotencia) ON cotizacion TO taller_mecanico;
-- Cerrar y cambiar la vigente. El total NO es actualizable: lo calcula el trigger.
-- (Este UPDATE es ademas lo que permite al mecanico tomar los bloqueos de
--  fila FOR UPDATE / FOR SHARE que usan las funciones y triggers.)
GRANT UPDATE (vigente, cerrada_en) ON cotizacion TO taller_mecanico;

GRANT SELECT ON cotizacion_detalle TO taller_admin, taller_mecanico, taller_auditor;
-- El cliente solo envia repuesto y cantidad; snapshot y precio los pone el trigger.
GRANT INSERT (cotizacion_id, repuesto_id, taller_id, cantidad) ON cotizacion_detalle TO taller_mecanico;
GRANT UPDATE (cantidad) ON cotizacion_detalle TO taller_mecanico;
-- Unico DELETE del modelo: lineas de una cotizacion ABIERTA (el trigger
-- rechaza el borrado si la cabecera esta cerrada).
GRANT DELETE ON cotizacion_detalle TO taller_mecanico;

-- ----------------------------------------------------------------------------
-- 8. auditoria: solo lectura para administrador y auditor de su taller.
--    Nadie tiene INSERT directo: se escribe via triggers y funciones.
-- ----------------------------------------------------------------------------
GRANT SELECT ON auditoria_operacion TO taller_admin, taller_auditor;

-- ----------------------------------------------------------------------------
-- 9. Funciones propiedad de app_owner
-- ----------------------------------------------------------------------------
-- Lectura del contexto (la usan las funciones SECURITY INVOKER).
GRANT EXECUTE ON FUNCTION fn_contexto_taller_id(), fn_contexto_usuario_id()
TO taller_admin, taller_mecanico, taller_auditor, app_funciones;
GRANT EXECUTE ON FUNCTION fn_contexto_rol(), fn_contexto_ip_origen() TO app_funciones;
GRANT EXECUTE ON FUNCTION
  fn_registrar_auditoria(bigint, bigint, tipo_operacion_auditoria, text, bigint, jsonb, jsonb, tipo_resultado_auditoria)
TO app_funciones;

-- Operaciones del mecanico (SECURITY INVOKER: corren con SUS privilegios y RLS).
GRANT EXECUTE ON FUNCTION
  fn_crear_cotizacion(bigint, uuid),
  fn_cerrar_cotizacion(bigint, integer),
  fn_cambiar_estado_sesion(bigint, tipo_estado_atencion, integer)
TO taller_mecanico;

-- Las funciones de trigger no necesitan EXECUTE para quien ejecuta el DML:
-- PostgreSQL comprueba ese privilegio al CREAR el trigger, no al dispararlo.

-- ----------------------------------------------------------------------------
-- 10. app_funciones: privilegios de TABLA minimos para las funciones
--     SECURITY DEFINER. BYPASSRLS salta las politicas, no los GRANT.
-- ----------------------------------------------------------------------------
-- Login y cambio de contrasena.
GRANT SELECT ON usuario, taller TO app_funciones;
GRANT SELECT, INSERT, UPDATE ON usuario_credencial TO app_funciones;
-- Auditoria: solo insertar.
GRANT INSERT ON auditoria_operacion TO app_funciones;
-- Supresion y anonimizacion.
GRANT SELECT ON taller_configuracion, sesion_diagnostico TO app_funciones;
GRANT SELECT, UPDATE ON titular, vehiculo, consentimiento_titular TO app_funciones;
GRANT SELECT, INSERT, UPDATE ON solicitud_derecho_titular TO app_funciones;

-- ----------------------------------------------------------------------------
-- 11. Funciones SECURITY DEFINER (propiedad de app_funciones)
--     Solo su propietario puede otorgar EXECUTE sobre ellas; se asume ese rol
--     (posible por la membresia app_funciones -> app_owner con SET TRUE).
-- ----------------------------------------------------------------------------
SET ROLE app_funciones;

REVOKE ALL ON FUNCTION
  fn_trg_auditar(),
  fn_autenticar_usuario(text, text),
  fn_establecer_contrasena(bigint, text),
  fn_anonimizar_titular(bigint),
  fn_solicitar_supresion_titular(bigint),
  fn_anonimizar_vencidos()
FROM PUBLIC;

-- El login ocurre antes de que exista contexto: EXECUTE directo para el rol
-- de conexion. Es el unico privilegio propio de app_backend_user.
GRANT EXECUTE ON FUNCTION fn_autenticar_usuario(text, text) TO app_backend_user;

-- Gestion de contrasenas y supresion: solo el administrador (las funciones
-- validan ademas el rol y el taller del contexto).
GRANT EXECUTE ON FUNCTION fn_establecer_contrasena(bigint, text) TO taller_admin;
GRANT EXECUTE ON FUNCTION fn_solicitar_supresion_titular(bigint) TO taller_admin;

-- Mantenimiento: el proceso periodico corre como app_owner. Ningun rol de
-- taller puede anonimizar directamente (se saltaria la retencion legal).
GRANT EXECUTE ON FUNCTION fn_anonimizar_vencidos(), fn_anonimizar_titular(bigint) TO app_owner;

SET ROLE app_owner;

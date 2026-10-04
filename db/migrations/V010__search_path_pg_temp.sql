-- =============================================================================
-- V010 - search_path de las funciones: pg_temp explicito y al final (Fase 7).
-- Evidencia: docs/evidencia/fase7_antes.txt (B5) y fase7_dictamen.txt (B5).
--
-- Hallazgo del dictamen de cierre. Todas las funciones fijaban
--     SET search_path = pg_catalog, public
-- Cuando pg_temp NO se nombra, PostgreSQL lo busca PRIMERO para tablas y tipos
-- (no para funciones ni operadores). Una tabla temporal llamada igual que una
-- tabla real la suplanta dentro de la funcion, aunque la funcion sea
-- SECURITY DEFINER. Experimento: con el privilegio TEMPORARY, un mecanico crea
-- la tabla temporal auditoria_operacion, le otorga INSERT a PUBLIC, y sus
-- escrituras quedan "auditadas" en esa tabla, que desaparece con su sesion; la
-- auditoria real no recibe nada. Del mismo modo podria suplantarse usuario o
-- usuario_credencial ante el login.
--
-- No era explotable: ningun rol de la aplicacion tiene TEMPORARY sobre la base
-- (V000 revoca todo a PUBLIC). Pero esa era la UNICA barrera, no estaba
-- probada, y la propia suite la levanta dentro de una transaccion
-- (09_consultas.sql). Un GRANT TEMPORARY futuro, razonable para un reporte,
-- habria abierto el camino sin que nada fallara.
--
-- Correccion: pg_temp nombrado de forma explicita y en ultimo lugar. Asi una
-- tabla real de public siempre gana a una temporal homonima. Se aplica a las 21
-- funciones (las 6 definidoras y, por uniformidad, las demas: fn_registrar_
-- auditoria es SECURITY INVOKER pero corre dentro de las definidoras).
-- Lo vigilan ESQ-30, ESQ-31 y la prueba de sombra de 07_auditoria.sql.
--
-- V005 no se edita: una migracion aplicada no se reescribe.
-- =============================================================================

-- Funciones propiedad de app_owner.
ALTER FUNCTION fn_contexto_taller_id()                    SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_contexto_usuario_id()                   SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_contexto_rol()                          SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_contexto_ip_origen()                    SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_trg_marcar_actualizado()                SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_trg_incrementar_version()               SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_registrar_auditoria(bigint, bigint, tipo_operacion_auditoria, text, bigint, jsonb, jsonb, tipo_resultado_auditoria)
                                                          SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_trg_auditoria_inmutable()               SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_trg_sesion_validar_transicion()         SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_cambiar_estado_sesion(bigint, tipo_estado_atencion, integer)
                                                          SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_trg_cotizacion_preparar()               SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_trg_cotizacion_validar_actualizacion()  SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_trg_cotizacion_detalle_validar()        SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_crear_cotizacion(bigint, uuid)          SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_cerrar_cotizacion(bigint, integer)      SET search_path = pg_catalog, public, pg_temp;

-- Funciones SECURITY DEFINER: solo su propietario puede alterarlas; se asume
-- ese rol (membresia app_funciones -> app_owner con SET TRUE, igual que en V007).
SET ROLE app_funciones;

ALTER FUNCTION fn_trg_auditar()                           SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_autenticar_usuario(text, text)          SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_establecer_contrasena(bigint, text)     SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_anonimizar_titular(bigint)              SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_solicitar_supresion_titular(bigint)     SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_anonimizar_vencidos()                   SET search_path = pg_catalog, public, pg_temp;

SET ROLE app_owner;

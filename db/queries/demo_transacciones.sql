-- =============================================================================
-- Demostracion de las transacciones de escritura (docs/transacciones.md).
--
-- Recorre una atencion completa con las sentencias tx_* y el rol real del
-- backend, incluidos los errores de negocio. TODO ocurre dentro de una
-- transaccion exterior que termina en ROLLBACK: la base queda como la dejaron
-- las semillas (se comprueba al final).
--
-- Por eso cada "peticion" se delimita aqui con SAVEPOINT peticion / RESET ROLE.
-- En el backend cada una es su propio BEGIN ... COMMIT, y ante un error hace
-- ROLLBACK de la peticion completa (aqui: ROLLBACK TO peticion).
--
-- Los errores marcados "se espera" son el resultado correcto; tras cada uno se
-- imprime su SQLSTATE. El script de evidencia cuenta que no haya ni uno mas.
-- Uso: bash db/scripts/psql.sh -f /db/queries/demo_transacciones.sql
-- =============================================================================
\encoding UTF8
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
\set VERBOSITY terse
\pset pager off

SELECT (SELECT count(*) FROM usuario)             AS usuarios,
       (SELECT count(*) FROM titular)             AS titulares,
       (SELECT count(*) FROM vehiculo)            AS vehiculos,
       (SELECT count(*) FROM sesion_diagnostico)  AS sesiones,
       (SELECT count(*) FROM cotizacion)          AS cotizaciones,
       (SELECT count(*) FROM auditoria_operacion) AS auditoria \gset antes_

SET SESSION AUTHORIZATION app_backend_user;
\ir preparar.sql

BEGIN;

-- Inicios de sesion de los usuarios que ya existen: ocurren sin contexto.
EXECUTE q_login('admin@losaromos.example', :'clave_demo') \gset ad_
EXECUTE q_login('mecanico@nuble.example',  :'clave_demo') \gset m2_

\echo '=== TX-1. Alta de usuario con contrasena (administradora, taller 1) ==='
SAVEPOINT peticion;
SET LOCAL ROLE taller_admin;
EXECUTE ctx(:'ad_taller_id', :'ad_usuario_id', '192.168.10.2', 'demo-tx-1a') \gset ctx_
\echo '-- 1a. usuario creado, contrasena fuera de limites (se espera RE011) -> la peticion completa se revierte'
EXECUTE tx_crear_usuario('mecanico3@losaromos.example', 'Andrea Lagos', 'mecanico') \gset nu_
EXECUTE tx_establecer_contrasena(:'nu_id_publico', 'corta');
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
ROLLBACK TO peticion;
SET LOCAL ROLE taller_admin;
SELECT count(*) AS usuarios_con_ese_email FROM usuario WHERE email = 'mecanico3@losaromos.example';
RESET ROLE;

SAVEPOINT peticion;
SET LOCAL ROLE taller_admin;
EXECUTE ctx(:'ad_taller_id', :'ad_usuario_id', '192.168.10.2', 'demo-tx-1b') \gset ctx_
\echo '-- 1b. usuario y contrasena en la misma transaccion'
EXECUTE tx_crear_usuario('mecanico3@losaromos.example', 'Andrea Lagos', 'mecanico') \gset nu_
\echo creado: :nu_email rol=:nu_rol activo=:nu_activo
EXECUTE tx_establecer_contrasena(:'nu_id_publico', :'clave_demo') \gset pw_
\echo '-- 1c. email repetido (se espera 23505)'
EXECUTE tx_crear_usuario('mecanico3@losaromos.example', 'Otra Persona', 'auditor');
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
RESET ROLE;
\echo '-- 1d. el usuario nuevo se autentica'
-- (se limpia el contexto de la peticion anterior: aqui sigue vivo porque toda
--  la demostracion comparte una transaccion; en el backend murio con su COMMIT)
EXECUTE ctx('', '', '', '') \gset ctx_
EXECUTE q_login('mecanico3@losaromos.example', :'clave_demo') \gset m3_
\echo autenticado=:m3_autenticado rol=:m3_rol nombre=:m3_nombre

\echo
\echo '=== TX-2. Titular, consentimiento y vehiculo (mecanica nueva) ==='
SAVEPOINT peticion;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m3_taller_id', :'m3_usuario_id', '192.168.10.23', 'demo-tx-2') \gset ctx_
EXECUTE tx_crear_titular('Rosa Molina Paz', '+56988888888', NULL, NULL) \gset ti_
\echo titular: :ti_nombre estado=:ti_estado_tratamiento
EXECUTE tx_registrar_consentimiento(:'ti_id_publico', 'prestacion_servicio', 'v1.0', 'presencial');
SELECT mo.id_publico AS modelo_corolla FROM modelo_vehiculo mo WHERE mo.nombre = 'Corolla' \gset
EXECUTE tx_crear_vehiculo(:'ti_id_publico', :'modelo_corolla', 2019, '1.8 Bencina', NULL, 'RSTV45') \gset ve_
\echo vehiculo: patente=:ve_patente anio=:ve_anio
\echo '-- 2a. patente ya registrada en el taller (se espera 23505)'
EXECUTE tx_crear_vehiculo(NULL, :'modelo_corolla', 2020, '1.8 Bencina', NULL, 'LPRS56');
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
\echo '-- 2b. patente con formato invalido (se espera 23514)'
EXECUTE tx_crear_vehiculo(NULL, :'modelo_corolla', 2020, '1.8 Bencina', NULL, 'rstv46');
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
\echo '-- 2c. titular inexistente: cero filas, no crea un vehiculo "sin titular"'
EXECUTE tx_crear_vehiculo('00000000-0000-4000-8000-000000000000', :'modelo_corolla', 2020, '1.8 Bencina', NULL, 'RSTV47');
RESET ROLE;

\echo
\echo '=== TX-3. Crear sesion con sus fallas (una sola sentencia) ==='
SAVEPOINT peticion;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m3_taller_id', :'m3_usuario_id', '192.168.10.23', 'demo-tx-3') \gset ctx_
SELECT d.id_publico AS dispositivo_activo   FROM dispositivo_diagnostico d WHERE d.estado = 'activo'   \gset
SELECT d.id_publico AS dispositivo_inactivo FROM dispositivo_diagnostico d WHERE d.estado = 'inactivo' \gset
\echo '-- 3a. un DTC que no esta en el catalogo (se espera 23502): no queda ni la sesion ni la otra falla'
EXECUTE tx_crear_sesion(:'ve_id_publico', :'dispositivo_activo', 52300, '[{"codigo": "P0335"}, {"codigo": "P3999"}]');
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
\echo '-- 3b. dispositivo inactivo con ingreso OBD (se espera 23514)'
EXECUTE tx_crear_sesion(:'ve_id_publico', :'dispositivo_inactivo', 52300, '[{"codigo": "P0335"}]');
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
EXECUTE q_historial_vehiculo(:'ve_id_publico', 5);
\echo '-- 3c. sesion valida: nace pendiente, version 1, con 2 fallas'
EXECUTE tx_crear_sesion(:'ve_id_publico', :'dispositivo_activo', 52300,
  '[{"codigo": "P0335", "freeze_frame": {"rpm": 0, "voltaje_bateria": 11.8}}, {"codigo": "C0035", "severidad": "media"}]') \gset se_
\echo sesion: estado=:se_estado metodo=:se_metodo_ingreso version=:se_version fallas_registradas=:se_fallas_registradas
EXECUTE q_sesion_fallas(:'se_id_publico');
\echo '-- 3d. matriz de la sesion (Corolla 2019, margen 30 %)'
EXECUTE q_matriz(:'se_id_publico');
RESET ROLE;

\echo
\echo '=== TX-4. Cotizacion: borrador idempotente y lineas ==='
SAVEPOINT peticion;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m3_taller_id', :'m3_usuario_id', '192.168.10.23', 'demo-tx-4') \gset ctx_
\echo '-- 4a. cotizado sin cotizacion cerrada (se espera RE002)'
EXECUTE tx_cambiar_estado(:'se_id_publico', 'cotizado', :se_version);
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
\echo '-- 4b. crear cotizacion; el reintento con la misma clave devuelve la misma'
EXECUTE tx_crear_cotizacion(:'se_id_publico', 'aaaaaaaa-0000-4000-8000-000000000001') \gset co_
\echo cotizacion: revision=:co_numero_revision vigente=:co_vigente moneda=:co_moneda version=:co_version
EXECUTE tx_crear_cotizacion(:'se_id_publico', 'aaaaaaaa-0000-4000-8000-000000000001') \gset re_
SELECT :'co_id_publico' = :'re_id_publico' AS misma_cotizacion,
       (SELECT count(*) FROM cotizacion c JOIN sesion_diagnostico s ON s.id = c.sesion_id
        WHERE s.id_publico = :'se_id_publico') AS cotizaciones_de_la_sesion;
\echo '-- 4c. segundo borrador con otra clave (se espera 23505: un solo borrador por sesion)'
EXECUTE tx_crear_cotizacion(:'se_id_publico', 'aaaaaaaa-0000-4000-8000-000000000002');
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
SELECT r.id_publico AS rep_ckp_toyota FROM repuesto r WHERE r.codigo_fabricante = '90919-05057' \gset
SELECT r.id_publico AS rep_ckp_bosch  FROM repuesto r WHERE r.codigo_fabricante = '0261210170'  \gset
SELECT r.id_publico AS rep_ckp_gen    FROM repuesto r WHERE r.codigo_fabricante = 'GEN-CKP-01'  \gset
SELECT r.id_publico AS rep_abs_bosch  FROM repuesto r WHERE r.codigo_fabricante = '0265007905'  \gset
SELECT r.id_publico AS rep_no_disp    FROM repuesto r WHERE r.codigo_fabricante = 'GEN-INY-02'  \gset
\echo '-- 4d. lineas: el cliente envia repuesto y cantidad; el precio lo pone el trigger'
EXECUTE tx_guardar_linea(:'co_id_publico', :'rep_ckp_toyota', 1);
EXECUTE tx_guardar_linea(:'co_id_publico', :'rep_abs_bosch', 2);
EXECUTE tx_guardar_linea(:'co_id_publico', :'rep_ckp_gen', 1);
\echo '-- 4e. repetir un repuesto reemplaza la cantidad (2 -> 1); quitar una linea'
EXECUTE tx_guardar_linea(:'co_id_publico', :'rep_abs_bosch', 1);
EXECUTE tx_quitar_linea(:'co_id_publico', :'rep_ckp_gen');
\echo '-- 4f. repuesto no disponible (se espera RE010) y cantidad 0 (se espera 23514)'
EXECUTE tx_guardar_linea(:'co_id_publico', :'rep_no_disp', 1);
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
EXECUTE tx_guardar_linea(:'co_id_publico', :'rep_ckp_bosch', 0);
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
EXECUTE q_cotizaciones_sesion(:'se_id_publico');
RESET ROLE;

\echo
\echo '=== TX-5. Cerrar la cotizacion y pasar la sesion a cotizado (una transaccion) ==='
SAVEPOINT peticion;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m3_taller_id', :'m3_usuario_id', '192.168.10.23', 'demo-tx-5') \gset ctx_
\echo '-- 5a. cerrar con una version antigua (se espera RE007)'
EXECUTE tx_cerrar_cotizacion(:'co_id_publico', 99);
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
\echo '-- 5b. cerrar: total = 76687 + 58487 = 135174, vigente, hora del servidor'
EXECUTE tx_cerrar_cotizacion(:'co_id_publico', :co_version) \gset ce_
\echo cerrada: revision=:ce_numero_revision vigente=:ce_vigente total=:ce_total version=:ce_version
EXECUTE tx_cambiar_estado(:'se_id_publico', 'cotizado', :se_version) \gset s2_
\echo sesion: estado=:s2_estado version=:s2_version
\echo '-- 5c. reintento del cierre: devuelve la misma cotizacion, sin cambios'
EXECUTE tx_cerrar_cotizacion(:'co_id_publico', NULL);
\echo '-- 5d. la cotizacion cerrada es inmutable (se esperan 2 errores RE003)'
EXECUTE tx_guardar_linea(:'co_id_publico', :'rep_ckp_bosch', 1);
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
EXECUTE tx_quitar_linea(:'co_id_publico', :'rep_ckp_toyota');
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
RESET ROLE;

\echo
\echo '=== TX-6. Nueva revision: reemplaza a la vigente ==='
SAVEPOINT peticion;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m3_taller_id', :'m3_usuario_id', '192.168.10.23', 'demo-tx-6') \gset ctx_
EXECUTE tx_crear_cotizacion(:'se_id_publico', 'aaaaaaaa-0000-4000-8000-000000000003') \gset c2_
EXECUTE tx_guardar_linea(:'c2_id_publico', :'rep_ckp_bosch', 1);
EXECUTE tx_guardar_linea(:'c2_id_publico', :'rep_abs_bosch', 1);
EXECUTE tx_cerrar_cotizacion(:'c2_id_publico', :c2_version);
\echo '-- una sola vigente: la revision 2; la 1 conserva su total'
EXECUTE q_cotizaciones_sesion(:'se_id_publico');
RESET ROLE;

\echo
\echo '=== TX-7. El administrador cambia el margen: lo cotizado no cambia ==='
SAVEPOINT peticion;
SET LOCAL ROLE taller_admin;
EXECUTE ctx(:'ad_taller_id', :'ad_usuario_id', '192.168.10.2', 'demo-tx-7') \gset ctx_
EXECUTE tx_actualizar_configuracion(NULL, 35, NULL);
\echo '-- 7a. margen fuera de rango (se espera 23514)'
EXECUTE tx_actualizar_configuracion(NULL, 250, NULL);
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
RESET ROLE;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m3_taller_id', :'m3_usuario_id', '192.168.10.23', 'demo-tx-7') \gset ctx_
\echo '-- 7b. detalle de la revision vigente: sigue con el snapshot del 30 %'
EXECUTE q_cotizacion_detalle(:'c2_id_publico');
\echo '-- 7c. la matriz ya usa el 35 %'
EXECUTE q_matriz(:'se_id_publico');
RESET ROLE;

\echo
\echo '=== TX-8. Completar con control optimista ==='
SAVEPOINT peticion;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m3_taller_id', :'m3_usuario_id', '192.168.10.23', 'demo-tx-8') \gset ctx_
\echo '-- 8a. el cliente envia la version que vio antes de cotizar (se espera RE007)'
EXECUTE tx_cambiar_estado(:'se_id_publico', 'completado', :se_version);
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
\echo '-- 8b. con la version actual'
EXECUTE tx_cambiar_estado(:'se_id_publico', 'completado', :s2_version);
\echo '-- 8c. estado terminal: ni otro estado (se espera RE001) ni otra cotizacion (se espera RE004)'
EXECUTE tx_cambiar_estado(:'se_id_publico', 'cancelado', NULL);
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
EXECUTE tx_crear_cotizacion(:'se_id_publico', 'aaaaaaaa-0000-4000-8000-000000000004');
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
RESET ROLE;

\echo
\echo '=== TX-9. Supresion del titular ==='
SAVEPOINT peticion;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m3_taller_id', :'m3_usuario_id', '192.168.10.23', 'demo-tx-9') \gset ctx_
\echo '-- 9a. el mecanico no puede solicitarla (se espera 42501)'
EXECUTE tx_solicitar_supresion(:'ti_id_publico');
\echo '   SQLSTATE' :LAST_ERROR_SQLSTATE
RESET ROLE;
SET LOCAL ROLE taller_admin;
EXECUTE ctx(:'ad_taller_id', :'ad_usuario_id', '192.168.10.2', 'demo-tx-9') \gset ctx_
\echo '-- 9b. la administradora: hay una atencion completada hoy -> bloqueado por retencion'
EXECUTE tx_solicitar_supresion(:'ti_id_publico');
RESET ROLE;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m3_taller_id', :'m3_usuario_id', '192.168.10.23', 'demo-tx-9') \gset ctx_
\echo '-- 9c. el mecanico ya no encuentra el vehiculo; la sesion sigue en el historial sin patente'
EXECUTE q_buscar_vehiculo_patente('RSTV45');
EXECUTE q_historial(1);
RESET ROLE;

\echo
\echo '=== TX-10. Aislamiento en escritura: mecanica del taller 2 con ids publicos del taller 1 ==='
SAVEPOINT peticion;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m2_taller_id', :'m2_usuario_id', '10.20.0.5', 'demo-tx-10') \gset ctx_
\echo '-- cada sentencia devuelve cero filas: los padres no son visibles'
EXECUTE tx_crear_sesion(:'ve_id_publico', NULL, 100, '[{"codigo": "P0335"}]');
EXECUTE tx_cambiar_estado(:'se_id_publico', 'cancelado', NULL);
EXECUTE tx_crear_cotizacion(:'se_id_publico', 'bbbbbbbb-0000-4000-8000-000000000001');
EXECUTE tx_guardar_linea(:'c2_id_publico', :'rep_ckp_bosch', 5);
EXECUTE tx_cerrar_cotizacion(:'c2_id_publico', NULL);
RESET ROLE;

\echo
\echo '=== Auditoria generada por la demostracion (administradora, taller 1) ==='
SET LOCAL ROLE taller_admin;
EXECUTE ctx(:'ad_taller_id', :'ad_usuario_id', '192.168.10.2', 'demo-tx-fin') \gset ctx_
SELECT a.request_id, a.rol, a.operacion, a.tabla, a.resultado, count(*) AS registros
FROM   auditoria_operacion a
WHERE  a.ocurrido_en >= now()
GROUP  BY a.request_id, a.rol, a.operacion, a.tabla, a.resultado
ORDER  BY min(a.id);
RESET ROLE;

ROLLBACK;
RESET SESSION AUTHORIZATION;

\echo
\echo '=== Tras el ROLLBACK: la base queda como la dejaron las semillas ==='
SELECT (SELECT count(*) FROM usuario)             = :antes_usuarios     AS usuarios_igual,
       (SELECT count(*) FROM titular)             = :antes_titulares    AS titulares_igual,
       (SELECT count(*) FROM vehiculo)            = :antes_vehiculos    AS vehiculos_igual,
       (SELECT count(*) FROM sesion_diagnostico)  = :antes_sesiones     AS sesiones_igual,
       (SELECT count(*) FROM cotizacion)          = :antes_cotizaciones AS cotizaciones_igual,
       (SELECT count(*) FROM auditoria_operacion) = :antes_auditoria    AS auditoria_igual,
       (SELECT margen_pct FROM taller_configuracion ORDER BY taller_id LIMIT 1) AS margen_taller_1;

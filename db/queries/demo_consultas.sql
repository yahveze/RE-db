-- =============================================================================
-- Demostracion de las consultas de lectura sobre las semillas.
-- Se conecta como lo hace el backend (app_backend_user, sin privilegios
-- propios) y cada peticion es una transaccion con SET LOCAL ROLE + ctx().
-- No modifica datos: los inicios de sesion van en transacciones con ROLLBACK.
-- No espera errores: cualquier error detiene la ejecucion (ON_ERROR_STOP).
-- Uso: bash db/scripts/psql.sh -f /db/queries/demo_consultas.sql
-- =============================================================================
\encoding UTF8
\pset pager off
\set VERBOSITY terse

SET SESSION AUTHORIZATION app_backend_user;
\ir preparar.sql

\echo '=== 1. Login del mecanico del taller 1 (sin contexto) ==='
BEGIN;
EXECUTE q_login('Mecanico1@LosAromos.example', :'clave_demo') \gset m1_
ROLLBACK;
\echo autenticado=:m1_autenticado rol=:m1_rol nombre=:m1_nombre
\echo '-- clave incorrecta: una fila, sin motivo'
BEGIN;
EXECUTE q_login('mecanico1@losaromos.example', 'clave-incorrecta');
ROLLBACK;

\echo
\echo '=== 2. Configuracion y catalogos (mecanico, taller 1) ==='
BEGIN;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m1_taller_id', :'m1_usuario_id', '192.168.10.21', 'demo-consultas-2') \gset ctx_
\echo '-- q_configuracion'
EXECUTE q_configuracion;
\echo '-- q_marcas'
EXECUTE q_marcas;
SELECT id_publico AS marca_toyota FROM marca_vehiculo WHERE nombre = 'Toyota' \gset
\echo '-- q_modelos(Toyota)'
EXECUTE q_modelos(:'marca_toyota');
\echo '-- q_dtc_buscar(P03, 10)'
EXECUTE q_dtc_buscar('P03', 10);
COMMIT;

\echo
\echo '=== 3. Busqueda de vehiculos (mecanico, taller 1) ==='
BEGIN;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m1_taller_id', :'m1_usuario_id', '192.168.10.21', 'demo-consultas-3') \gset ctx_
\echo '-- q_buscar_vehiculo_patente(LPRS56)'
EXECUTE q_buscar_vehiculo_patente('LPRS56');
\echo '-- q_buscar_vehiculo_vin(JTDBR32E720123456)'
EXECUTE q_buscar_vehiculo_vin('JTDBR32E720123456');
SELECT mo.id_publico AS modelo_hilux FROM modelo_vehiculo mo WHERE mo.nombre = 'Hilux' \gset
\echo '-- q_buscar_vehiculo_modelo(Hilux, cualquier anio, 10)'
EXECUTE q_buscar_vehiculo_modelo(:'modelo_hilux', NULL, 10);
\echo '-- patente de un titular bloqueado (BCDF12): el mecanico no la encuentra'
EXECUTE q_buscar_vehiculo_patente('BCDF12');
COMMIT;

\echo
\echo '=== 4. Historial con paginacion por clave (mecanico, taller 1) ==='
BEGIN;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m1_taller_id', :'m1_usuario_id', '192.168.10.21', 'demo-consultas-4') \gset ctx_
\echo '-- pagina 1: q_historial(5)'
EXECUTE q_historial(5);
-- La API toma el cursor de la ultima fila de la pagina que acaba de devolver.
SELECT s.iniciada_en AS cursor_fecha, s.id_publico AS cursor_id
FROM   sesion_diagnostico s
ORDER  BY s.iniciada_en DESC, s.id DESC
OFFSET 4 LIMIT 1 \gset
\echo '-- pagina 2: q_historial(NULL, <cursor>, 5)'
EXECUTE q_historial_siguiente(:'cursor_fecha', :'cursor_id', 5);
\echo '-- filtrado por estado: q_historial_estado(pendiente, 5)'
EXECUTE q_historial_estado('pendiente', 5);
COMMIT;

\echo
\echo '=== 5. Detalle de sesion, fallas y matriz (mecanico, taller 1) ==='
BEGIN;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m1_taller_id', :'m1_usuario_id', '192.168.10.21', 'demo-consultas-5') \gset ctx_
-- Sesion pendiente de la Kia Morning 2015 (P0201 y P0300).
SELECT s.id_publico AS sesion_morning
FROM   sesion_diagnostico s JOIN vehiculo v ON v.id = s.vehiculo_id
WHERE  v.patente = 'DFGH21' \gset
-- Sesion de la Corolla 2006 (P0401).
SELECT s.id_publico AS sesion_corolla
FROM   sesion_diagnostico s JOIN vehiculo v ON v.id = s.vehiculo_id
WHERE  v.patente = 'XK4521' \gset
-- Sesion mas reciente de la Yaris (U0100, sin componente asociado).
SELECT s.id_publico AS sesion_u0100
FROM   sesion_diagnostico s JOIN vehiculo v ON v.id = s.vehiculo_id
WHERE  v.patente = 'GHJK34' ORDER BY s.iniciada_en DESC LIMIT 1 \gset
-- Sesion completada de la Yaris (dos revisiones).
SELECT s.id_publico AS sesion_yaris
FROM   sesion_diagnostico s JOIN vehiculo v ON v.id = s.vehiculo_id
WHERE  v.patente = 'GHJK34' ORDER BY s.iniciada_en LIMIT 1 \gset
-- Sesion completada del Accent, cuyo titular esta bloqueado: vehiculo oculto.
SELECT s.id_publico AS sesion_oculta
FROM   sesion_diagnostico s
WHERE  NOT EXISTS (SELECT 1 FROM vehiculo v WHERE v.id = s.vehiculo_id)
ORDER  BY s.iniciada_en LIMIT 1 \gset

\echo '-- q_sesion (Kia Morning 2015, pendiente con borrador)'
\x on
EXECUTE q_sesion(:'sesion_morning');
\x off
\echo '-- q_sesion_fallas'
EXECUTE q_sesion_fallas(:'sesion_morning');
\echo '-- q_matriz: Kia Morning 2015. Sin genuinos (no hay de la marca Kia); P0300 y P0201 comparten el inyector'
EXECUTE q_matriz(:'sesion_morning');
\echo '-- q_matriz: Toyota Corolla 2006. El anio deja fuera genuinos (2010+) y OEM (2008+)'
EXECUTE q_matriz(:'sesion_corolla');
\echo '-- q_matriz: sesion con U0100 (DTC sin componente): cero filas'
EXECUTE q_matriz(:'sesion_u0100');
\echo '-- q_matriz: sesion cuyo vehiculo esta oculto para el mecanico: cero filas'
EXECUTE q_matriz(:'sesion_oculta');
\echo '-- q_sesion de esa sesion: sigue visible, con las columnas del vehiculo en NULL'
\x on
EXECUTE q_sesion(:'sesion_oculta');
\x off
\echo '-- q_repuestos_por_dtc(P0420) sin vehiculo, y para una Hilux 2016 (fuera de los rangos del Walker)'
EXECUTE q_repuestos_por_dtc('P0420', NULL, NULL);
EXECUTE q_repuestos_por_dtc('P0420', :'modelo_hilux', 2016);
COMMIT;

\echo
\echo '=== 6. Cotizaciones (mecanico, taller 1) ==='
BEGIN;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m1_taller_id', :'m1_usuario_id', '192.168.10.21', 'demo-consultas-6') \gset ctx_
\echo '-- q_cotizaciones_sesion (Yaris: dos revisiones, vigente la segunda)'
EXECUTE q_cotizaciones_sesion(:'sesion_yaris');
SELECT c.id_publico AS cotizacion_vigente
FROM   cotizacion c JOIN sesion_diagnostico s ON s.id = c.sesion_id
WHERE  s.id_publico = :'sesion_yaris' AND c.vigente \gset
\echo '-- q_cotizacion_detalle (revision vigente)'
EXECUTE q_cotizacion_detalle(:'cotizacion_vigente');
\echo '-- q_cotizaciones_sesion (Morning: borrador sin total, con total_calculado)'
EXECUTE q_cotizaciones_sesion(:'sesion_morning');
COMMIT;

\echo
\echo '=== 7. Dashboard (mecanico, taller 1) ==='
BEGIN;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m1_taller_id', :'m1_usuario_id', '192.168.10.21', 'demo-consultas-7') \gset ctx_
\echo '-- q_dashboard_resumen(ultimos 30 dias)'
\x on
EXECUTE q_dashboard_resumen(now() - interval '30 days');
\x off
\echo '-- q_dashboard_dtc_frecuentes(ultimos 90 dias, 5)'
EXECUTE q_dashboard_dtc_frecuentes(now() - interval '90 days', 5);
COMMIT;

\echo
\echo '=== 8. Auditor del taller 1 ==='
BEGIN;
EXECUTE q_login('auditor@losaromos.example', :'clave_demo') \gset au_
ROLLBACK;
BEGIN;
SET LOCAL ROLE taller_auditor;
EXECUTE ctx(:'au_taller_id', :'au_usuario_id', '192.168.10.40', 'demo-consultas-8') \gset ctx_
\echo '-- q_historial: el auditor ve todos los vehiculos, tambien el del titular bloqueado y el anonimizado (sin patente)'
EXECUTE q_historial_estado('completado', 10);
EXECUTE q_historial_estado('cancelado', 10);
\echo '-- q_historial_estado_siguiente(completado, <cursor de la 2.a fila>, 10): la pagina siguiente del mismo estado'
SELECT s.iniciada_en AS cursor_fecha, s.id_publico AS cursor_id
FROM   sesion_diagnostico s WHERE s.estado = 'completado'
ORDER  BY s.iniciada_en DESC, s.id DESC OFFSET 1 LIMIT 1 \gset
EXECUTE q_historial_estado_siguiente('completado', :'cursor_fecha', :'cursor_id', 10);
\echo '-- q_consentimientos_titular de un titular bloqueado (el auditor lo ve; sin datos de identidad)'
SELECT t.id_publico AS titular_bloqueado FROM titular t WHERE t.estado_tratamiento = 'bloqueado' \gset
EXECUTE q_consentimientos_titular(:'titular_bloqueado');
\echo '-- q_solicitudes_derecho (sin identidad del titular)'
EXECUTE q_solicitudes_derecho;
\echo '-- q_auditoria(cotizacion, 4)'
EXECUTE q_auditoria('cotizacion', 4);
COMMIT;

\echo
\echo '=== 9. Administradora del taller 1 ==='
BEGIN;
EXECUTE q_login('admin@losaromos.example', :'clave_demo') \gset ad_
ROLLBACK;
BEGIN;
SET LOCAL ROLE taller_admin;
EXECUTE ctx(:'ad_taller_id', :'ad_usuario_id', '192.168.10.2', 'demo-consultas-9') \gset ctx_
\echo '-- q_usuarios'
EXECUTE q_usuarios;
\echo '-- q_dispositivos'
EXECUTE q_dispositivos;
\echo '-- q_auditoria(titular, 3): sin nombre, telefono, email ni HMAC'
EXECUTE q_auditoria('titular', 3);
COMMIT;

\echo
\echo '=== 10. Aislamiento: mecanica del taller 2 con las mismas sentencias ==='
BEGIN;
EXECUTE q_login('mecanico@nuble.example', :'clave_demo') \gset m2_
ROLLBACK;
BEGIN;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'m2_taller_id', :'m2_usuario_id', '10.20.0.5', 'demo-consultas-10') \gset ctx_
\echo '-- q_configuracion: su taller, margen 45,5 %'
EXECUTE q_configuracion;
\echo '-- q_historial: solo sus 4 sesiones'
EXECUTE q_historial(20);
\echo '-- q_buscar_vehiculo_patente(BCDF12): SU Hilux, no el Accent del taller 1'
EXECUTE q_buscar_vehiculo_patente('BCDF12');
\echo '-- sentencias con ids publicos del taller 1: cero filas'
EXECUTE q_sesion(:'sesion_morning');
EXECUTE q_matriz(:'sesion_morning');
EXECUTE q_cotizacion_detalle(:'cotizacion_vigente');
\echo '-- q_repuestos_por_dtc(P0420): mismo catalogo, precio con SU margen'
EXECUTE q_repuestos_por_dtc('P0420', NULL, NULL);
COMMIT;

\echo
\echo '=== 11. Rol asumido sin contexto de taller: cero filas ==='
BEGIN;
SET LOCAL ROLE taller_mecanico;
EXECUTE q_configuracion;
EXECUTE q_historial(5);
\x on
EXECUTE q_dashboard_resumen(now() - interval '30 days');
\x off
COMMIT;

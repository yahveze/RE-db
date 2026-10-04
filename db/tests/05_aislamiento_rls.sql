-- =============================================================================
-- 05 - Aislamiento entre talleres (RLS + FK compuestas) y visibilidad por rol.
-- Los conteos esperados se calculan como plataforma (sin RLS) y se comparan con
-- lo que ve cada rol.
-- =============================================================================
\ir incluir/inicio.sql
\echo '### 05 Aislamiento y RLS'
\o /dev/null

\ir incluir/rol_plataforma.sql
SELECT (SELECT count(*) FROM usuario                   WHERE taller_id = :taller_2) AS usuario,
       (SELECT count(*) FROM titular                   WHERE taller_id = :taller_2) AS titular,
       (SELECT count(*) FROM consentimiento_titular    WHERE taller_id = :taller_2) AS consentimiento,
       (SELECT count(*) FROM solicitud_derecho_titular WHERE taller_id = :taller_2) AS solicitud,
       (SELECT count(*) FROM vehiculo                  WHERE taller_id = :taller_2) AS vehiculo,
       (SELECT count(*) FROM dispositivo_diagnostico   WHERE taller_id = :taller_2) AS dispositivo,
       (SELECT count(*) FROM sesion_diagnostico        WHERE taller_id = :taller_2) AS sesion,
       (SELECT count(*) FROM falla_sesion              WHERE taller_id = :taller_2) AS falla,
       (SELECT count(*) FROM cotizacion                WHERE taller_id = :taller_2) AS cotizacion,
       (SELECT count(*) FROM cotizacion_detalle        WHERE taller_id = :taller_2) AS detalle,
       (SELECT count(*) FROM auditoria_operacion       WHERE taller_id = :taller_2) AS auditoria,
       (SELECT count(*) FROM auditoria_operacion       WHERE taller_id IS NULL)     AS auditoria_sin_taller \gset n2_

-- Objetos del taller 1 que el taller 2 intentara alcanzar.
SELECT s.id AS ses_id, s.id_publico AS ses FROM sesion_diagnostico s
WHERE  s.taller_id = :taller_1 AND s.estado = 'pendiente'
AND    EXISTS (SELECT 1 FROM cotizacion c WHERE c.sesion_id = s.id AND c.cerrada_en IS NULL) \gset
SELECT c.id AS cot_id, c.id_publico AS cot FROM cotizacion c WHERE c.sesion_id = :ses_id \gset
SELECT v.id AS veh_id, v.id_publico AS veh FROM vehiculo v WHERE v.taller_id = :taller_1 AND v.patente = 'LPRS56' \gset
SELECT t.id AS tit_id, t.id_publico AS tit FROM titular t WHERE t.taller_id = :taller_1 AND t.nombre = 'Juana Pérez Soto' \gset
SELECT t.id AS tit_bloq_id FROM titular t WHERE t.taller_id = :taller_1 AND t.estado_tratamiento = 'bloqueado' \gset
SELECT v.id AS veh_bloq_id FROM vehiculo v WHERE v.titular_id = :tit_bloq_id \gset
SELECT u.id_publico AS usr FROM usuario u WHERE u.id = :mec_1 \gset
SELECT r.id AS rep_id, r.id_publico AS rep FROM repuesto r WHERE r.codigo_fabricante = 'SC20HR11' \gset
SELECT mo.id AS modelo_id, mo.id_publico AS modelo FROM modelo_vehiculo mo WHERE mo.nombre = 'Hilux' \gset
SELECT d.id AS dtc_id FROM dtc_catalogo d WHERE d.codigo = 'P0335' \gset
SELECT margen_pct AS margen_1 FROM taller_configuracion WHERE taller_id = :taller_1 \gset

-- ============================================== lo que ve el administrador 2
\echo '--- lectura: cada rol ve solo las filas de su taller'
\ir incluir/rol_admin_2.sql

\set prueba 'taller: solo la fila propia'
SELECT count(*) = 1 AND bool_and(id = :taller_2) AS ok FROM taller \gset
\ir incluir/afirmar.sql
\set prueba 'taller_configuracion: solo la fila propia'
SELECT count(*) = 1 AND bool_and(taller_id = :taller_2) AS ok FROM taller_configuracion \gset
\ir incluir/afirmar.sql
\set prueba 'usuario: todas las del taller y ninguna ajena'
SELECT count(*) = :n2_usuario AND count(*) FILTER (WHERE taller_id <> :taller_2) = 0 AS ok FROM usuario \gset
\ir incluir/afirmar.sql
\set prueba 'titular: todas las del taller y ninguna ajena'
SELECT count(*) = :n2_titular AND count(*) FILTER (WHERE taller_id <> :taller_2) = 0 AS ok FROM titular \gset
\ir incluir/afirmar.sql
\set prueba 'consentimiento_titular: todas las del taller y ninguna ajena'
SELECT count(*) = :n2_consentimiento AND count(*) FILTER (WHERE taller_id <> :taller_2) = 0 AS ok FROM consentimiento_titular \gset
\ir incluir/afirmar.sql
\set prueba 'solicitud_derecho_titular: todas las del taller y ninguna ajena'
SELECT count(*) = :n2_solicitud AND count(*) FILTER (WHERE taller_id <> :taller_2) = 0 AS ok FROM solicitud_derecho_titular \gset
\ir incluir/afirmar.sql
\set prueba 'vehiculo: todas las del taller y ninguna ajena'
SELECT count(*) = :n2_vehiculo AND count(*) FILTER (WHERE taller_id <> :taller_2) = 0 AS ok FROM vehiculo \gset
\ir incluir/afirmar.sql
\set prueba 'dispositivo_diagnostico: todas las del taller y ninguna ajena'
SELECT count(*) = :n2_dispositivo AND count(*) FILTER (WHERE taller_id <> :taller_2) = 0 AS ok FROM dispositivo_diagnostico \gset
\ir incluir/afirmar.sql
\set prueba 'sesion_diagnostico: todas las del taller y ninguna ajena'
SELECT count(*) = :n2_sesion AND count(*) FILTER (WHERE taller_id <> :taller_2) = 0 AS ok FROM sesion_diagnostico \gset
\ir incluir/afirmar.sql
\set prueba 'falla_sesion: todas las del taller y ninguna ajena'
SELECT count(*) = :n2_falla AND count(*) FILTER (WHERE taller_id <> :taller_2) = 0 AS ok FROM falla_sesion \gset
\ir incluir/afirmar.sql
\set prueba 'cotizacion: todas las del taller y ninguna ajena'
SELECT count(*) = :n2_cotizacion AND count(*) FILTER (WHERE taller_id <> :taller_2) = 0 AS ok FROM cotizacion \gset
\ir incluir/afirmar.sql
\set prueba 'cotizacion_detalle: todas las del taller y ninguna ajena'
SELECT count(*) = :n2_detalle AND count(*) FILTER (WHERE taller_id <> :taller_2) = 0 AS ok FROM cotizacion_detalle \gset
\ir incluir/afirmar.sql
\set prueba 'auditoria_operacion: la del taller; ni la ajena ni la que no tiene taller (hay registros sin taller)'
SELECT count(*) = :n2_auditoria AND count(*) FILTER (WHERE taller_id IS DISTINCT FROM :taller_2) = 0
       AND :n2_auditoria_sin_taller > 0 AS ok
FROM   auditoria_operacion \gset
\ir incluir/afirmar.sql
\set prueba 'catalogos globales: se ven completos desde cualquier taller'
SELECT (SELECT count(*) FROM repuesto) = 42 AND (SELECT count(*) FROM dtc_catalogo) = 12 AS ok \gset
\ir incluir/afirmar.sql

\ir incluir/rol_auditor_2.sql
\set prueba 'auditor del taller 2: ve las sesiones y la auditoria de su taller, y nada mas'
SELECT (SELECT count(*) FROM sesion_diagnostico) = :n2_sesion
   AND (SELECT count(*) FROM auditoria_operacion WHERE taller_id IS DISTINCT FROM :taller_2) = 0 AS ok \gset
\ir incluir/afirmar.sql

-- ===================================== escritura cruzada: mecanica del taller 2
\echo '--- escritura: el taller 2 no alcanza filas del taller 1'
\ir incluir/rol_mecanico_2.sql
\set esperado 0

\set prueba 'UPDATE de una sesion ajena: 0 filas'
UPDATE sesion_diagnostico SET kilometraje = 1 WHERE id = :ses_id;
\ir incluir/filas.sql
\set prueba 'UPDATE de un titular ajeno: 0 filas'
UPDATE titular SET telefono = '+56900000000' WHERE id = :tit_id;
\ir incluir/filas.sql
\set prueba 'UPDATE de un vehiculo ajeno: 0 filas'
UPDATE vehiculo SET motor = 'x' WHERE id = :veh_id;
\ir incluir/filas.sql
\set prueba 'UPDATE de fallas ajenas: 0 filas'
UPDATE falla_sesion SET severidad = 'baja' WHERE sesion_id = :ses_id;
\ir incluir/filas.sql
\set prueba 'UPDATE de una cotizacion ajena: 0 filas'
UPDATE cotizacion SET vigente = false WHERE id = :cot_id;
\ir incluir/filas.sql
\set prueba 'UPDATE de lineas ajenas: 0 filas'
UPDATE cotizacion_detalle SET cantidad = 99 WHERE cotizacion_id = :cot_id;
\ir incluir/filas.sql
\set prueba 'DELETE de lineas ajenas: 0 filas'
DELETE FROM cotizacion_detalle WHERE cotizacion_id = :cot_id;
\ir incluir/filas.sql
\set prueba 'UPDATE de consentimientos ajenos: 0 filas'
UPDATE consentimiento_titular SET revocado_en = now() WHERE titular_id = :tit_id;
\ir incluir/filas.sql

\set prueba 'INSERT de un titular con taller_id ajeno: lo rechaza la politica'
\set esperado 42501
INSERT INTO titular (taller_id, nombre) VALUES (:taller_1, 'Intruso');
\ir incluir/error.sql
\set prueba 'INSERT de un vehiculo con taller_id ajeno: lo rechaza la politica'
\set esperado 42501
INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, motor, patente) VALUES (:taller_1, :modelo_id, 2020, '2.4', 'WXYZ11');
\ir incluir/error.sql
\set prueba 'INSERT de una sesion con taller_id ajeno: lo rechaza la politica'
\set esperado 42501
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, metodo_ingreso, kilometraje)
VALUES (:taller_1, :veh_id, :mec_2, 'manual', 10);
\ir incluir/error.sql
\set prueba 'INSERT de una falla con taller_id ajeno: lo rechaza la politica'
\set esperado 42501
INSERT INTO falla_sesion (sesion_id, dtc_id, taller_id, severidad) VALUES (:ses_id, :dtc_id, :taller_1, 'baja');
\ir incluir/error.sql
-- Aqui rechaza antes el trigger BEFORE INSERT (se ejecuta antes que el WITH CHECK
-- de la politica): no encuentra la configuracion del taller ajeno.
\set prueba 'INSERT de una linea con taller_id ajeno: lo rechaza el trigger, que no ve ese taller'
\set esperado RE009
INSERT INTO cotizacion_detalle (cotizacion_id, repuesto_id, taller_id, cantidad) VALUES (:cot_id, :rep_id, :taller_1, 1);
\ir incluir/error.sql

\set prueba 'Sesion propia sobre un vehiculo ajeno: la rechaza la FK compuesta (RLS no interviene en las FK)'
\set esperado 23503
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, metodo_ingreso, kilometraje)
VALUES (:taller_2, :veh_id, :mec_2, 'manual', 10);
\ir incluir/error.sql
\set prueba 'Falla con taller propio sobre una sesion ajena: la rechaza la FK compuesta'
\set esperado 23503
INSERT INTO falla_sesion (sesion_id, dtc_id, taller_id, severidad) VALUES (:ses_id, :dtc_id, :taller_2, 'baja');
\ir incluir/error.sql
\set prueba 'Linea con taller propio sobre una cotizacion ajena: la rechaza la FK compuesta'
\set esperado 23503
INSERT INTO cotizacion_detalle (cotizacion_id, repuesto_id, taller_id, cantidad) VALUES (:cot_id, :rep_id, :taller_2, 1);
\ir incluir/error.sql
\set prueba 'Cotizacion con taller propio sobre una sesion ajena: el trigger no encuentra la sesion'
\set esperado RE009
INSERT INTO cotizacion (taller_id, sesion_id, clave_idempotencia) VALUES (:taller_2, :ses_id, gen_random_uuid());
\ir incluir/error.sql

\set prueba 'fn_cambiar_estado_sesion sobre una sesion ajena'
\set esperado RE009
SELECT fn_cambiar_estado_sesion(:ses_id, 'cancelado');
\ir incluir/error.sql
\set prueba 'fn_cerrar_cotizacion sobre una cotizacion ajena'
\set esperado RE009
SELECT fn_cerrar_cotizacion(:cot_id);
\ir incluir/error.sql
\set prueba 'fn_crear_cotizacion sobre una sesion ajena'
\set esperado RE009
SELECT fn_crear_cotizacion(:ses_id, gen_random_uuid());
\ir incluir/error.sql

\echo '--- sentencias del backend con ids publicos ajenos: cero filas'
\set esperado 0
\set prueba 'q_sesion con id publico ajeno'
EXECUTE q_sesion(:'ses');
\ir incluir/filas.sql
\set prueba 'q_sesion_fallas con id publico ajeno'
EXECUTE q_sesion_fallas(:'ses');
\ir incluir/filas.sql
\set prueba 'q_matriz con id publico ajeno'
EXECUTE q_matriz(:'ses');
\ir incluir/filas.sql
\set prueba 'q_cotizaciones_sesion con id publico ajeno'
EXECUTE q_cotizaciones_sesion(:'ses');
\ir incluir/filas.sql
\set prueba 'q_cotizacion_detalle con id publico ajeno'
EXECUTE q_cotizacion_detalle(:'cot');
\ir incluir/filas.sql
\set prueba 'q_historial_vehiculo con id publico ajeno'
EXECUTE q_historial_vehiculo(:'veh', 10);
\ir incluir/filas.sql
\set prueba 'q_buscar_vehiculo_vin con un VIN del otro taller'
EXECUTE q_buscar_vehiculo_vin('JTDBR32E720123456');
\ir incluir/filas.sql
\set prueba 'tx_crear_sesion sobre un vehiculo ajeno'
EXECUTE tx_crear_sesion(:'veh', NULL, 10, '[{"codigo": "P0335"}]');
\ir incluir/filas.sql
\set prueba 'tx_cambiar_estado sobre una sesion ajena'
EXECUTE tx_cambiar_estado(:'ses', 'cancelado', NULL);
\ir incluir/filas.sql
\set prueba 'tx_crear_cotizacion sobre una sesion ajena'
EXECUTE tx_crear_cotizacion(:'ses', gen_random_uuid());
\ir incluir/filas.sql
\set prueba 'tx_guardar_linea sobre una cotizacion ajena'
EXECUTE tx_guardar_linea(:'cot', :'rep', 5);
\ir incluir/filas.sql
\set prueba 'tx_quitar_linea sobre una cotizacion ajena'
EXECUTE tx_quitar_linea(:'cot', :'rep');
\ir incluir/filas.sql
\set prueba 'tx_cerrar_cotizacion sobre una cotizacion ajena'
EXECUTE tx_cerrar_cotizacion(:'cot', NULL);
\ir incluir/filas.sql
\set prueba 'tx_registrar_consentimiento sobre un titular ajeno'
EXECUTE tx_registrar_consentimiento(:'tit', 'marketing', 'v1', 'web');
\ir incluir/filas.sql
\set prueba 'tx_crear_vehiculo con un titular ajeno: no crea un vehiculo sin titular'
EXECUTE tx_crear_vehiculo(:'tit', :'modelo', 2020, '2.4', NULL, 'WXYZ11');
\ir incluir/filas.sql

\ir incluir/rol_admin_2.sql
\set prueba 'tx_establecer_contrasena sobre un usuario ajeno'
EXECUTE tx_establecer_contrasena(:'usr', 'Clave-Intrusa-123');
\ir incluir/filas.sql
\set prueba 'tx_cambiar_activo_usuario sobre un usuario ajeno'
EXECUTE tx_cambiar_activo_usuario(:'usr', false);
\ir incluir/filas.sql
\set prueba 'tx_solicitar_supresion sobre un titular ajeno'
EXECUTE tx_solicitar_supresion(:'tit');
\ir incluir/filas.sql
\set prueba 'tx_actualizar_configuracion (UPDATE sin WHERE) toca solo la fila del taller propio'
EXECUTE tx_actualizar_configuracion(NULL, 99, NULL);
\set esperado 1
\ir incluir/filas.sql

\set prueba 'fn_establecer_contrasena con el id interno de un usuario ajeno (definidora: valida ella misma)'
\set esperado RE009
SELECT fn_establecer_contrasena(:mec_1, 'Clave-Intrusa-123');
\ir incluir/error.sql
\set prueba 'fn_solicitar_supresion_titular con el id interno de un titular ajeno'
\set esperado RE009
SELECT fn_solicitar_supresion_titular(:tit_id);
\ir incluir/error.sql
\set prueba 'INSERT de un usuario en otro taller: lo rechaza la politica'
\set esperado 42501
INSERT INTO usuario (taller_id, email, nombre, rol) VALUES (:taller_1, 'intruso@nuble.example', 'Intruso', 'admin');
\ir incluir/error.sql
\set prueba 'INSERT de un dispositivo en otro taller: lo rechaza la politica'
\set esperado 42501
INSERT INTO dispositivo_diagnostico (taller_id, mac) VALUES (:taller_1, '00:11:22:33:44:77');
\ir incluir/error.sql

\ir incluir/rol_plataforma.sql
\set prueba 'Tras todos los intentos, el taller 1 no cambio (margen, sesion, titular, lineas, credencial)'
SELECT (SELECT margen_pct FROM taller_configuracion WHERE taller_id = :taller_1) = :margen_1
   AND (SELECT margen_pct FROM taller_configuracion WHERE taller_id = :taller_2) = 99
   AND (SELECT kilometraje <> 1 AND estado = 'pendiente' FROM sesion_diagnostico WHERE id = :ses_id)
   AND (SELECT telefono = '+56911111111' FROM titular WHERE id = :tit_id)
   AND (SELECT count(*) = 2 AND bool_and(cantidad <> 99) FROM cotizacion_detalle WHERE cotizacion_id = :cot_id)
   AND (SELECT activo FROM usuario WHERE id = :mec_1)
   AND (SELECT a.autenticado FROM fn_autenticar_usuario('mecanico1@losaromos.example', :'clave_demo') a) AS ok \gset
\ir incluir/afirmar.sql

-- ============================================================ sin contexto
\echo '--- contexto ausente o invalido: falla cerrado'
RESET ROLE;
SET SESSION AUTHORIZATION app_backend_user;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx('', '', '', '') \gset ctx_

\set prueba 'Rol asumido sin app.taller_id: cero filas en todas las tablas de taller'
SELECT (SELECT count(*) FROM taller) + (SELECT count(*) FROM taller_configuracion) + (SELECT count(*) FROM titular)
     + (SELECT count(*) FROM vehiculo) + (SELECT count(*) FROM sesion_diagnostico) + (SELECT count(*) FROM falla_sesion)
     + (SELECT count(*) FROM cotizacion) + (SELECT count(*) FROM cotizacion_detalle)
     + (SELECT count(*) FROM dispositivo_diagnostico) + (SELECT count(*) FROM consentimiento_titular) = 0 AS ok \gset
\ir incluir/afirmar.sql
\set prueba 'Rol asumido sin app.taller_id: no puede insertar en ningun taller'
\set esperado 42501
INSERT INTO titular (taller_id, nombre) VALUES (:taller_1, 'Sin contexto');
\ir incluir/error.sql
\set prueba 'Rol asumido sin app.taller_id: UPDATE sin WHERE no toca nada'
UPDATE sesion_diagnostico SET kilometraje = 1;
\set esperado 0
\ir incluir/filas.sql

\set prueba 'app.taller_id de un taller que no existe: cero filas'
EXECUTE ctx('999999', '1', '', '') \gset ctx_
SELECT (SELECT count(*) FROM sesion_diagnostico) + (SELECT count(*) FROM taller) = 0 AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'app.taller_id no numerico: la consulta falla en lugar de devolver datos'
EXECUTE ctx('1 OR 1=1', '1', '', '') \gset ctx_
\set esperado 22P02
SELECT count(*) FROM sesion_diagnostico;
\ir incluir/error.sql

\ir incluir/rol_plataforma.sql
\set prueba 'FORCE RLS: el propietario app_owner, sin politica propia, no ve ninguna fila'
SET LOCAL ROLE app_owner;
EXECUTE ctx(:'taller_1', :'admin_1', '', '') \gset ctx_
SELECT (SELECT count(*) FROM sesion_diagnostico) + (SELECT count(*) FROM titular) + (SELECT count(*) FROM auditoria_operacion) = 0 AS ok \gset
\ir incluir/afirmar.sql

-- ================================== visibilidad por rol dentro del taller 1
\echo '--- visibilidad del mecanico sobre titulares bloqueados o anonimizados (RN-64)'
\ir incluir/rol_admin_1.sql
\set prueba 'admin del taller 1: ve los 5 titulares, los 8 vehiculos y las 12 sesiones'
SELECT (SELECT count(*) FROM titular) = 5 AND (SELECT count(*) FROM vehiculo) = 8
   AND (SELECT count(*) FROM sesion_diagnostico) = 12 AS ok \gset
\ir incluir/afirmar.sql

\ir incluir/rol_auditor_1.sql
\set prueba 'auditor del taller 1: ve los 5 titulares (sin identidad), los 8 vehiculos y las 12 sesiones'
SELECT (SELECT count(id) FROM titular) = 5 AND (SELECT count(*) FROM vehiculo) = 8
   AND (SELECT count(*) FROM sesion_diagnostico) = 12 AS ok \gset
\ir incluir/afirmar.sql

\ir incluir/rol_mecanico_1.sql
\set prueba 'RN-64 mecanico: solo los 3 titulares activos y sus 6 vehiculos; las 12 sesiones siguen visibles'
SELECT (SELECT count(*) FROM titular) = 3 AND (SELECT bool_and(estado_tratamiento = 'activo') FROM titular)
   AND (SELECT count(*) FROM vehiculo) = 6 AND (SELECT bool_and(anonimizado_en IS NULL) FROM vehiculo)
   AND (SELECT count(*) FROM sesion_diagnostico) = 12 AS ok \gset
\ir incluir/afirmar.sql
\set prueba 'RN-64 mecanico: no ve los consentimientos de titulares que no ve'
SELECT count(*) > 0 AND bool_and(EXISTS (SELECT 1 FROM titular t WHERE t.id = c.titular_id)) AS ok
FROM   consentimiento_titular c \gset
\ir incluir/afirmar.sql
\set prueba 'RN-64 mecanico: no modifica el vehiculo de un titular bloqueado (0 filas)'
UPDATE vehiculo SET motor = '9.9' WHERE id = :veh_bloq_id;
\set esperado 0
\ir incluir/filas.sql
\set prueba 'RN-64 mecanico: no registra un vehiculo a nombre de un titular bloqueado'
\set esperado 42501
INSERT INTO vehiculo (taller_id, titular_id, modelo_vehiculo_id, anio, motor, patente)
VALUES (:taller_1, :tit_bloq_id, :modelo_id, 2020, '2.4', 'WXYZ11');
\ir incluir/error.sql
\set prueba 'RN-64 mecanico: no registra consentimientos de un titular bloqueado'
\set esperado 42501
INSERT INTO consentimiento_titular (taller_id, titular_id, finalidad, version_terminos, canal)
VALUES (:taller_1, :tit_bloq_id, 'marketing', 'v1', 'web');
\ir incluir/error.sql
\set prueba 'RN-25 mecanico: no crea una sesion a nombre de otro mecanico de su taller'
\set esperado 42501
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, metodo_ingreso, kilometraje)
VALUES (:taller_1, :veh_id, :mec_1b, 'manual', 10);
\ir incluir/error.sql
\set prueba 'mecanico: si puede cotizar sobre la sesion de un companero del mismo taller'
SELECT count(*) > 0 AS ok FROM sesion_diagnostico WHERE usuario_id = :mec_1b \gset
\ir incluir/afirmar.sql

ROLLBACK;

-- ==================================================== fuera de transaccion
\echo '--- SET LOCAL fuera de una transaccion no tiene efecto'
SET SESSION AUTHORIZATION app_backend_user;
SET LOCAL ROLE taller_mecanico;
\set prueba 'SET LOCAL ROLE sin BEGIN no asume el rol: la consulta siguiente es denegada'
\set esperado 42501
SELECT count(*) FROM sesion_diagnostico;
\ir incluir/error.sql
RESET SESSION AUTHORIZATION;

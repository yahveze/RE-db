-- =============================================================================
-- 03 - Estados de la atencion y cotizaciones (RN-30 a RN-34, RN-50 a RN-59).
-- Con el rol del mecanico y las sentencias tx_* del backend.
-- =============================================================================
\ir incluir/inicio.sql
\echo '### 03 Estados y cotizaciones'
\o /dev/null

\ir incluir/rol_mecanico_1.sql
SELECT v.id_publico AS veh FROM vehiculo v WHERE v.patente = 'DFGH21' \gset
SELECT r.id AS rep_ngk_id, r.id_publico AS rep_ngk FROM repuesto r WHERE r.codigo_fabricante = 'ILKAR7B11' \gset
SELECT r.id_publico AS rep_bob     FROM repuesto r WHERE r.codigo_fabricante = 'GEN-BOB-01' \gset
SELECT r.id_publico AS rep_no_disp FROM repuesto r WHERE r.codigo_fabricante = 'GEN-INY-02' \gset

-- ------------------------------------------------------------------ sesion
EXECUTE tx_crear_sesion(:'veh', NULL, 150000, '[{"codigo": "P0301"}, {"codigo": "P0171", "severidad": "critica"}]') \gset s_

\set prueba 'La sesion nace pendiente, version 1, manual, a nombre del usuario del contexto y con la hora del servidor'
SELECT s.estado = 'pendiente' AND s.version = 1 AND s.metodo_ingreso = 'manual' AND s.usuario_id = :mec_1
       AND s.taller_id = :taller_1 AND s.iniciada_en = now()
       AND s.cotizada_en IS NULL AND s.completada_en IS NULL AND s.cancelada_en IS NULL AS ok,
       s.id AS ses
FROM   sesion_diagnostico s WHERE s.id_publico = :'s_id_publico' \gset
\ir incluir/afirmar.sql

\set prueba 'Las fallas quedan con la severidad enviada o, si falta, con la sugerida por el catalogo'
SELECT count(*) = 2
   AND bool_and(CASE d.codigo WHEN 'P0301' THEN f.severidad = d.severidad_sugerida WHEN 'P0171' THEN f.severidad = 'critica' END) AS ok
FROM   falla_sesion f JOIN dtc_catalogo d ON d.id = f.dtc_id
WHERE  f.sesion_id = :ses \gset
\ir incluir/afirmar.sql

\set prueba 'RN-30 pendiente -> completado es una transicion invalida'
\set esperado RE001
UPDATE sesion_diagnostico SET estado = 'completado' WHERE id = :ses;
\ir incluir/error.sql

\set prueba 'RN-32 pendiente -> cotizado sin cotizacion vigente cerrada'
\set esperado RE002
EXECUTE tx_cambiar_estado(:'s_id_publico', 'cotizado', NULL);
\ir incluir/error.sql

\set prueba 'RE009 cambiar el estado de una sesion inexistente'
\set esperado RE009
SELECT fn_cambiar_estado_sesion(999999999, 'cancelado');
\ir incluir/error.sql

\set prueba 'El kilometraje se puede corregir y la version se incrementa'
UPDATE sesion_diagnostico SET kilometraje = 150100 WHERE id = :ses;
SELECT s.version = 2 AND s.kilometraje = 150100 AS ok FROM sesion_diagnostico s WHERE s.id = :ses \gset
\ir incluir/afirmar.sql

-- -------------------------------------------------------------- cotizacion
EXECUTE tx_crear_cotizacion(:'s_id_publico', 'cccccccc-0000-4000-8000-000000000001') \gset c_

\set prueba 'RN-50 la cotizacion nace como borrador: revision 1, no vigente, sin total, moneda del taller'
SELECT c.numero_revision = 1 AND NOT c.vigente AND c.cerrada_en IS NULL AND c.total IS NULL
       AND c.moneda = 'CLP' AND c.version = 1 AS ok, c.id AS cot
FROM   cotizacion c WHERE c.id_publico = :'c_id_publico' \gset
\ir incluir/afirmar.sql

\set prueba 'RN-57 reintentar con la misma clave devuelve la misma cotizacion y no crea otra'
EXECUTE tx_crear_cotizacion(:'s_id_publico', 'cccccccc-0000-4000-8000-000000000001') \gset r_
SELECT :'r_id_publico' = :'c_id_publico' AND (SELECT count(*) FROM cotizacion WHERE sesion_id = :ses) = 1 AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'RN-52 un segundo borrador con otra clave se rechaza'
\set esperado 23505
EXECUTE tx_crear_cotizacion(:'s_id_publico', 'cccccccc-0000-4000-8000-000000000002');
\ir incluir/error.sql

\set prueba 'RE008 no se puede cerrar una cotizacion sin detalle'
\set esperado RE008
EXECUTE tx_cerrar_cotizacion(:'c_id_publico', NULL);
\ir incluir/error.sql

\set prueba 'RN-56 el cliente no puede enviar el precio de una linea'
\set esperado 42501
INSERT INTO cotizacion_detalle (cotizacion_id, repuesto_id, taller_id, cantidad, precio_unitario)
VALUES (:cot, :rep_ngk_id, :taller_1, 1, 1);
\ir incluir/error.sql

\set prueba 'RE010 un repuesto no disponible no se puede cotizar'
\set esperado RE010
EXECUTE tx_guardar_linea(:'c_id_publico', :'rep_no_disp', 1);
\ir incluir/error.sql

EXECUTE tx_guardar_linea(:'c_id_publico', :'rep_ngk', 3);
EXECUTE tx_guardar_linea(:'c_id_publico', :'rep_bob', 1);

\set prueba 'RN-56 el trigger llena el snapshot desde el catalogo y el margen del taller'
SELECT count(*) = 2
   AND bool_and(d.nombre_snapshot = r.nombre AND d.marca_snapshot = r.marca AND d.perfil_snapshot = r.perfil
                AND d.precio_referencia_snapshot = r.precio_referencia AND d.margen_pct_snapshot = 30.00
                AND d.precio_unitario = ROUND(r.precio_referencia * 1.30)) AS ok
FROM   cotizacion_detalle d JOIN repuesto r ON r.id = d.repuesto_id
WHERE  d.cotizacion_id = :cot \gset
\ir incluir/afirmar.sql

\set prueba 'RN-58 repetir un repuesto reemplaza la cantidad en lugar de duplicar la linea'
EXECUTE tx_guardar_linea(:'c_id_publico', :'rep_ngk', 4);
SELECT count(*) = 2 AND max(d.cantidad) FILTER (WHERE d.repuesto_id = :rep_ngk_id) = 4 AS ok
FROM   cotizacion_detalle d WHERE d.cotizacion_id = :cot \gset
\ir incluir/afirmar.sql

\set prueba 'RE007 cerrar con una version distinta de la actual'
\set esperado RE007
EXECUTE tx_cerrar_cotizacion(:'c_id_publico', 99);
\ir incluir/error.sql

-- Cierre por UPDATE directo, intentando antedatarlo.
UPDATE cotizacion SET cerrada_en = '2001-01-01 00:00:00+00', vigente = true WHERE id = :cot;

\set prueba 'RN-54 al cerrar, el trigger fija cerrada_en = hora del servidor y total = suma del detalle'
SELECT c.cerrada_en = now() AND c.vigente AND c.version = 2
       AND c.total = (SELECT sum(d.cantidad::bigint * d.precio_unitario) FROM cotizacion_detalle d WHERE d.cotizacion_id = c.id)
       AND c.total = 4 * 11687 + 23387 AS ok
FROM   cotizacion c WHERE c.id = :cot \gset
\ir incluir/afirmar.sql

\set prueba 'Cerrar una cotizacion ya cerrada la devuelve sin cambios (idempotente)'
EXECUTE tx_cerrar_cotizacion(:'c_id_publico', NULL) \gset z_
SELECT :z_version = 2 AND :z_total = 4 * 11687 + 23387 AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'RN-55 cotizacion cerrada: no admite lineas nuevas'
\set esperado RE003
EXECUTE tx_guardar_linea(:'c_id_publico', :'rep_bob', 2);
\ir incluir/error.sql

\set prueba 'RN-55 cotizacion cerrada: no admite cambiar cantidades'
\set esperado RE003
UPDATE cotizacion_detalle SET cantidad = 9 WHERE cotizacion_id = :cot;
\ir incluir/error.sql

\set prueba 'RN-55 cotizacion cerrada: no admite borrar lineas'
\set esperado RE003
EXECUTE tx_quitar_linea(:'c_id_publico', :'rep_ngk');
\ir incluir/error.sql

\set prueba 'RN-55 cotizacion cerrada: no se puede reabrir'
\set esperado RE003
UPDATE cotizacion SET cerrada_en = NULL WHERE id = :cot;
\ir incluir/error.sql

\set prueba 'RN-55 cotizacion cerrada: no se puede cambiar la fecha de cierre'
\set esperado RE003
UPDATE cotizacion SET cerrada_en = now() - interval '1 day' WHERE id = :cot;
\ir incluir/error.sql

-- ---------------------------------------------------- cotizado y revisiones
EXECUTE tx_cambiar_estado(:'s_id_publico', 'cotizado', 2) \gset e_

\set prueba 'RN-33 pendiente -> cotizado fija cotizada_en e incrementa la version'
SELECT s.estado = 'cotizado' AND s.cotizada_en = now() AND s.completada_en IS NULL AND s.version = 3 AS ok
FROM   sesion_diagnostico s WHERE s.id = :ses \gset
\ir incluir/afirmar.sql

\set prueba 'RN-30 cotizado -> pendiente es una transicion invalida'
\set esperado RE001
EXECUTE tx_cambiar_estado(:'s_id_publico', 'pendiente', NULL);
\ir incluir/error.sql

EXECUTE tx_crear_cotizacion(:'s_id_publico', 'cccccccc-0000-4000-8000-000000000003') \gset c2_
EXECUTE tx_guardar_linea(:'c2_id_publico', :'rep_ngk', 4);
EXECUTE tx_cerrar_cotizacion(:'c2_id_publico', :c2_version) \gset z2_

\set prueba 'RN-50 la segunda revision recibe el numero 2'
SELECT :c2_numero_revision = 2 AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'RN-51 al cerrar la revision 2 pasa a ser la unica vigente; la 1 conserva su total'
SELECT count(*) FILTER (WHERE c.vigente) = 1
   AND bool_and(c.vigente = (c.numero_revision = 2))
   AND max(c.total) FILTER (WHERE c.numero_revision = 1) = 4 * 11687 + 23387
   AND max(c.total) FILTER (WHERE c.numero_revision = 2) = 4 * 11687 AS ok
FROM   cotizacion c WHERE c.sesion_id = :ses \gset
\ir incluir/afirmar.sql

\set prueba 'RN-55 la revision reemplazada no puede volver a ser vigente'
\set esperado RE003
UPDATE cotizacion SET vigente = true WHERE id = :cot;
\ir incluir/error.sql

-- ---------------------------------------------- RN-59: cambios del catalogo
\ir incluir/rol_plataforma.sql
UPDATE repuesto SET precio_referencia = precio_referencia * 2, nombre = 'Bujía renombrada' WHERE id = :rep_ngk_id;
UPDATE taller_configuracion SET margen_pct = 80 WHERE taller_id = :taller_1;

\set prueba 'RE012 ni la plataforma puede cambiar la identidad de una cotizacion'
\set esperado RE012
UPDATE cotizacion SET numero_revision = 9 WHERE id = :cot;
\ir incluir/error.sql

\set prueba 'RN-55 ni la plataforma puede cambiar el total de una cotizacion cerrada'
\set esperado RE003
UPDATE cotizacion SET total = 1 WHERE id = :cot;
\ir incluir/error.sql

\ir incluir/rol_mecanico_1.sql

\set prueba 'RN-59 cambiar el precio maestro, el nombre o el margen no altera lo ya cotizado'
SELECT bool_and(d.precio_unitario = 11687 AND d.nombre_snapshot = 'Bujía de iridio NGK Laser' AND d.margen_pct_snapshot = 30.00)
   AND (SELECT sum(c.total) FROM cotizacion c WHERE c.sesion_id = :ses) = (4 * 11687 + 23387) + 4 * 11687 AS ok
FROM   cotizacion_detalle d
WHERE  d.repuesto_id = :rep_ngk_id AND d.cotizacion_id IN (SELECT c.id FROM cotizacion c WHERE c.sesion_id = :ses) \gset
\ir incluir/afirmar.sql

\ir incluir/rol_plataforma.sql
UPDATE repuesto SET precio_referencia = precio_referencia / 2, nombre = 'Bujía de iridio NGK Laser' WHERE id = :rep_ngk_id;
UPDATE taller_configuracion SET margen_pct = 30 WHERE taller_id = :taller_1;
\ir incluir/rol_mecanico_1.sql

-- --------------------------------------------------------------- terminales
\set prueba 'RE007 completar con la version que el cliente vio antes de cotizar'
\set esperado RE007
EXECUTE tx_cambiar_estado(:'s_id_publico', 'completado', 2);
\ir incluir/error.sql

EXECUTE tx_cambiar_estado(:'s_id_publico', 'completado', 3);

\set prueba 'RN-33 cotizado -> completado fija completada_en y conserva cotizada_en'
SELECT s.estado = 'completado' AND s.completada_en = now() AND s.cotizada_en IS NOT NULL
       AND s.cancelada_en IS NULL AND s.version = 4 AS ok
FROM   sesion_diagnostico s WHERE s.id = :ses \gset
\ir incluir/afirmar.sql

\set prueba 'RN-31 completado -> cancelado se rechaza (estado terminal)'
\set esperado RE001
EXECUTE tx_cambiar_estado(:'s_id_publico', 'cancelado', NULL);
\ir incluir/error.sql

\set prueba 'RN-31 completado -> cotizado se rechaza (estado terminal)'
\set esperado RE001
EXECUTE tx_cambiar_estado(:'s_id_publico', 'cotizado', NULL);
\ir incluir/error.sql

\set prueba 'RN-34 una sesion completada no admite cotizaciones nuevas'
\set esperado RE004
EXECUTE tx_crear_cotizacion(:'s_id_publico', 'cccccccc-0000-4000-8000-000000000004');
\ir incluir/error.sql

-- Segunda sesion: se cancela con un borrador abierto.
EXECUTE tx_crear_sesion(:'veh', NULL, 150200, '[{"codigo": "P0300"}]') \gset t_
EXECUTE tx_crear_cotizacion(:'t_id_publico', 'cccccccc-0000-4000-8000-000000000005') \gset c3_
EXECUTE tx_guardar_linea(:'c3_id_publico', :'rep_ngk', 1);
EXECUTE tx_cambiar_estado(:'t_id_publico', 'cancelado', 1);

\set prueba 'RN-30 pendiente -> cancelado fija cancelada_en y deja cotizada_en vacio'
SELECT s.estado = 'cancelado' AND s.cancelada_en = now() AND s.cotizada_en IS NULL AND s.completada_en IS NULL AS ok
FROM   sesion_diagnostico s WHERE s.id_publico = :'t_id_publico' \gset
\ir incluir/afirmar.sql

\set prueba 'RE004 el borrador de una sesion cancelada no se puede cerrar'
\set esperado RE004
EXECUTE tx_cerrar_cotizacion(:'c3_id_publico', NULL);
\ir incluir/error.sql

\set prueba 'RN-31 cancelado -> pendiente se rechaza (estado terminal)'
\set esperado RE001
EXECUTE tx_cambiar_estado(:'t_id_publico', 'pendiente', NULL);
\ir incluir/error.sql

\set prueba 'RN-30 cotizado -> cancelado esta permitido y conserva cotizada_en (dato de las semillas)'
SELECT count(*) >= 1 AS ok
FROM   sesion_diagnostico s
WHERE  s.estado = 'cancelado' AND s.cotizada_en IS NOT NULL AND s.cancelada_en IS NOT NULL \gset
\ir incluir/afirmar.sql

\set prueba 'RN-32 toda sesion cotizada o completada tiene exactamente una cotizacion vigente cerrada'
SELECT count(*) > 0 AND bool_and((SELECT count(*) FROM cotizacion c
                                  WHERE c.sesion_id = s.id AND c.vigente AND c.cerrada_en IS NOT NULL) = 1) AS ok
FROM   sesion_diagnostico s WHERE s.estado IN ('cotizado', 'completado') \gset
\ir incluir/afirmar.sql

\set prueba 'RE006 crear una cotizacion sin contexto de taller'
EXECUTE ctx('', '', '', '') \gset ctx_
\set esperado RE006
SELECT fn_crear_cotizacion(:ses, 'cccccccc-0000-4000-8000-000000000006');
\ir incluir/error.sql

\set prueba 'RE009 cerrar una cotizacion inexistente'
\ir incluir/rol_mecanico_1.sql
\set esperado RE009
SELECT fn_cerrar_cotizacion(999999999);
\ir incluir/error.sql

ROLLBACK;

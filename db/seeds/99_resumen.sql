-- =============================================================================
-- Semilla 99 - Verificacion y resumen de la carga (no inserta nada).
-- Si una comprobacion falla, la carga termina con error.
-- =============================================================================
\encoding UTF8
\pset pager off

DO $verificacion$
DECLARE
  v_n bigint;
BEGIN
  -- Toda linea cotizada debe ser de un repuesto compatible con el vehiculo.
  SELECT count(*) INTO v_n
  FROM   cotizacion_detalle d
  JOIN   cotizacion c         ON c.id = d.cotizacion_id
  JOIN   sesion_diagnostico s ON s.id = c.sesion_id
  JOIN   vehiculo v           ON v.id = s.vehiculo_id
  WHERE  NOT EXISTS (
           SELECT 1
           FROM   compatibilidad_repuesto k
           WHERE  k.repuesto_id = d.repuesto_id
           AND    k.modelo_vehiculo_id = v.modelo_vehiculo_id
           AND    v.anio BETWEEN k.anio_desde AND k.anio_hasta);
  IF v_n > 0 THEN
    RAISE EXCEPTION 'semillas: % linea(s) cotizan un repuesto incompatible con el vehiculo', v_n;
  END IF;

  -- Toda linea cotizada debe ser de un componente asociado a algun DTC de la sesion.
  SELECT count(*) INTO v_n
  FROM   cotizacion_detalle d
  JOIN   cotizacion c ON c.id = d.cotizacion_id
  WHERE  NOT EXISTS (
           SELECT 1
           FROM   falla_sesion f
           JOIN   v_dtc_repuesto x ON x.dtc_id = f.dtc_id
           WHERE  f.sesion_id = c.sesion_id
           AND    x.repuesto_id = d.repuesto_id);
  IF v_n > 0 THEN
    RAISE EXCEPTION 'semillas: % linea(s) cotizan un repuesto ajeno a las fallas de la sesion', v_n;
  END IF;

  -- Todo usuario tiene credencial.
  SELECT count(*) INTO v_n
  FROM   usuario u
  WHERE  NOT EXISTS (SELECT 1 FROM usuario_credencial c WHERE c.usuario_id = u.id);
  IF v_n > 0 THEN
    RAISE EXCEPTION 'semillas: % usuario(s) sin credencial', v_n;
  END IF;

  -- La auditoria no contiene columnas enmascaradas.
  SELECT count(*) INTO v_n
  FROM   auditoria_operacion a
  WHERE  (a.tabla = 'titular'      AND (COALESCE(a.datos_nuevos, '{}') || COALESCE(a.datos_anteriores, '{}')) ?| ARRAY['nombre', 'telefono', 'email', 'identificador_hmac'])
  OR     (a.tabla = 'vehiculo'     AND (COALESCE(a.datos_nuevos, '{}') || COALESCE(a.datos_anteriores, '{}')) ?| ARRAY['patente', 'vin'])
  OR     (a.tabla = 'usuario'      AND (COALESCE(a.datos_nuevos, '{}') || COALESCE(a.datos_anteriores, '{}')) ?| ARRAY['email', 'nombre'])
  OR     (a.tabla = 'falla_sesion' AND (COALESCE(a.datos_nuevos, '{}') || COALESCE(a.datos_anteriores, '{}')) ?  'freeze_frame');
  IF v_n > 0 THEN
    RAISE EXCEPTION 'semillas: % registro(s) de auditoria con datos personales', v_n;
  END IF;
END;
$verificacion$;

\echo '--- Catalogos globales ---'
SELECT (SELECT count(*) FROM marca_vehiculo)          AS marcas,
       (SELECT count(*) FROM modelo_vehiculo)         AS modelos,
       (SELECT count(*) FROM dtc_catalogo)            AS dtc,
       (SELECT count(*) FROM componente_repuesto)     AS componentes,
       (SELECT count(*) FROM dtc_componente)          AS dtc_componente,
       (SELECT count(*) FROM repuesto)                AS repuestos,
       (SELECT count(*) FROM compatibilidad_repuesto) AS compatibilidades;

\echo '--- Repuestos por perfil ---'
SELECT perfil, count(*) AS repuestos, count(*) FILTER (WHERE NOT disponible) AS no_disponibles
FROM   repuesto
GROUP  BY perfil
ORDER  BY CASE perfil WHEN 'genuino' THEN 1 WHEN 'oem' THEN 2 ELSE 3 END;

\echo '--- Por taller ---'
SELECT t.nombre AS taller,
       tc.margen_pct,
       (SELECT count(*) FROM usuario u WHERE u.taller_id = t.id)                  AS usuarios,
       (SELECT count(*) FROM dispositivo_diagnostico d WHERE d.taller_id = t.id)  AS dispositivos,
       (SELECT count(*) FROM titular x WHERE x.taller_id = t.id)                  AS titulares,
       (SELECT count(*) FROM vehiculo v WHERE v.taller_id = t.id)                 AS vehiculos,
       (SELECT count(*) FROM sesion_diagnostico s WHERE s.taller_id = t.id)       AS sesiones,
       (SELECT count(*) FROM falla_sesion f WHERE f.taller_id = t.id)             AS fallas,
       (SELECT count(*) FROM cotizacion c WHERE c.taller_id = t.id)               AS cotizaciones,
       (SELECT count(*) FROM cotizacion_detalle d WHERE d.taller_id = t.id)       AS lineas,
       (SELECT count(*) FROM auditoria_operacion a WHERE a.taller_id = t.id)      AS auditoria
FROM   taller t
JOIN   taller_configuracion tc ON tc.taller_id = t.id
ORDER  BY t.id;

\echo '--- Sesiones por taller y estado ---'
SELECT t.nombre AS taller, s.estado, count(*) AS sesiones
FROM   sesion_diagnostico s
JOIN   taller t ON t.id = s.taller_id
GROUP  BY t.id, t.nombre, s.estado
ORDER  BY t.id, s.estado;

\echo '--- Cotizaciones ---'
SELECT t.nombre AS taller,
       count(*)                                    AS cotizaciones,
       count(*) FILTER (WHERE c.vigente)           AS vigentes,
       count(*) FILTER (WHERE c.cerrada_en IS NULL) AS borradores,
       sum(c.total) FILTER (WHERE c.vigente)       AS total_vigente
FROM   cotizacion c
JOIN   taller t ON t.id = c.taller_id
GROUP  BY t.id, t.nombre
ORDER  BY t.id;

\echo '--- Titulares por estado de tratamiento ---'
SELECT t.nombre AS taller, x.estado_tratamiento, count(*) AS titulares,
       count(*) FILTER (WHERE x.nombre IS NULL) AS sin_nombre
FROM   titular x
JOIN   taller t ON t.id = x.taller_id
GROUP  BY t.id, t.nombre, x.estado_tratamiento
ORDER  BY t.id, x.estado_tratamiento;

\echo '--- Auditoria por operacion, rol y resultado ---'
SELECT operacion, rol, resultado, count(*) AS registros
FROM   auditoria_operacion
GROUP  BY operacion, rol, resultado
ORDER  BY operacion, rol, resultado;

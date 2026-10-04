-- =============================================================================
-- q05 - Matriz comparativa de repuestos de una sesion.
--                                                        roles: admin, mecanico, auditor
-- GET /sessions/{sesion}/matrix
--   $1 id_publico de la sesion
--
-- Una fila por (componente, repuesto):
--   * fallas de la sesion -> componentes (dtc_componente). Un componente
--     asociado a varios DTC de la misma sesion aparece UNA vez, con la lista de
--     codigos (dtc_codigos) y la severidad mas alta entre ellos.
--   * por componente, sus repuestos disponibles y compatibles con el modelo y
--     el anio del vehiculo (RN-44). EXISTS: rangos solapados no duplican filas.
--   * precio_venta = ROUND(precio_referencia * (1 + margen_pct / 100)) con el
--     margen ACTUAL del taller (RN-45). El precio_referencia no se devuelve.
--   * orden (RN-43): severidad, componente, perfil genuino -> oem -> generico
--     con CASE explicito, precio, id.
--
-- Casos sin filas (no son errores): la sesion no existe o es de otro taller; el
-- vehiculo no es visible para el rol (titular bloqueado o anonimizado); ningun
-- DTC tiene componente asociado; ningun repuesto es compatible.
-- =============================================================================
PREPARE q_matriz (uuid) AS
WITH sesion AS (
  SELECT s.id, s.taller_id, v.modelo_vehiculo_id, v.anio
  FROM   sesion_diagnostico s
  JOIN   vehiculo v ON v.id = s.vehiculo_id AND v.taller_id = s.taller_id
  WHERE  s.id_publico = $1
),
componente AS (
  SELECT dc.componente_id,
         array_agg(d.codigo ORDER BY d.codigo) AS dtc_codigos,
         max(f.severidad)                      AS severidad_maxima
  FROM   sesion x
  JOIN   falla_sesion f    ON f.sesion_id = x.id
  JOIN   dtc_catalogo d    ON d.id = f.dtc_id
  JOIN   dtc_componente dc ON dc.dtc_id = f.dtc_id
  GROUP  BY dc.componente_id
)
SELECT c.id_publico  AS componente_id_publico,
       c.nombre      AS componente_nombre,
       k.dtc_codigos,
       k.severidad_maxima,
       r.id_publico,
       r.perfil,
       r.marca,
       r.nombre,
       r.codigo_fabricante,
       r.durabilidad_estimada_km,
       r.riesgo,
       ROUND(r.precio_referencia * (1 + tc.margen_pct / 100))::bigint AS precio_venta,
       tc.moneda
FROM   sesion x
JOIN   taller_configuracion tc ON tc.taller_id = x.taller_id
CROSS  JOIN componente k
JOIN   componente_repuesto c   ON c.id = k.componente_id
JOIN   repuesto r              ON r.componente_id = k.componente_id
WHERE  r.disponible
AND    EXISTS (
         SELECT 1
         FROM   compatibilidad_repuesto cr
         WHERE  cr.repuesto_id = r.id
         AND    cr.modelo_vehiculo_id = x.modelo_vehiculo_id
         AND    x.anio BETWEEN cr.anio_desde AND cr.anio_hasta)
ORDER  BY k.severidad_maxima DESC, c.nombre, c.id,
          CASE r.perfil WHEN 'genuino' THEN 1 WHEN 'oem' THEN 2 WHEN 'generico' THEN 3 END,
          precio_venta, r.id;

-- =============================================================================
-- q02 - Configuracion del taller y catalogos globales.
--
-- Ninguna consulta filtra por taller_id: el aislamiento lo aplica RLS con el
-- contexto de la peticion. Sin contexto devuelven cero filas (fallan cerrado).
-- Las columnas de otras tablas llevan el prefijo de su entidad
-- (modelo_nombre, marca_nombre, ...); las propias van sin prefijo.
-- =============================================================================

-- GET /settings                                      roles: admin, mecanico, auditor
-- Una fila: el taller del contexto.
PREPARE q_configuracion AS
SELECT t.id_publico,
       t.nombre,
       tc.moneda,
       tc.tema,
       tc.margen_pct,
       tc.retencion_anios,
       tc.actualizado_en
FROM   taller t
JOIN   taller_configuracion tc ON tc.taller_id = t.id;

-- GET /catalog/brands                                roles: admin, mecanico, auditor
PREPARE q_marcas AS
SELECT m.id_publico,
       m.nombre
FROM   marca_vehiculo m
ORDER  BY m.nombre, m.id;

-- GET /catalog/brands/{marca}/models                 roles: admin, mecanico, auditor
--   $1 id_publico de la marca
PREPARE q_modelos (uuid) AS
SELECT mo.id_publico,
       mo.nombre
FROM   modelo_vehiculo mo
JOIN   marca_vehiculo  ma ON ma.id = mo.marca_vehiculo_id
WHERE  ma.id_publico = $1
ORDER  BY mo.nombre, mo.id;

-- GET /catalog/dtc?q=P03                             roles: admin, mecanico, auditor
--   $1 prefijo del codigo (la API lo pasa a mayusculas), $2 limite
-- componentes = cuantos componentes puede sugerir la matriz para ese codigo.
PREPARE q_dtc_buscar (text, integer) AS
SELECT d.codigo,
       d.descripcion,
       d.severidad_sugerida,
       (SELECT count(*) FROM dtc_componente dc WHERE dc.dtc_id = d.id) AS componentes
FROM   dtc_catalogo d
WHERE  d.codigo LIKE $1 || '%'
ORDER  BY d.codigo
LIMIT  $2;

-- GET /catalog/dtc/{codigo}/parts?model=&year=       roles: admin, mecanico, auditor
--   $1 codigo DTC, $2 id_publico del modelo (opcional), $3 anio (opcional)
-- Consulta de catalogo sin sesion: que repuestos resuelven un DTC. Usa la vista
-- v_dtc_repuesto (DTC -> componente -> repuesto). Con modelo y anio aplica la
-- compatibilidad (RN-44); sin ellos lista todo lo disponible.
-- Orden RN-43: componente, perfil (genuino, oem, generico), precio, id.
PREPARE q_repuestos_por_dtc (text, uuid, smallint) AS
SELECT c.id_publico  AS componente_id_publico,
       c.nombre      AS componente_nombre,
       r.id_publico,
       r.perfil,
       r.marca,
       r.nombre,
       r.codigo_fabricante,
       r.durabilidad_estimada_km,
       r.riesgo,
       ROUND(r.precio_referencia * (1 + tc.margen_pct / 100))::bigint AS precio_venta,
       tc.moneda
FROM   dtc_catalogo d
JOIN   v_dtc_repuesto x      ON x.dtc_id = d.id
JOIN   componente_repuesto c ON c.id = x.componente_id
JOIN   repuesto r            ON r.id = x.repuesto_id
CROSS  JOIN taller_configuracion tc
WHERE  d.codigo = $1
AND    r.disponible
AND    ($2::uuid IS NULL OR EXISTS (
         SELECT 1
         FROM   compatibilidad_repuesto k
         JOIN   modelo_vehiculo mo ON mo.id = k.modelo_vehiculo_id
         WHERE  k.repuesto_id = r.id
         AND    mo.id_publico = $2
         AND    ($3::smallint IS NULL OR $3 BETWEEN k.anio_desde AND k.anio_hasta)))
ORDER  BY c.nombre, c.id,
          CASE r.perfil WHEN 'genuino' THEN 1 WHEN 'oem' THEN 2 WHEN 'generico' THEN 3 END,
          precio_venta, r.id;

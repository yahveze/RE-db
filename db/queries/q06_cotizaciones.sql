-- =============================================================================
-- q06 - Cotizaciones de una sesion.                     roles: admin, mecanico, auditor
-- =============================================================================

-- GET /sessions/{sesion}/quotes
--   $1 id_publico de la sesion. Una fila por revision, la mas reciente primero.
-- total es el valor CONGELADO al cerrar (NULL en un borrador); total_calculado
-- se suma del detalle y sirve para mostrar el avance de un borrador. En una
-- cotizacion cerrada ambos coinciden.
PREPARE q_cotizaciones_sesion (uuid) AS
SELECT c.id_publico,
       c.numero_revision,
       c.vigente,
       c.cerrada_en,
       c.total,
       c.moneda,
       c.version,
       c.creado_en,
       d.lineas,
       d.total_calculado
FROM   sesion_diagnostico s
JOIN   cotizacion c ON c.sesion_id = s.id AND c.taller_id = s.taller_id
CROSS  JOIN LATERAL (
         SELECT count(*) AS lineas,
                COALESCE(sum(x.cantidad::bigint * x.precio_unitario), 0)::bigint AS total_calculado
         FROM   cotizacion_detalle x
         WHERE  x.cotizacion_id = c.id) d
WHERE  s.id_publico = $1
ORDER  BY c.numero_revision DESC;

-- GET /quotes/{cotizacion}/lines
--   $1 id_publico de la cotizacion
-- Devuelve el snapshot (nombre, marca, perfil y precio del momento de cotizar),
-- no el catalogo actual: un cambio posterior del precio maestro o del margen no
-- altera lo cotizado (RN-59).
PREPARE q_cotizacion_detalle (uuid) AS
SELECT r.id_publico AS repuesto_id_publico,
       d.nombre_snapshot,
       d.marca_snapshot,
       d.perfil_snapshot,
       d.cantidad,
       d.precio_unitario,
       d.cantidad::bigint * d.precio_unitario AS subtotal,
       c.moneda
FROM   cotizacion c
JOIN   cotizacion_detalle d ON d.cotizacion_id = c.id AND d.taller_id = c.taller_id
JOIN   repuesto r           ON r.id = d.repuesto_id
WHERE  c.id_publico = $1
ORDER  BY CASE d.perfil_snapshot WHEN 'genuino' THEN 1 WHEN 'oem' THEN 2 WHEN 'generico' THEN 3 END,
          d.nombre_snapshot, d.repuesto_id;

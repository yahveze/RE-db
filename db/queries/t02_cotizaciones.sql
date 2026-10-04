-- =============================================================================
-- t02 - Escrituras de cotizacion.                       rol: mecanico
-- =============================================================================

-- POST /sessions/{sesion}/quotes      (cabecera Idempotency-Key)
--   $1 id_publico de la sesion, $2 clave de idempotencia generada por el cliente
-- Crea un borrador. Reintentar con la misma clave devuelve la MISMA cotizacion.
-- sesion_id_publico es el de la cotizacion devuelta: si no coincide con $1, la
-- clave ya se uso para otra sesion y la API responde 409.
-- Errores: RE004 sesion en estado terminal; 23505 (uq_cotizacion_sesion_abierta)
-- si la sesion ya tiene OTRO borrador abierto.
PREPARE tx_crear_cotizacion (uuid, uuid) AS
SELECT c.id_publico,
       c.numero_revision,
       c.vigente,
       c.cerrada_en,
       c.total,
       c.moneda,
       c.version,
       p.id_publico AS sesion_id_publico
FROM   sesion_diagnostico s
CROSS  JOIN LATERAL fn_crear_cotizacion(s.id, $2) c
JOIN   sesion_diagnostico p ON p.id = c.sesion_id
WHERE  s.id_publico = $1;

-- PUT /quotes/{cotizacion}/lines/{repuesto}
--   $1 id_publico de la cotizacion, $2 id_publico del repuesto, $3 cantidad
-- Agrega la linea o, si el repuesto ya esta, reemplaza su cantidad (PUT es
-- idempotente). El cliente NO envia precios: el trigger copia nombre, marca,
-- perfil y precio del catalogo, toma el margen del taller y calcula
-- precio_unitario. Cero filas = cotizacion o repuesto inexistente (404).
-- Errores: RE003 cotizacion cerrada, RE010 repuesto no disponible, 23514
-- cantidad <= 0.
PREPARE tx_guardar_linea (uuid, uuid, integer) AS
WITH linea AS (
  INSERT INTO cotizacion_detalle AS d (cotizacion_id, repuesto_id, taller_id, cantidad)
  SELECT c.id, r.id, c.taller_id, $3
  FROM   cotizacion c
  CROSS  JOIN repuesto r
  WHERE  c.id_publico = $1
  AND    r.id_publico = $2
  ON CONFLICT (cotizacion_id, repuesto_id) DO UPDATE SET cantidad = EXCLUDED.cantidad
  RETURNING d.repuesto_id, d.nombre_snapshot, d.marca_snapshot, d.perfil_snapshot, d.cantidad, d.precio_unitario
)
SELECT r.id_publico AS repuesto_id_publico,
       l.nombre_snapshot,
       l.marca_snapshot,
       l.perfil_snapshot,
       l.cantidad,
       l.precio_unitario,
       l.cantidad::bigint * l.precio_unitario AS subtotal
FROM   linea l
JOIN   repuesto r ON r.id = l.repuesto_id;

-- DELETE /quotes/{cotizacion}/lines/{repuesto}
--   $1 id_publico de la cotizacion, $2 id_publico del repuesto
-- Unico DELETE del modelo. Cero filas = la linea no existia. RE003 si esta cerrada.
PREPARE tx_quitar_linea (uuid, uuid) AS
DELETE FROM cotizacion_detalle d
USING  cotizacion c, repuesto r
WHERE  c.id = d.cotizacion_id
AND    r.id = d.repuesto_id
AND    c.id_publico = $1
AND    r.id_publico = $2
RETURNING r.id_publico AS repuesto_id_publico, d.cantidad;

-- POST /quotes/{cotizacion}/close
--   $1 id_publico de la cotizacion, $2 version que vio el cliente (opcional)
-- Delega en fn_cerrar_cotizacion: bloquea sesion -> cotizacion, apaga la
-- vigente anterior, congela total y cerrada_en (hora del servidor) y la marca
-- vigente. Cerrar una cotizacion ya cerrada la devuelve sin cambios.
-- Errores: RE008 sin detalle, RE004 sesion terminal, RE007 version distinta.
PREPARE tx_cerrar_cotizacion (uuid, integer) AS
SELECT x.id_publico,
       x.numero_revision,
       x.vigente,
       x.cerrada_en,
       x.total,
       x.moneda,
       x.version
FROM   cotizacion c
CROSS  JOIN LATERAL fn_cerrar_cotizacion(c.id, $2) x
WHERE  c.id_publico = $1;

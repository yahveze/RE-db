-- =============================================================================
-- q04 - Historial y detalle de sesiones.                roles: admin, mecanico, auditor
--
-- LEFT JOIN hacia vehiculo: el mecanico no ve vehiculos anonimizados ni de
-- titulares bloqueados, pero la sesion sigue en su historial. En ese caso las
-- columnas vehiculo_*, modelo_* y marca_* llegan en NULL (la API muestra
-- "vehiculo no disponible").
-- =============================================================================

-- GET /history?status=&cursor=&limit=
-- Cuatro sentencias con las MISMAS columnas de salida; la API elige una segun
-- vengan o no el estado y el cursor:
--   q_historial                    (limite)
--   q_historial_siguiente          (cursor_fecha, cursor_id, limite)
--   q_historial_estado             (estado, limite)
--   q_historial_estado_siguiente   (estado, cursor_fecha, cursor_id, limite)
-- cursor = iniciada_en e id_publico de la ULTIMA fila de la pagina anterior.
-- La API pide limite + 1 para saber si hay mas paginas.
--
-- Paginacion por clave (keyset) sobre (iniciada_en DESC, id DESC): no usa
-- OFFSET, asi que el costo de una pagina no crece con su posicion y no se
-- saltan ni repiten filas si entran sesiones nuevas. El desempate usa el id
-- interno, pero el cursor que viaja al cliente lleva el id_publico.
--
-- Por que cuatro sentencias y no una con parametros opcionales. La version
-- inicial tenia "($1 IS NULL OR estado = $1) AND ($2 IS NULL OR (iniciada_en,
-- id) < ...)". Medida con volumen (docs/evidencia/rendimiento.md), tras cinco
-- ejecuciones PostgreSQL adopta el plan generico, en el que esas condiciones
-- son un FILTRO y no una condicion de indice: para servir una pagina profunda
-- leia y descartaba todas las filas anteriores. Sin parametros opcionales la
-- comparacion de fila entra siempre como condicion del indice.
-- Indices: ix_sesion_diagnostico_historial (sin estado) e
-- ix_sesion_diagnostico_estado (con estado).
PREPARE q_historial (integer) AS
SELECT s.id_publico,
       s.estado,
       s.iniciada_en,
       s.metodo_ingreso,
       s.kilometraje,
       s.version,
       v.id_publico      AS vehiculo_id_publico,
       v.patente         AS vehiculo_patente,
       v.anio            AS vehiculo_anio,
       mo.nombre         AS modelo_nombre,
       ma.nombre         AS marca_nombre,
       u.nombre          AS usuario_nombre,
       f.fallas,
       f.severidad_maxima,
       c.total           AS cotizacion_total,
       c.moneda          AS cotizacion_moneda
FROM   sesion_diagnostico s
JOIN   usuario u               ON u.id = s.usuario_id
LEFT   JOIN vehiculo v         ON v.id = s.vehiculo_id
LEFT   JOIN modelo_vehiculo mo ON mo.id = v.modelo_vehiculo_id
LEFT   JOIN marca_vehiculo  ma ON ma.id = mo.marca_vehiculo_id
LEFT   JOIN cotizacion c       ON c.sesion_id = s.id AND c.vigente
CROSS  JOIN LATERAL (
         SELECT count(*) AS fallas, max(x.severidad) AS severidad_maxima
         FROM   falla_sesion x
         WHERE  x.sesion_id = s.id) f
ORDER  BY s.iniciada_en DESC, s.id DESC
LIMIT  $1;

PREPARE q_historial_siguiente (timestamptz, uuid, integer) AS
SELECT s.id_publico,
       s.estado,
       s.iniciada_en,
       s.metodo_ingreso,
       s.kilometraje,
       s.version,
       v.id_publico      AS vehiculo_id_publico,
       v.patente         AS vehiculo_patente,
       v.anio            AS vehiculo_anio,
       mo.nombre         AS modelo_nombre,
       ma.nombre         AS marca_nombre,
       u.nombre          AS usuario_nombre,
       f.fallas,
       f.severidad_maxima,
       c.total           AS cotizacion_total,
       c.moneda          AS cotizacion_moneda
FROM   sesion_diagnostico s
JOIN   usuario u               ON u.id = s.usuario_id
LEFT   JOIN vehiculo v         ON v.id = s.vehiculo_id
LEFT   JOIN modelo_vehiculo mo ON mo.id = v.modelo_vehiculo_id
LEFT   JOIN marca_vehiculo  ma ON ma.id = mo.marca_vehiculo_id
LEFT   JOIN cotizacion c       ON c.sesion_id = s.id AND c.vigente
CROSS  JOIN LATERAL (
         SELECT count(*) AS fallas, max(x.severidad) AS severidad_maxima
         FROM   falla_sesion x
         WHERE  x.sesion_id = s.id) f
WHERE  (s.iniciada_en, s.id) < ($1, (SELECT k.id FROM sesion_diagnostico k WHERE k.id_publico = $2))
ORDER  BY s.iniciada_en DESC, s.id DESC
LIMIT  $3;

PREPARE q_historial_estado (tipo_estado_atencion, integer) AS
SELECT s.id_publico,
       s.estado,
       s.iniciada_en,
       s.metodo_ingreso,
       s.kilometraje,
       s.version,
       v.id_publico      AS vehiculo_id_publico,
       v.patente         AS vehiculo_patente,
       v.anio            AS vehiculo_anio,
       mo.nombre         AS modelo_nombre,
       ma.nombre         AS marca_nombre,
       u.nombre          AS usuario_nombre,
       f.fallas,
       f.severidad_maxima,
       c.total           AS cotizacion_total,
       c.moneda          AS cotizacion_moneda
FROM   sesion_diagnostico s
JOIN   usuario u               ON u.id = s.usuario_id
LEFT   JOIN vehiculo v         ON v.id = s.vehiculo_id
LEFT   JOIN modelo_vehiculo mo ON mo.id = v.modelo_vehiculo_id
LEFT   JOIN marca_vehiculo  ma ON ma.id = mo.marca_vehiculo_id
LEFT   JOIN cotizacion c       ON c.sesion_id = s.id AND c.vigente
CROSS  JOIN LATERAL (
         SELECT count(*) AS fallas, max(x.severidad) AS severidad_maxima
         FROM   falla_sesion x
         WHERE  x.sesion_id = s.id) f
WHERE  s.estado = $1
ORDER  BY s.iniciada_en DESC, s.id DESC
LIMIT  $2;

PREPARE q_historial_estado_siguiente (tipo_estado_atencion, timestamptz, uuid, integer) AS
SELECT s.id_publico,
       s.estado,
       s.iniciada_en,
       s.metodo_ingreso,
       s.kilometraje,
       s.version,
       v.id_publico      AS vehiculo_id_publico,
       v.patente         AS vehiculo_patente,
       v.anio            AS vehiculo_anio,
       mo.nombre         AS modelo_nombre,
       ma.nombre         AS marca_nombre,
       u.nombre          AS usuario_nombre,
       f.fallas,
       f.severidad_maxima,
       c.total           AS cotizacion_total,
       c.moneda          AS cotizacion_moneda
FROM   sesion_diagnostico s
JOIN   usuario u               ON u.id = s.usuario_id
LEFT   JOIN vehiculo v         ON v.id = s.vehiculo_id
LEFT   JOIN modelo_vehiculo mo ON mo.id = v.modelo_vehiculo_id
LEFT   JOIN marca_vehiculo  ma ON ma.id = mo.marca_vehiculo_id
LEFT   JOIN cotizacion c       ON c.sesion_id = s.id AND c.vigente
CROSS  JOIN LATERAL (
         SELECT count(*) AS fallas, max(x.severidad) AS severidad_maxima
         FROM   falla_sesion x
         WHERE  x.sesion_id = s.id) f
WHERE  s.estado = $1
AND    (s.iniciada_en, s.id) < ($2, (SELECT k.id FROM sesion_diagnostico k WHERE k.id_publico = $3))
ORDER  BY s.iniciada_en DESC, s.id DESC
LIMIT  $4;

-- GET /vehicles/{vehiculo}/sessions                  indice: ix_sesion_diagnostico_vehiculo
--   $1 id_publico del vehiculo, $2 limite
PREPARE q_historial_vehiculo (uuid, integer) AS
SELECT s.id_publico,
       s.estado,
       s.iniciada_en,
       s.kilometraje,
       u.nombre AS usuario_nombre,
       (SELECT count(*) FROM falla_sesion x WHERE x.sesion_id = s.id) AS fallas,
       c.total  AS cotizacion_total,
       c.moneda AS cotizacion_moneda
FROM   vehiculo v
JOIN   sesion_diagnostico s ON s.vehiculo_id = v.id AND s.taller_id = v.taller_id
JOIN   usuario u            ON u.id = s.usuario_id
LEFT   JOIN cotizacion c    ON c.sesion_id = s.id AND c.vigente
WHERE  v.id_publico = $1
ORDER  BY s.iniciada_en DESC, s.id DESC
LIMIT  $2;

-- GET /sessions/{sesion}
--   $1 id_publico de la sesion. Cero filas = 404 (no existe o es de otro taller).
-- version se devuelve para el control optimista del cambio de estado.
PREPARE q_sesion (uuid) AS
SELECT s.id_publico,
       s.estado,
       s.metodo_ingreso,
       s.kilometraje,
       s.iniciada_en,
       s.cotizada_en,
       s.completada_en,
       s.cancelada_en,
       s.version,
       s.actualizado_en,
       v.id_publico      AS vehiculo_id_publico,
       v.patente         AS vehiculo_patente,
       v.vin             AS vehiculo_vin,
       v.anio            AS vehiculo_anio,
       v.motor           AS vehiculo_motor,
       mo.nombre         AS modelo_nombre,
       ma.nombre         AS marca_nombre,
       u.id_publico      AS usuario_id_publico,
       u.nombre          AS usuario_nombre,
       d.id_publico      AS dispositivo_id_publico,
       d.mac             AS dispositivo_mac,
       cv.id_publico     AS cotizacion_vigente_id_publico,
       cv.total          AS cotizacion_vigente_total,
       cb.id_publico     AS cotizacion_borrador_id_publico
FROM   sesion_diagnostico s
JOIN   usuario u                      ON u.id = s.usuario_id
LEFT   JOIN vehiculo v                ON v.id = s.vehiculo_id
LEFT   JOIN modelo_vehiculo mo        ON mo.id = v.modelo_vehiculo_id
LEFT   JOIN marca_vehiculo  ma        ON ma.id = mo.marca_vehiculo_id
LEFT   JOIN dispositivo_diagnostico d ON d.id = s.dispositivo_id
LEFT   JOIN cotizacion cv             ON cv.sesion_id = s.id AND cv.vigente
LEFT   JOIN cotizacion cb             ON cb.sesion_id = s.id AND cb.cerrada_en IS NULL
WHERE  s.id_publico = $1;

-- GET /sessions/{sesion}/faults
--   $1 id_publico de la sesion. Las mas graves primero.
PREPARE q_sesion_fallas (uuid) AS
SELECT d.codigo,
       d.descripcion,
       f.severidad,
       d.severidad_sugerida,
       f.freeze_frame,
       f.creado_en
FROM   sesion_diagnostico s
JOIN   falla_sesion f ON f.sesion_id = s.id
JOIN   dtc_catalogo d ON d.id = f.dtc_id
WHERE  s.id_publico = $1
ORDER  BY f.severidad DESC, d.codigo;

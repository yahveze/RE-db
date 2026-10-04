-- =============================================================================
-- q03 - Busqueda de vehiculos (/search).
--
-- Roles: admin y mecanico. El auditor NO puede ejecutarlas: devuelven
-- titular.nombre, columna sobre la que no tiene privilegio (permission denied).
-- El mecanico solo ve vehiculos no anonimizados y de titulares activos (RLS).
-- =============================================================================

-- GET /search?vin=                                   indice: uq_vehiculo_taller_vin
--   $1 VIN (17 caracteres, mayusculas). Cero o una fila.
PREPARE q_buscar_vehiculo_vin (text) AS
SELECT v.id_publico,
       v.patente,
       v.vin,
       v.anio,
       v.motor,
       mo.id_publico AS modelo_id_publico,
       mo.nombre     AS modelo_nombre,
       ma.nombre     AS marca_nombre,
       t.id_publico  AS titular_id_publico,
       t.nombre      AS titular_nombre,
       (SELECT max(s.iniciada_en) FROM sesion_diagnostico s WHERE s.vehiculo_id = v.id) AS ultima_sesion_en
FROM   vehiculo v
JOIN   modelo_vehiculo mo ON mo.id = v.modelo_vehiculo_id
JOIN   marca_vehiculo  ma ON ma.id = mo.marca_vehiculo_id
LEFT   JOIN titular t     ON t.id = v.titular_id
WHERE  v.vin = $1;

-- GET /search?plate=                                 indice: uq_vehiculo_taller_patente
--   $1 patente (mayusculas, sin separadores). Cero o una fila.
PREPARE q_buscar_vehiculo_patente (text) AS
SELECT v.id_publico,
       v.patente,
       v.vin,
       v.anio,
       v.motor,
       mo.id_publico AS modelo_id_publico,
       mo.nombre     AS modelo_nombre,
       ma.nombre     AS marca_nombre,
       t.id_publico  AS titular_id_publico,
       t.nombre      AS titular_nombre,
       (SELECT max(s.iniciada_en) FROM sesion_diagnostico s WHERE s.vehiculo_id = v.id) AS ultima_sesion_en
FROM   vehiculo v
JOIN   modelo_vehiculo mo ON mo.id = v.modelo_vehiculo_id
JOIN   marca_vehiculo  ma ON ma.id = mo.marca_vehiculo_id
LEFT   JOIN titular t     ON t.id = v.titular_id
WHERE  v.patente = $1;

-- GET /search?model=&year=                           indice: ix_vehiculo_taller_modelo_anio
--   $1 id_publico del modelo, $2 anio (opcional), $3 limite
-- (modelo, anio) no identifica un vehiculo: devuelve una lista para elegir.
PREPARE q_buscar_vehiculo_modelo (uuid, smallint, integer) AS
SELECT v.id_publico,
       v.patente,
       v.vin,
       v.anio,
       v.motor,
       mo.id_publico AS modelo_id_publico,
       mo.nombre     AS modelo_nombre,
       ma.nombre     AS marca_nombre,
       t.id_publico  AS titular_id_publico,
       t.nombre      AS titular_nombre,
       (SELECT max(s.iniciada_en) FROM sesion_diagnostico s WHERE s.vehiculo_id = v.id) AS ultima_sesion_en
FROM   vehiculo v
JOIN   modelo_vehiculo mo ON mo.id = v.modelo_vehiculo_id
JOIN   marca_vehiculo  ma ON ma.id = mo.marca_vehiculo_id
LEFT   JOIN titular t     ON t.id = v.titular_id
WHERE  mo.id_publico = $1
AND    ($2::smallint IS NULL OR v.anio = $2)
ORDER  BY v.anio DESC, v.id DESC
LIMIT  $3;

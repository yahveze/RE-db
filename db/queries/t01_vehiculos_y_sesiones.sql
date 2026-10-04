-- =============================================================================
-- t01 - Escrituras del mecanico: titular, vehiculo, sesion y estado.
--
-- Son las sentencias que componen las transacciones de docs/transacciones.md.
-- taller_id y usuario_id NUNCA vienen del cliente: salen del contexto de la
-- peticion (fn_contexto_*). Los padres se resuelven por id_publico bajo RLS: un
-- id_publico de otro taller no se encuentra y la sentencia devuelve cero filas
-- (la API responde 404) en lugar de tocar datos ajenos.
-- =============================================================================

-- POST /holders                                      roles: admin, mecanico
--   $1 nombre, $2 telefono, $3 email, $4 identificador HMAC (32 bytes, lo
--   calcula el backend; opcional)
-- Un HMAC repetido en el taller viola uq_titular_taller_identificador_hmac
-- (23505): el titular ya existe.
PREPARE tx_crear_titular (text, text, text, bytea) AS
INSERT INTO titular (taller_id, nombre, telefono, email, identificador_hmac)
VALUES (fn_contexto_taller_id(), $1, $2, $3, $4)
RETURNING id_publico, nombre, telefono, email, estado_tratamiento, creado_en;

-- POST /holders/{titular}/consents                   roles: admin, mecanico
--   $1 id_publico del titular, $2 finalidad, $3 version de los terminos, $4 canal
-- Ya existe uno activo para esa finalidad -> 23505 (uq_consentimiento_titular_activo).
PREPARE tx_registrar_consentimiento (uuid, tipo_finalidad_tratamiento, text, text) AS
INSERT INTO consentimiento_titular (taller_id, titular_id, finalidad, version_terminos, canal)
SELECT t.taller_id, t.id, $2, $3, $4
FROM   titular t
WHERE  t.id_publico = $1
RETURNING finalidad, version_terminos, canal, otorgado_en;

-- POST /vehicles                                     roles: admin, mecanico
--   $1 id_publico del titular (opcional), $2 id_publico del modelo, $3 anio,
--   $4 motor, $5 VIN, $6 patente
-- Cero filas si el modelo no existe o si se envio un titular que no es visible:
-- nunca se crea el vehiculo "sin titular" por un id mal escrito.
PREPARE tx_crear_vehiculo (uuid, uuid, smallint, text, text, text) AS
INSERT INTO vehiculo (taller_id, titular_id, modelo_vehiculo_id, anio, motor, vin, patente)
SELECT fn_contexto_taller_id(),
       (SELECT t.id FROM titular t WHERE t.id_publico = $1),
       mo.id, $3, $4, $5, $6
FROM   modelo_vehiculo mo
WHERE  mo.id_publico = $2
AND    ($1::uuid IS NULL OR EXISTS (SELECT 1 FROM titular t WHERE t.id_publico = $1))
RETURNING id_publico, patente, vin, anio, motor, creado_en;

-- POST /sessions                                     rol: mecanico
--   $1 id_publico del vehiculo
--   $2 id_publico del dispositivo (NULL = ingreso manual)
--   $3 kilometraje
--   $4 fallas: arreglo JSON [{"codigo", "severidad"?, "freeze_frame"?}]
-- UNA sentencia crea la sesion y todas sus fallas: es atomica aunque el backend
-- no abriera una transaccion. La sesion nace 'pendiente', a nombre del usuario
-- del contexto (la politica RLS lo exige) y con la hora del servidor.
--   * severidad omitida -> la sugerida por el catalogo.
--   * codigo que no existe en el catalogo -> dtc_id NULL -> 23502, y no se crea
--     nada (LEFT JOIN a proposito: un JOIN lo descartaria en silencio).
--   * dispositivo que no esta 'activo' o no es del taller -> queda NULL con
--     metodo obd_bluetooth -> 23514 (ck_sesion_diagnostico_dispositivo_segun_metodo).
--   * vehiculo no visible -> cero filas (404).
-- fallas_registradas permite a la API comprobar que guardo todas las enviadas.
PREPARE tx_crear_sesion (uuid, uuid, integer, jsonb) AS
WITH nueva AS (
  INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, dispositivo_id, metodo_ingreso, kilometraje)
  SELECT v.taller_id,
         v.id,
         fn_contexto_usuario_id(),
         (SELECT d.id FROM dispositivo_diagnostico d WHERE d.id_publico = $2 AND d.estado = 'activo'),
         CASE WHEN $2::uuid IS NULL THEN 'manual' ELSE 'obd_bluetooth' END::tipo_metodo_ingreso,
         $3
  FROM   vehiculo v
  WHERE  v.id_publico = $1
  RETURNING id, id_publico, taller_id, estado, metodo_ingreso, kilometraje, iniciada_en, version
),
falla AS (
  INSERT INTO falla_sesion (sesion_id, dtc_id, taller_id, severidad, freeze_frame)
  SELECT n.id, d.id, n.taller_id, COALESCE(f.severidad, d.severidad_sugerida, 'media'), f.freeze_frame
  FROM   nueva n
  CROSS  JOIN jsonb_to_recordset($4) AS f (codigo text, severidad tipo_severidad, freeze_frame jsonb)
  LEFT   JOIN dtc_catalogo d ON d.codigo = f.codigo
  RETURNING dtc_id
)
SELECT n.id_publico,
       n.estado,
       n.metodo_ingreso,
       n.kilometraje,
       n.iniciada_en,
       n.version,
       (SELECT count(*) FROM falla) AS fallas_registradas
FROM   nueva n;

-- POST /sessions/{sesion}/status                     rol: mecanico
--   $1 id_publico de la sesion, $2 nuevo estado, $3 version que vio el cliente
-- Delega en fn_cambiar_estado_sesion (bloqueo sesion -> cotizacion, transicion
-- validada por trigger). Cero filas = 404.
-- Errores: RE001 transicion invalida, RE002 falta cotizacion vigente cerrada,
-- RE007 la version cambio (otro usuario modifico la sesion).
PREPARE tx_cambiar_estado (uuid, tipo_estado_atencion, integer) AS
SELECT x.id_publico,
       x.estado,
       x.cotizada_en,
       x.completada_en,
       x.cancelada_en,
       x.version,
       x.actualizado_en
FROM   sesion_diagnostico s
CROSS  JOIN LATERAL fn_cambiar_estado_sesion(s.id, $2, $3) x
WHERE  s.id_publico = $1;

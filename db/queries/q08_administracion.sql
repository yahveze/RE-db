-- =============================================================================
-- q08 - Administracion y auditoria.
-- =============================================================================

-- GET /users                                         roles: admin, auditor
-- (el mecanico no tiene privilegio sobre usuario.email ni creado_en)
PREPARE q_usuarios AS
SELECT u.id_publico,
       u.email,
       u.nombre,
       u.rol,
       u.activo,
       u.creado_en
FROM   usuario u
ORDER  BY u.activo DESC, u.nombre, u.id;

-- GET /devices                                       roles: admin, mecanico, auditor
PREPARE q_dispositivos AS
SELECT d.id_publico,
       d.mac,
       d.estado,
       d.fabricante,
       d.modelo,
       d.firmware,
       d.actualizado_en
FROM   dispositivo_diagnostico d
ORDER  BY CASE d.estado WHEN 'activo' THEN 1 WHEN 'inactivo' THEN 2 WHEN 'baja' THEN 3 END, d.id;

-- GET /privacy/requests                              roles: admin, auditor
-- Sin datos de identidad del titular: sirve igual al auditor.
PREPARE q_solicitudes_derecho AS
SELECT s.id_publico,
       s.tipo,
       s.estado,
       s.recibida_en,
       s.resuelta_en,
       t.id_publico         AS titular_id_publico,
       t.estado_tratamiento AS titular_estado_tratamiento,
       t.bloqueado_hasta    AS titular_bloqueado_hasta,
       u.nombre             AS usuario_responsable_nombre
FROM   solicitud_derecho_titular s
JOIN   titular t      ON t.id = s.titular_id
LEFT   JOIN usuario u ON u.id = s.usuario_responsable_id
ORDER  BY s.recibida_en DESC, s.id DESC;

-- GET /audit?table=&cursor=&limit=                   roles: admin, auditor
--   $1 tabla (opcional)
--   $2, $3 cursor: ocurrido_en e id de la ultima fila de la pagina anterior
--   $4 limite
-- Paginacion por clave sobre ix_auditoria_operacion_taller_fecha.
-- La bitacora es forense: id, registro_id y el contenido de datos_* son ids
-- internos. Es la unica respuesta que los contiene y solo la reciben el
-- administrador y el auditor del taller (tema T-36).
PREPARE q_auditoria (text, timestamptz, bigint, integer) AS
SELECT a.id,
       a.ocurrido_en,
       a.operacion,
       a.tabla,
       a.registro_id,
       a.resultado,
       a.rol,
       u.id_publico AS usuario_id_publico,
       u.nombre     AS usuario_nombre,
       a.ip_origen,
       a.request_id,
       a.datos_anteriores,
       a.datos_nuevos
FROM   auditoria_operacion a
LEFT   JOIN usuario u ON u.id = a.usuario_id
WHERE  ($1::text IS NULL OR a.tabla = $1)
AND    ($2::timestamptz IS NULL OR (a.ocurrido_en, a.id) < ($2, $3))
ORDER  BY a.ocurrido_en DESC, a.id DESC
LIMIT  $4;

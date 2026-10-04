-- =============================================================================
-- q08 - Administracion, privacidad y auditoria.
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

-- GET /holders/{titular}/consents                    roles: admin, mecanico, auditor
--   $1 id_publico del titular. Activos y revocados, el mas reciente primero.
-- No devuelve datos de identidad: sirve igual al auditor. El mecanico solo
-- obtiene filas de titulares que puede ver (RLS).
-- Indice: ix_consentimiento_titular_taller_titular.
PREPARE q_consentimientos_titular (uuid) AS
SELECT c.finalidad,
       c.version_terminos,
       c.canal,
       c.otorgado_en,
       c.revocado_en
FROM   titular t
JOIN   consentimiento_titular c ON c.titular_id = t.id AND c.taller_id = t.taller_id
WHERE  t.id_publico = $1
ORDER  BY c.otorgado_en DESC, c.id DESC;

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
--   q_auditoria            (tabla opcional, limite)
--   q_auditoria_siguiente  (tabla opcional, cursor ocurrido_en, cursor id, limite)
-- Paginacion por clave sobre ix_auditoria_operacion_taller_fecha. El cursor va
-- en una sentencia aparte por la misma razon que en q_historial: como parametro
-- opcional no entraria como condicion del indice en el plan generico. El filtro
-- por tabla si puede ser opcional: no hay indice por tabla, es un filtro en
-- cualquier plan.
-- La bitacora es forense: id, registro_id y el contenido de datos_* son ids
-- internos. Es la unica respuesta que los contiene y solo la reciben el
-- administrador y el auditor del taller (tema T-36).
PREPARE q_auditoria (text, integer) AS
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
ORDER  BY a.ocurrido_en DESC, a.id DESC
LIMIT  $2;

PREPARE q_auditoria_siguiente (text, timestamptz, bigint, integer) AS
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
AND    (a.ocurrido_en, a.id) < ($2, $3)
ORDER  BY a.ocurrido_en DESC, a.id DESC
LIMIT  $4;

-- =============================================================================
-- Semilla 04 - Derechos del titular y accesos.
--
-- La administradora del taller 1 tramita, con su rol y su contexto:
--   * una solicitud de acceso (queda 'recibida');
--   * la supresion de Elena Vargas: tiene una atencion completada dentro del
--     plazo de retencion -> queda 'bloqueado' hasta que venza;
--   * la supresion de Tomas Reyes: su unica atencion fue cancelada, no hay
--     retencion pendiente -> se anonimiza de inmediato (titular y vehiculo).
-- Despues de esto el mecanico deja de ver a ambos titulares y sus vehiculos,
-- pero las sesiones siguen en el historial.
--
-- Al final se registran algunos inicios de sesion (correctos y fallidos) para
-- que la auditoria tenga eventos LOGIN y LOGIN_FALLIDO.
-- =============================================================================
\encoding UTF8
\o /dev/null

SELECT id AS taller_1 FROM taller WHERE nombre = 'Taller Mecánico Los Aromos' \gset
SELECT id AS admin_1 FROM usuario WHERE email = 'admin@losaromos.example' \gset

BEGIN;
SET LOCAL ROLE taller_admin;
SELECT set_config('app.taller_id',  :'taller_1', true),
       set_config('app.usuario_id', :'admin_1',  true),
       set_config('app.ip_origen',  '192.168.10.2', true),
       set_config('app.request_id', 'semilla-04-derechos', true);

INSERT INTO solicitud_derecho_titular (taller_id, titular_id, tipo, usuario_responsable_id, recibida_en)
SELECT :taller_1, t.id, 'acceso', :admin_1, now() - interval '3 days'
FROM   titular t
WHERE  t.nombre = 'Juana Pérez Soto';

SELECT fn_solicitar_supresion_titular(t.id)
FROM   titular t
WHERE  t.nombre IN ('Elena Vargas Mora', 'Tomás Reyes Cid');

COMMIT;

-- Inicios de sesion: ocurren sin contexto de taller, como en el backend.
SELECT autenticado FROM fn_autenticar_usuario('admin@losaromos.example',     :'clave_demo');
SELECT autenticado FROM fn_autenticar_usuario('mecanico1@losaromos.example', :'clave_demo');
SELECT autenticado FROM fn_autenticar_usuario('mecanico@nuble.example',      :'clave_demo');
-- Fallidos: clave incorrecta, usuario dado de baja y email inexistente.
SELECT autenticado FROM fn_autenticar_usuario('mecanico2@losaromos.example',  'clave-incorrecta');
SELECT autenticado FROM fn_autenticar_usuario('exmecanico@losaromos.example', :'clave_demo');
SELECT autenticado FROM fn_autenticar_usuario('nadie@losaromos.example',      'clave-incorrecta');

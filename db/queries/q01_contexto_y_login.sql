-- =============================================================================
-- q01 - Inicio de sesion y contexto de la peticion.
--
-- Todas las sentencias de db/queries/ son PREPARE con parametros $n: es
-- exactamente el texto que envia el backend (nunca se concatena SQL). Los
-- nombres de las columnas de salida son los campos JSON de la respuesta.
--
-- Patron de TODA peticion autenticada (una transaccion por peticion):
--     BEGIN;
--     SET LOCAL ROLE taller_mecanico;      -- o taller_admin / taller_auditor
--     EXECUTE ctx(taller_id, usuario_id, ip, request_id);
--     ... sentencias de la peticion ...
--     COMMIT;
-- SET LOCAL ROLE no admite parametros: el backend elige una de TRES sentencias
-- literales segun el rol que devolvio el login; jamas interpola texto del
-- cliente. SET LOCAL y set_config(..., true) mueren con la transaccion, por lo
-- que el patron es seguro con un pool en modo transaccion.
-- =============================================================================

-- POST /auth/login                                   rol: app_backend_user (sin contexto)
--   $1 email, $2 contrasena
-- Una fila siempre. autenticado = false no distingue el motivo (401).
-- usuario_id y taller_id son ids internos: el backend los guarda en SU sesion
-- para llamar a ctx(); al cliente solo viajan los *_id_publico.
PREPARE q_login (text, text) AS
SELECT a.autenticado,
       a.usuario_id,
       a.usuario_id_publico,
       a.taller_id,
       a.taller_id_publico,
       a.rol,
       a.nombre
FROM   fn_autenticar_usuario($1, $2) a;

-- Contexto de la peticion (despues de SET LOCAL ROLE).
--   $1 taller_id, $2 usuario_id, $3 ip de origen, $4 identificador de la peticion
PREPARE ctx (text, text, text, text) AS
SELECT set_config('app.taller_id',  $1, true) AS taller_id,
       set_config('app.usuario_id', $2, true) AS usuario_id,
       set_config('app.ip_origen',  $3, true) AS ip_origen,
       set_config('app.request_id', $4, true) AS request_id;

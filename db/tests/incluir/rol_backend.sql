-- Conexion del backend SIN asumir un grupo y sin contexto.
RESET ROLE;
SET SESSION AUTHORIZATION app_backend_user;
EXECUTE ctx('', '', '', '') \gset ctx_

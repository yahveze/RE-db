-- Peticion del backend: conexion app_backend_user + SET LOCAL ROLE + contexto.
RESET ROLE;
SET SESSION AUTHORIZATION app_backend_user;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'taller_1', :'mec_1', '192.168.10.21', 'prueba') \gset ctx_

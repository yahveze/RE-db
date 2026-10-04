-- Peticion del backend: conexion app_backend_user + SET LOCAL ROLE + contexto.
RESET ROLE;
SET SESSION AUTHORIZATION app_backend_user;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'taller_2', :'mec_2', '10.20.0.5', 'prueba') \gset ctx_

-- Peticion del backend: conexion app_backend_user + SET LOCAL ROLE + contexto.
RESET ROLE;
SET SESSION AUTHORIZATION app_backend_user;
SET LOCAL ROLE taller_admin;
EXECUTE ctx(:'taller_2', :'admin_2', '10.20.0.2', 'prueba') \gset ctx_

-- Peticion del backend: conexion app_backend_user + SET LOCAL ROLE + contexto.
RESET ROLE;
SET SESSION AUTHORIZATION app_backend_user;
SET LOCAL ROLE taller_admin;
EXECUTE ctx(:'taller_1', :'admin_1', '192.168.10.2', 'prueba') \gset ctx_

-- Peticion del backend: conexion app_backend_user + SET LOCAL ROLE + contexto.
RESET ROLE;
SET SESSION AUTHORIZATION app_backend_user;
SET LOCAL ROLE taller_auditor;
EXECUTE ctx(:'taller_1', :'aud_1', '192.168.10.40', 'prueba') \gset ctx_

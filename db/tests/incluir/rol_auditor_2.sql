-- Peticion del backend: conexion app_backend_user + SET LOCAL ROLE + contexto.
RESET ROLE;
SET SESSION AUTHORIZATION app_backend_user;
SET LOCAL ROLE taller_auditor;
EXECUTE ctx(:'taller_2', :'aud_2', '10.20.0.9', 'prueba') \gset ctx_

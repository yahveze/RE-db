-- =============================================================================
-- V000 - Roles, membresias, extensiones y privilegios base.
-- Se ejecuta como SUPERUSUARIO (es la unica migracion que lo requiere).
-- Requiere la variable psql :'clave_backend' (viene de .env via psql -v).
-- No es re-ejecutable: los roles son globales al cluster. 'make reset' parte
-- de un volumen vacio.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Extensiones
--   pgcrypto            crypt() y gen_salt() para el login de prototipo.
--   pg_stat_statements  observabilidad (ya esta en shared_preload_libraries).
-- gen_random_uuid() es del nucleo desde PostgreSQL 13: no necesita extension.
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- La extension otorga SELECT a PUBLIC sobre sus vistas. Se revoca: las
-- estadisticas de consultas son informacion de operacion, no de los talleres.
REVOKE ALL ON pg_stat_statements, pg_stat_statements_info FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- Roles
-- ----------------------------------------------------------------------------
-- Propietario de tablas, tipos, vistas y migraciones. No se usa en ejecucion.
CREATE ROLE app_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;

-- Propietario SOLO de las funciones SECURITY DEFINER. BYPASSRLS porque con
-- FORCE ROW LEVEL SECURITY ni siquiera el propietario de las tablas las ve sin
-- contexto, y el login ocurre antes de que exista contexto de taller.
CREATE ROLE app_funciones NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS;

-- Grupos: definen QUE operaciones puede hacer cada tipo de usuario (RBAC).
CREATE ROLE taller_admin    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE ROLE taller_mecanico NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
CREATE ROLE taller_auditor  NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;

-- Rol de conexion del backend: sin privilegios propios sobre tablas.
-- La clave se guarda como verificador SCRAM-SHA-256 (password_encryption).
CREATE ROLE app_backend_user LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOINHERIT
  PASSWORD :'clave_backend';

-- ----------------------------------------------------------------------------
-- Membresias (sintaxis PostgreSQL 16)
-- ----------------------------------------------------------------------------
-- El backend puede ASUMIR un grupo con SET LOCAL ROLE (SET TRUE), pero no
-- hereda sus privilegios por defecto (INHERIT FALSE): sin SET LOCAL ROLE no
-- puede leer ni escribir nada.
GRANT taller_admin, taller_mecanico, taller_auditor TO app_backend_user
  WITH INHERIT FALSE, SET TRUE;

-- Para que app_owner pueda ejecutar ALTER FUNCTION ... OWNER TO app_funciones,
-- PostgreSQL exige que pueda hacer SET ROLE al nuevo propietario.
GRANT app_funciones TO app_owner WITH INHERIT FALSE, SET TRUE;

-- ----------------------------------------------------------------------------
-- Base de datos y esquema
-- ----------------------------------------------------------------------------
REVOKE ALL ON DATABASE :"DBNAME" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"DBNAME" TO app_backend_user;

-- Desde PostgreSQL 15 PUBLIC ya no tiene CREATE en public; se revoca todo
-- igualmente para que el acceso al esquema sea explicito.
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO app_owner;
-- CREATE para app_funciones: segundo requisito de ALTER FUNCTION ... OWNER TO
-- (el nuevo propietario debe tener CREATE en el esquema).
GRANT USAGE, CREATE ON SCHEMA public TO app_funciones;
GRANT USAGE ON SCHEMA public TO taller_admin, taller_mecanico, taller_auditor, app_backend_user;

-- Toda funcion que cree app_owner nace sin EXECUTE para PUBLIC: los permisos
-- de ejecucion se otorgan uno a uno en V007.
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

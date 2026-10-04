-- Preambulo comun de la suite. Cada archivo de db/tests/ lo incluye primero.
--   * Las pruebas corren sobre las semillas, dentro de UNA transaccion que el
--     archivo termina con ROLLBACK: la suite no deja cambios.
--   * ON_ERROR_STOP off + ON_ERROR_ROLLBACK on: un error esperado no aborta la
--     transaccion. Para que un error NO esperado no pase inadvertido,
--     run_all.sh exige que el numero de lineas "ERROR:" coincida con el de
--     pruebas de error ([E]).
--   * Resultado de cada prueba: una linea "PASS | ..." o "FAIL | ...".
\encoding UTF8
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
\set VERBOSITY terse
\pset pager off
\set ok f

SELECT id AS taller_1 FROM taller WHERE nombre = 'Taller Mecánico Los Aromos' \gset
SELECT id AS taller_2 FROM taller WHERE nombre = 'Servicio Automotriz Ñuble'  \gset
SELECT id AS admin_1  FROM usuario WHERE email = 'admin@losaromos.example'     \gset
SELECT id AS mec_1    FROM usuario WHERE email = 'mecanico1@losaromos.example' \gset
SELECT id AS mec_1b   FROM usuario WHERE email = 'mecanico2@losaromos.example' \gset
SELECT id AS aud_1    FROM usuario WHERE email = 'auditor@losaromos.example'   \gset
SELECT id AS admin_2  FROM usuario WHERE email = 'admin@nuble.example'         \gset
SELECT id AS mec_2    FROM usuario WHERE email = 'mecanico@nuble.example'      \gset
SELECT id AS aud_2    FROM usuario WHERE email = 'auditor@nuble.example'       \gset

\ir ../../queries/preparar.sql

BEGIN;

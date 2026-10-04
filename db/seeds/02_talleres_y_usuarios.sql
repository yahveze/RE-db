-- =============================================================================
-- Semilla 02 - Talleres, usuarios y dispositivos.
--
-- Dos etapas:
--   1. Alta de plataforma (superusuario): taller, su configuracion y su primer
--      administrador con credencial. Es lo unico que ningun rol de taller puede
--      hacer por si mismo.
--   2. Cada administrador, con SU rol y SU contexto (el mismo patron que usa el
--      backend), crea el resto de los usuarios, les fija la contrasena con
--      fn_establecer_contrasena, ajusta la configuracion y registra los
--      dispositivos. Asi las semillas pasan por los GRANT, las politicas RLS y
--      la auditoria reales.
--
-- La contrasena de demostracion llega por psql -v (:'clave_demo', desde .env).
-- Nunca se escribe en este archivo. Los emails usan el dominio reservado
-- ".example" y los nombres son ficticios.
-- =============================================================================
\encoding UTF8
\o /dev/null

-- ----------------------------------------------------------------------------
-- 1. Alta de plataforma
-- ----------------------------------------------------------------------------
BEGIN;

INSERT INTO taller (nombre) VALUES ('Taller Mecánico Los Aromos') RETURNING id AS taller_1 \gset
INSERT INTO taller (nombre) VALUES ('Servicio Automotriz Ñuble')  RETURNING id AS taller_2 \gset

-- Valores por defecto: CLP, tema claro, margen 30 %, retencion 6 anios.
INSERT INTO taller_configuracion (taller_id) VALUES (:taller_1), (:taller_2);

INSERT INTO usuario (taller_id, email, nombre, rol)
VALUES (:taller_1, 'admin@losaromos.example', 'Carla Fuentes', 'admin')
RETURNING id AS admin_1 \gset

INSERT INTO usuario (taller_id, email, nombre, rol)
VALUES (:taller_2, 'admin@nuble.example', 'Rodrigo Henríquez', 'admin')
RETURNING id AS admin_2 \gset

INSERT INTO usuario_credencial (usuario_id, hash_contrasena)
SELECT u.id, crypt(:'clave_demo', gen_salt('bf', 10))
FROM   usuario u
WHERE  u.id IN (:admin_1, :admin_2);

COMMIT;

-- ----------------------------------------------------------------------------
-- 2a. Administradora del taller 1
-- ----------------------------------------------------------------------------
BEGIN;
SET LOCAL ROLE taller_admin;
SELECT set_config('app.taller_id',  :'taller_1', true),
       set_config('app.usuario_id', :'admin_1',  true),
       set_config('app.request_id', 'semilla-02-taller-1', true);

INSERT INTO usuario (taller_id, email, nombre, rol, activo) VALUES
  (:taller_1, 'mecanico1@losaromos.example',  'Diego Rojas',   'mecanico', true),
  (:taller_1, 'mecanico2@losaromos.example',  'Paula Soto',    'mecanico', true),
  (:taller_1, 'auditor@losaromos.example',    'Marcela Vidal', 'auditor',  true),
  -- Usuario dado de baja: existe y tiene credencial, pero no puede autenticarse.
  (:taller_1, 'exmecanico@losaromos.example', 'Hugo Pino',     'mecanico', false);

SELECT fn_establecer_contrasena(u.id, :'clave_demo')
FROM   usuario u
WHERE  u.rol <> 'admin';

INSERT INTO dispositivo_diagnostico (taller_id, mac, estado, fabricante, modelo, firmware) VALUES
  (:taller_1, '00:1D:A5:68:98:8A', 'activo',   'OBDLink', 'MX+',        '5.6.19'),
  (:taller_1, '00:1D:A5:00:12:34', 'inactivo', 'Vgate',   'iCar Pro',   '2.3'),
  (:taller_1, '66:1E:10:0F:AA:01', 'baja',     'ELM',     'ELM327 v1.5', NULL);

COMMIT;

-- ----------------------------------------------------------------------------
-- 2b. Administrador del taller 2 (otro margen y otro tema)
-- ----------------------------------------------------------------------------
BEGIN;
SET LOCAL ROLE taller_admin;
SELECT set_config('app.taller_id',  :'taller_2', true),
       set_config('app.usuario_id', :'admin_2',  true),
       set_config('app.request_id', 'semilla-02-taller-2', true);

UPDATE taller_configuracion
SET    margen_pct = 45.50,
       tema       = 'oscuro';

INSERT INTO usuario (taller_id, email, nombre, rol) VALUES
  (:taller_2, 'mecanico@nuble.example', 'Valentina Muñoz', 'mecanico'),
  (:taller_2, 'auditor@nuble.example',  'Ignacio Parra',   'auditor');

SELECT fn_establecer_contrasena(u.id, :'clave_demo')
FROM   usuario u
WHERE  u.rol <> 'admin';

-- La misma MAC puede existir en dos talleres: la unicidad es por taller.
INSERT INTO dispositivo_diagnostico (taller_id, mac, estado, fabricante, modelo, firmware) VALUES
  (:taller_2, '00:04:3E:9A:11:22', 'activo', 'OBDLink', 'LX', '5.4.0');

COMMIT;

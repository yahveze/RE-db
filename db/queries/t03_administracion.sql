-- =============================================================================
-- t03 - Escrituras del administrador.                   rol: admin
-- =============================================================================

-- POST /users
--   $1 email (la API lo pasa a minusculas), $2 nombre, $3 rol
-- 23505 (uq_usuario_email): el email ya existe en algun taller.
-- El usuario no puede autenticarse hasta que se le fije una contrasena
-- (tx_establecer_contrasena, en la misma transaccion).
PREPARE tx_crear_usuario (text, text, tipo_rol_usuario) AS
INSERT INTO usuario (taller_id, email, nombre, rol)
VALUES (fn_contexto_taller_id(), $1, $2, $3)
RETURNING id_publico, email, nombre, rol, activo, creado_en;

-- PUT /users/{usuario}/password
--   $1 id_publico del usuario, $2 contrasena
-- Cero filas = el usuario no existe en el taller (404).
-- Errores: RE011 contrasena fuera de limites, RE006 rol o contexto no autorizado.
-- La contrasena viaja como parametro, no como texto de la sentencia, y el
-- servidor corre con log_statement = none.
-- La funcion devuelve void; MATERIALIZED garantiza que se ejecuta aunque la
-- consulta exterior solo lea id_publico.
PREPARE tx_establecer_contrasena (uuid, text) AS
WITH establecida AS MATERIALIZED (
  SELECT u.id_publico, fn_establecer_contrasena(u.id, $2)
  FROM   usuario u
  WHERE  u.id_publico = $1
)
SELECT e.id_publico
FROM   establecida e;

-- PATCH /users/{usuario}
--   $1 id_publico del usuario, $2 activo
-- Baja logica: no se borran usuarios (sus sesiones los referencian).
PREPARE tx_cambiar_activo_usuario (uuid, boolean) AS
UPDATE usuario u
SET    activo = $2
WHERE  u.id_publico = $1
RETURNING u.id_publico, u.email, u.nombre, u.rol, u.activo, u.actualizado_en;

-- PATCH /settings
--   $1 tema, $2 margen_pct, $3 retencion_anios   (NULL = no cambiar)
-- Sin WHERE: RLS limita el UPDATE a la fila del taller del contexto.
-- El margen nuevo afecta a la matriz y a los borradores que se llenen desde
-- ahora; las lineas ya cotizadas conservan su snapshot. 23514 si el margen sale
-- de 0-200 o la retencion de 0-30.
PREPARE tx_actualizar_configuracion (tipo_tema_visual, numeric, smallint) AS
UPDATE taller_configuracion tc
SET    tema            = COALESCE($1, tc.tema),
       margen_pct      = COALESCE($2, tc.margen_pct),
       retencion_anios = COALESCE($3, tc.retencion_anios)
RETURNING tc.moneda, tc.tema, tc.margen_pct, tc.retencion_anios, tc.actualizado_en;

-- POST /devices
--   $1 MAC, $2 fabricante, $3 modelo, $4 firmware
-- 23505 (uq_dispositivo_diagnostico_taller_mac): la MAC ya esta registrada en el taller.
PREPARE tx_registrar_dispositivo (macaddr, text, text, text) AS
INSERT INTO dispositivo_diagnostico (taller_id, mac, fabricante, modelo, firmware)
VALUES (fn_contexto_taller_id(), $1, $2, $3, $4)
RETURNING id_publico, mac, estado, fabricante, modelo, firmware, creado_en;

-- POST /holders/{titular}/erasure
--   $1 id_publico del titular
-- Supresion con retencion legal: devuelve 'bloqueado' (con la fecha de
-- vencimiento) o 'anonimizado'. Titular y vehiculos cambian en la misma
-- transaccion. Cero filas = 404. RE006 si no es el administrador.
PREPARE tx_solicitar_supresion (uuid) AS
SELECT t.id_publico,
       fn_solicitar_supresion_titular(t.id) AS estado_tratamiento
FROM   titular t
WHERE  t.id_publico = $1;

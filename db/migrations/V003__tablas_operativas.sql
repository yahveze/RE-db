-- =============================================================================
-- V003 - Tablas multi-taller, privacidad, operacion, cotizacion y auditoria.
--
-- Aislamiento entre talleres:
--   * Toda tabla operativa lleva taller_id NOT NULL.
--   * Las tablas PADRE referenciadas (usuario, titular, vehiculo,
--     dispositivo_diagnostico, sesion_diagnostico, cotizacion) declaran
--     UNIQUE (id, taller_id). Es logicamente redundante (id ya es unico), pero
--     PostgreSQL exige una restriccion unica exacta sobre las columnas
--     referenciadas por una FK compuesta.
--   * Las hijas referencian (padre_id, taller_id): una fila no puede apuntar a
--     un padre de otro taller.
--
-- Los indices UNICOS PARCIALES se crean aqui y no en V006 porque son reglas de
-- integridad, no optimizaciones. RLS NO se activa aqui (va en V008).
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Multi-taller
-- ----------------------------------------------------------------------------
CREATE TABLE taller (
  id              BIGINT GENERATED ALWAYS AS IDENTITY,
  id_publico      UUID        NOT NULL DEFAULT gen_random_uuid(),
  nombre          TEXT        NOT NULL,
  activo          BOOLEAN     NOT NULL DEFAULT true,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  actualizado_en  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT pk_taller PRIMARY KEY (id),
  CONSTRAINT uq_taller_id_publico UNIQUE (id_publico),
  CONSTRAINT ck_taller_nombre_no_vacio CHECK (btrim(nombre) <> '')
);

-- 1:1 con taller: la PK es la FK.
CREATE TABLE taller_configuracion (
  taller_id        BIGINT           NOT NULL,
  moneda           CHAR(3)          NOT NULL DEFAULT 'CLP',
  tema             tipo_tema_visual NOT NULL DEFAULT 'claro',
  margen_pct       NUMERIC(5,2)     NOT NULL DEFAULT 30.00,
  retencion_anios  SMALLINT         NOT NULL DEFAULT 6,
  actualizado_en   TIMESTAMPTZ      NOT NULL DEFAULT now(),
  CONSTRAINT pk_taller_configuracion PRIMARY KEY (taller_id),
  CONSTRAINT ck_taller_configuracion_moneda_formato CHECK (moneda ~ '^[A-Z]{3}$'),
  CONSTRAINT ck_taller_configuracion_margen_rango CHECK (margen_pct BETWEEN 0 AND 200),
  CONSTRAINT ck_taller_configuracion_retencion_rango CHECK (retencion_anios BETWEEN 0 AND 30),
  CONSTRAINT fk_taller_configuracion_taller FOREIGN KEY (taller_id)
    REFERENCES taller (id) ON DELETE RESTRICT
);

CREATE TABLE usuario (
  id              BIGINT GENERATED ALWAYS AS IDENTITY,
  id_publico      UUID             NOT NULL DEFAULT gen_random_uuid(),
  taller_id       BIGINT           NOT NULL,
  email           TEXT             NOT NULL,
  nombre          TEXT             NOT NULL,
  rol             tipo_rol_usuario NOT NULL,
  activo          BOOLEAN          NOT NULL DEFAULT true,
  creado_en       TIMESTAMPTZ      NOT NULL DEFAULT now(),
  actualizado_en  TIMESTAMPTZ      NOT NULL DEFAULT now(),
  CONSTRAINT pk_usuario PRIMARY KEY (id),
  CONSTRAINT uq_usuario_id_publico UNIQUE (id_publico),
  CONSTRAINT uq_usuario_email UNIQUE (email),
  CONSTRAINT uq_usuario_id_taller UNIQUE (id, taller_id),
  CONSTRAINT ck_usuario_email_minusculas CHECK (email = lower(email)),
  CONSTRAINT ck_usuario_email_formato CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  CONSTRAINT ck_usuario_nombre_no_vacio CHECK (btrim(nombre) <> ''),
  CONSTRAINT fk_usuario_taller FOREIGN KEY (taller_id)
    REFERENCES taller (id) ON DELETE RESTRICT
);

-- 1:1 con usuario, separada por minimo privilegio: ningun rol de grupo tiene
-- acceso; solo las funciones SECURITY DEFINER. CASCADE porque una credencial no
-- tiene sentido sin su usuario.
CREATE TABLE usuario_credencial (
  usuario_id         BIGINT      NOT NULL,
  hash_contrasena    TEXT        NOT NULL,
  intentos_fallidos  INTEGER     NOT NULL DEFAULT 0,
  bloqueado_hasta    TIMESTAMPTZ,
  ultimo_login_en    TIMESTAMPTZ,
  actualizado_en     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT pk_usuario_credencial PRIMARY KEY (usuario_id),
  CONSTRAINT ck_usuario_credencial_intentos_no_negativos CHECK (intentos_fallidos >= 0),
  CONSTRAINT ck_usuario_credencial_hash_no_vacio CHECK (btrim(hash_contrasena) <> ''),
  CONSTRAINT fk_usuario_credencial_usuario FOREIGN KEY (usuario_id)
    REFERENCES usuario (id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- Privacidad
-- ----------------------------------------------------------------------------
CREATE TABLE titular (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY,
  id_publico          UUID                    NOT NULL DEFAULT gen_random_uuid(),
  taller_id           BIGINT                  NOT NULL,
  nombre              TEXT,
  telefono            TEXT,
  email               TEXT,
  identificador_hmac  BYTEA,
  estado_tratamiento  tipo_estado_tratamiento NOT NULL DEFAULT 'activo',
  bloqueado_hasta     DATE,
  anonimizado_en      TIMESTAMPTZ,
  creado_en           TIMESTAMPTZ             NOT NULL DEFAULT now(),
  actualizado_en      TIMESTAMPTZ             NOT NULL DEFAULT now(),
  CONSTRAINT pk_titular PRIMARY KEY (id),
  CONSTRAINT uq_titular_id_publico UNIQUE (id_publico),
  CONSTRAINT uq_titular_id_taller UNIQUE (id, taller_id),
  CONSTRAINT ck_titular_hmac_largo CHECK (identificador_hmac IS NULL OR octet_length(identificador_hmac) = 32),
  CONSTRAINT ck_titular_estado_bloqueado
    CHECK ((estado_tratamiento = 'bloqueado') = (bloqueado_hasta IS NOT NULL)),
  CONSTRAINT ck_titular_estado_anonimizado
    CHECK ((estado_tratamiento = 'anonimizado') = (anonimizado_en IS NOT NULL)),
  CONSTRAINT ck_titular_anonimizado_sin_datos CHECK (
    CASE WHEN anonimizado_en IS NOT NULL
         THEN nombre IS NULL AND telefono IS NULL AND email IS NULL AND identificador_hmac IS NULL
         ELSE nombre IS NOT NULL AND btrim(nombre) <> ''
    END),
  CONSTRAINT fk_titular_taller FOREIGN KEY (taller_id)
    REFERENCES taller (id) ON DELETE RESTRICT
);

-- Detecta al mismo titular dentro de un taller sin guardar su RUT.
CREATE UNIQUE INDEX uq_titular_taller_identificador_hmac
  ON titular (taller_id, identificador_hmac)
  WHERE identificador_hmac IS NOT NULL;

CREATE TABLE consentimiento_titular (
  id                BIGINT GENERATED ALWAYS AS IDENTITY,
  taller_id         BIGINT                     NOT NULL,
  titular_id        BIGINT                     NOT NULL,
  finalidad         tipo_finalidad_tratamiento NOT NULL,
  version_terminos  TEXT                       NOT NULL,
  canal             TEXT                       NOT NULL,
  otorgado_en       TIMESTAMPTZ                NOT NULL DEFAULT now(),
  revocado_en       TIMESTAMPTZ,
  CONSTRAINT pk_consentimiento_titular PRIMARY KEY (id),
  CONSTRAINT ck_consentimiento_titular_version_no_vacia CHECK (btrim(version_terminos) <> ''),
  CONSTRAINT ck_consentimiento_titular_canal CHECK (canal IN ('presencial', 'app', 'web', 'telefono')),
  CONSTRAINT ck_consentimiento_titular_revocacion_posterior CHECK (revocado_en IS NULL OR revocado_en >= otorgado_en),
  CONSTRAINT fk_consentimiento_titular_taller FOREIGN KEY (taller_id)
    REFERENCES taller (id) ON DELETE RESTRICT,
  CONSTRAINT fk_consentimiento_titular_titular FOREIGN KEY (titular_id, taller_id)
    REFERENCES titular (id, taller_id) ON DELETE RESTRICT
);

-- A lo mas un consentimiento ACTIVO por titular y finalidad.
CREATE UNIQUE INDEX uq_consentimiento_titular_activo
  ON consentimiento_titular (titular_id, finalidad)
  WHERE revocado_en IS NULL;

CREATE TABLE solicitud_derecho_titular (
  id                      BIGINT GENERATED ALWAYS AS IDENTITY,
  id_publico              UUID                   NOT NULL DEFAULT gen_random_uuid(),
  taller_id               BIGINT                 NOT NULL,
  titular_id              BIGINT                 NOT NULL,
  tipo                    tipo_solicitud_derecho NOT NULL,
  estado                  tipo_estado_solicitud  NOT NULL DEFAULT 'recibida',
  usuario_responsable_id  BIGINT,
  recibida_en             TIMESTAMPTZ            NOT NULL DEFAULT now(),
  resuelta_en             TIMESTAMPTZ,
  actualizado_en          TIMESTAMPTZ            NOT NULL DEFAULT now(),
  CONSTRAINT pk_solicitud_derecho_titular PRIMARY KEY (id),
  CONSTRAINT uq_solicitud_derecho_titular_id_publico UNIQUE (id_publico),
  CONSTRAINT ck_solicitud_derecho_titular_resolucion
    CHECK ((estado IN ('resuelta', 'rechazada')) = (resuelta_en IS NOT NULL)),
  CONSTRAINT fk_solicitud_derecho_titular_taller FOREIGN KEY (taller_id)
    REFERENCES taller (id) ON DELETE RESTRICT,
  CONSTRAINT fk_solicitud_derecho_titular_titular FOREIGN KEY (titular_id, taller_id)
    REFERENCES titular (id, taller_id) ON DELETE RESTRICT,
  -- MATCH SIMPLE (por defecto): si usuario_responsable_id es NULL no se evalua.
  CONSTRAINT fk_solicitud_derecho_titular_usuario FOREIGN KEY (usuario_responsable_id, taller_id)
    REFERENCES usuario (id, taller_id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- Operacion
-- ----------------------------------------------------------------------------
CREATE TABLE vehiculo (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY,
  id_publico          UUID        NOT NULL DEFAULT gen_random_uuid(),
  taller_id           BIGINT      NOT NULL,
  titular_id          BIGINT,
  modelo_vehiculo_id  BIGINT      NOT NULL,
  anio                SMALLINT    NOT NULL,
  motor               TEXT,
  vin                 TEXT,
  patente             TEXT,
  anonimizado_en      TIMESTAMPTZ,
  creado_en           TIMESTAMPTZ NOT NULL DEFAULT now(),
  actualizado_en      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT pk_vehiculo PRIMARY KEY (id),
  CONSTRAINT uq_vehiculo_id_publico UNIQUE (id_publico),
  CONSTRAINT uq_vehiculo_id_taller UNIQUE (id, taller_id),
  -- Limites FIJOS: now() no puede usarse en un CHECK. 1981 = primer anio del
  -- VIN estandar de 17 caracteres.
  CONSTRAINT ck_vehiculo_anio_rango CHECK (anio BETWEEN 1981 AND 2100),
  CONSTRAINT ck_vehiculo_motor_no_vacio CHECK (motor IS NULL OR btrim(motor) <> ''),
  -- Sin I, O ni Q (se confunden con 1 y 0).
  CONSTRAINT ck_vehiculo_vin_formato CHECK (vin IS NULL OR vin ~ '^[A-HJ-NPR-Z0-9]{17}$'),
  -- Formato antiguo (AA1234) y nuevo (BBBB12, solo consonantes permitidas).
  CONSTRAINT ck_vehiculo_patente_formato CHECK (
    patente IS NULL
    OR patente ~ '^[A-Z]{2}[0-9]{4}$'
    OR patente ~ '^[BCDFGHJKLPRSTVWXYZ]{4}[0-9]{2}$'),
  CONSTRAINT ck_vehiculo_patente_obligatoria CHECK (anonimizado_en IS NOT NULL OR patente IS NOT NULL),
  CONSTRAINT ck_vehiculo_anonimizado_sin_identificadores
    CHECK (anonimizado_en IS NULL OR (patente IS NULL AND vin IS NULL)),
  -- Sin VIN, el motor es obligatorio: (modelo, anio, motor) identifican tecnicamente.
  CONSTRAINT ck_vehiculo_identificacion_tecnica
    CHECK (anonimizado_en IS NOT NULL OR vin IS NOT NULL OR motor IS NOT NULL),
  CONSTRAINT fk_vehiculo_taller FOREIGN KEY (taller_id)
    REFERENCES taller (id) ON DELETE RESTRICT,
  -- MATCH SIMPLE: un vehiculo sin titular (titular_id NULL) es valido.
  CONSTRAINT fk_vehiculo_titular FOREIGN KEY (titular_id, taller_id)
    REFERENCES titular (id, taller_id) ON DELETE RESTRICT,
  CONSTRAINT fk_vehiculo_modelo_vehiculo FOREIGN KEY (modelo_vehiculo_id)
    REFERENCES modelo_vehiculo (id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX uq_vehiculo_taller_vin
  ON vehiculo (taller_id, vin) WHERE vin IS NOT NULL;

CREATE UNIQUE INDEX uq_vehiculo_taller_patente
  ON vehiculo (taller_id, patente) WHERE patente IS NOT NULL;

CREATE TABLE dispositivo_diagnostico (
  id              BIGINT GENERATED ALWAYS AS IDENTITY,
  id_publico      UUID                    NOT NULL DEFAULT gen_random_uuid(),
  taller_id       BIGINT                  NOT NULL,
  mac             MACADDR                 NOT NULL,
  estado          tipo_estado_dispositivo NOT NULL DEFAULT 'activo',
  fabricante      TEXT,
  modelo          TEXT,
  firmware        TEXT,
  creado_en       TIMESTAMPTZ             NOT NULL DEFAULT now(),
  actualizado_en  TIMESTAMPTZ             NOT NULL DEFAULT now(),
  CONSTRAINT pk_dispositivo_diagnostico PRIMARY KEY (id),
  CONSTRAINT uq_dispositivo_diagnostico_id_publico UNIQUE (id_publico),
  CONSTRAINT uq_dispositivo_diagnostico_id_taller UNIQUE (id, taller_id),
  CONSTRAINT uq_dispositivo_diagnostico_taller_mac UNIQUE (taller_id, mac),
  CONSTRAINT fk_dispositivo_diagnostico_taller FOREIGN KEY (taller_id)
    REFERENCES taller (id) ON DELETE RESTRICT
);

CREATE TABLE sesion_diagnostico (
  id              BIGINT GENERATED ALWAYS AS IDENTITY,
  id_publico      UUID                 NOT NULL DEFAULT gen_random_uuid(),
  taller_id       BIGINT               NOT NULL,
  vehiculo_id     BIGINT               NOT NULL,
  usuario_id      BIGINT               NOT NULL,
  dispositivo_id  BIGINT,
  metodo_ingreso  tipo_metodo_ingreso  NOT NULL,
  kilometraje     INTEGER              NOT NULL,
  estado          tipo_estado_atencion NOT NULL DEFAULT 'pendiente',
  iniciada_en     TIMESTAMPTZ          NOT NULL DEFAULT now(),
  cotizada_en     TIMESTAMPTZ,
  completada_en   TIMESTAMPTZ,
  cancelada_en    TIMESTAMPTZ,
  version         INTEGER              NOT NULL DEFAULT 1,
  actualizado_en  TIMESTAMPTZ          NOT NULL DEFAULT now(),
  CONSTRAINT pk_sesion_diagnostico PRIMARY KEY (id),
  CONSTRAINT uq_sesion_diagnostico_id_publico UNIQUE (id_publico),
  CONSTRAINT uq_sesion_diagnostico_id_taller UNIQUE (id, taller_id),
  CONSTRAINT ck_sesion_diagnostico_kilometraje_no_negativo CHECK (kilometraje >= 0),
  CONSTRAINT ck_sesion_diagnostico_version_positiva CHECK (version > 0),
  -- dispositivo_id obligatorio si y solo si el metodo es obd_bluetooth.
  CONSTRAINT ck_sesion_diagnostico_dispositivo_segun_metodo
    CHECK ((metodo_ingreso = 'obd_bluetooth') = (dispositivo_id IS NOT NULL)),
  -- Coherencia estado <-> timestamps. 'cancelado' admite cotizada_en porque
  -- se puede cancelar desde 'cotizado'.
  CONSTRAINT ck_sesion_diagnostico_estado_timestamps CHECK (
    CASE estado
      WHEN 'pendiente'  THEN cotizada_en IS NULL     AND completada_en IS NULL     AND cancelada_en IS NULL
      WHEN 'cotizado'   THEN cotizada_en IS NOT NULL AND completada_en IS NULL     AND cancelada_en IS NULL
      WHEN 'completado' THEN cotizada_en IS NOT NULL AND completada_en IS NOT NULL AND cancelada_en IS NULL
      WHEN 'cancelado'  THEN completada_en IS NULL   AND cancelada_en IS NOT NULL
    END),
  CONSTRAINT fk_sesion_diagnostico_taller FOREIGN KEY (taller_id)
    REFERENCES taller (id) ON DELETE RESTRICT,
  CONSTRAINT fk_sesion_diagnostico_vehiculo FOREIGN KEY (vehiculo_id, taller_id)
    REFERENCES vehiculo (id, taller_id) ON DELETE RESTRICT,
  CONSTRAINT fk_sesion_diagnostico_usuario FOREIGN KEY (usuario_id, taller_id)
    REFERENCES usuario (id, taller_id) ON DELETE RESTRICT,
  -- MATCH SIMPLE: con metodo 'manual' dispositivo_id es NULL y no se evalua.
  CONSTRAINT fk_sesion_diagnostico_dispositivo FOREIGN KEY (dispositivo_id, taller_id)
    REFERENCES dispositivo_diagnostico (id, taller_id) ON DELETE RESTRICT
);

-- N:M sesion <-> DTC. Tabla hoja: no necesita UNIQUE (id, taller_id).
-- taller_id es una desnormalizacion deliberada (sesion_id -> taller_id),
-- protegida por la FK compuesta y usada por las politicas RLS.
CREATE TABLE falla_sesion (
  sesion_id     BIGINT         NOT NULL,
  dtc_id        BIGINT         NOT NULL,
  taller_id     BIGINT         NOT NULL,
  severidad     tipo_severidad NOT NULL,
  freeze_frame  JSONB,
  creado_en     TIMESTAMPTZ    NOT NULL DEFAULT now(),
  CONSTRAINT pk_falla_sesion PRIMARY KEY (sesion_id, dtc_id),
  CONSTRAINT ck_falla_sesion_freeze_frame_objeto
    CHECK (freeze_frame IS NULL OR jsonb_typeof(freeze_frame) = 'object'),
  CONSTRAINT fk_falla_sesion_taller FOREIGN KEY (taller_id)
    REFERENCES taller (id) ON DELETE RESTRICT,
  CONSTRAINT fk_falla_sesion_sesion_diagnostico FOREIGN KEY (sesion_id, taller_id)
    REFERENCES sesion_diagnostico (id, taller_id) ON DELETE RESTRICT,
  CONSTRAINT fk_falla_sesion_dtc_catalogo FOREIGN KEY (dtc_id)
    REFERENCES dtc_catalogo (id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- Cotizacion
-- ----------------------------------------------------------------------------
CREATE TABLE cotizacion (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY,
  id_publico          UUID        NOT NULL DEFAULT gen_random_uuid(),
  taller_id           BIGINT      NOT NULL,
  sesion_id           BIGINT      NOT NULL,
  numero_revision     INTEGER     NOT NULL,
  vigente             BOOLEAN     NOT NULL DEFAULT false,
  cerrada_en          TIMESTAMPTZ,
  total               BIGINT,
  moneda              CHAR(3)     NOT NULL,
  clave_idempotencia  UUID        NOT NULL,
  version             INTEGER     NOT NULL DEFAULT 1,
  creado_en           TIMESTAMPTZ NOT NULL DEFAULT now(),
  actualizado_en      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT pk_cotizacion PRIMARY KEY (id),
  CONSTRAINT uq_cotizacion_id_publico UNIQUE (id_publico),
  CONSTRAINT uq_cotizacion_id_taller UNIQUE (id, taller_id),
  CONSTRAINT uq_cotizacion_sesion_revision UNIQUE (sesion_id, numero_revision),
  CONSTRAINT uq_cotizacion_taller_clave_idempotencia UNIQUE (taller_id, clave_idempotencia),
  CONSTRAINT ck_cotizacion_revision_positiva CHECK (numero_revision > 0),
  CONSTRAINT ck_cotizacion_version_positiva CHECK (version > 0),
  CONSTRAINT ck_cotizacion_moneda_formato CHECK (moneda ~ '^[A-Z]{3}$'),
  CONSTRAINT ck_cotizacion_total_no_negativo CHECK (total IS NULL OR total >= 0),
  -- El total existe si y solo si la cotizacion esta cerrada.
  CONSTRAINT ck_cotizacion_total_al_cerrar CHECK ((cerrada_en IS NULL) = (total IS NULL)),
  -- Solo una cotizacion cerrada puede ser la vigente.
  CONSTRAINT ck_cotizacion_vigente_cerrada CHECK (NOT vigente OR cerrada_en IS NOT NULL),
  CONSTRAINT fk_cotizacion_taller FOREIGN KEY (taller_id)
    REFERENCES taller (id) ON DELETE RESTRICT,
  CONSTRAINT fk_cotizacion_sesion_diagnostico FOREIGN KEY (sesion_id, taller_id)
    REFERENCES sesion_diagnostico (id, taller_id) ON DELETE RESTRICT
);

-- Una sola cotizacion vigente por sesion.
CREATE UNIQUE INDEX uq_cotizacion_sesion_vigente
  ON cotizacion (sesion_id) WHERE vigente;

-- Un solo borrador (cotizacion abierta) por sesion.
CREATE UNIQUE INDEX uq_cotizacion_sesion_abierta
  ON cotizacion (sesion_id) WHERE cerrada_en IS NULL;

-- N:M cotizacion <-> repuesto con snapshot. Tabla hoja. CASCADE porque el
-- detalle es parte de la cotizacion.
-- Las columnas *_snapshot y precio_unitario son desnormalizaciones
-- intencionales: congelan el catalogo y el margen del momento de cotizar.
CREATE TABLE cotizacion_detalle (
  cotizacion_id               BIGINT               NOT NULL,
  repuesto_id                 BIGINT               NOT NULL,
  taller_id                   BIGINT               NOT NULL,
  cantidad                    INTEGER              NOT NULL,
  nombre_snapshot             TEXT                 NOT NULL,
  marca_snapshot              TEXT                 NOT NULL,
  perfil_snapshot             tipo_perfil_repuesto NOT NULL,
  precio_referencia_snapshot  BIGINT               NOT NULL,
  margen_pct_snapshot         NUMERIC(5,2)         NOT NULL,
  precio_unitario             BIGINT               NOT NULL,
  creado_en                   TIMESTAMPTZ          NOT NULL DEFAULT now(),
  CONSTRAINT pk_cotizacion_detalle PRIMARY KEY (cotizacion_id, repuesto_id),
  CONSTRAINT ck_cotizacion_detalle_cantidad_positiva CHECK (cantidad > 0),
  CONSTRAINT ck_cotizacion_detalle_precio_referencia_no_negativo CHECK (precio_referencia_snapshot >= 0),
  CONSTRAINT ck_cotizacion_detalle_margen_rango CHECK (margen_pct_snapshot BETWEEN 0 AND 200),
  -- El precio guardado debe coincidir con la formula de markup sobre costo.
  CONSTRAINT ck_cotizacion_detalle_precio_unitario_formula
    CHECK (precio_unitario = ROUND(precio_referencia_snapshot * (1 + margen_pct_snapshot / 100))),
  CONSTRAINT fk_cotizacion_detalle_taller FOREIGN KEY (taller_id)
    REFERENCES taller (id) ON DELETE RESTRICT,
  CONSTRAINT fk_cotizacion_detalle_cotizacion FOREIGN KEY (cotizacion_id, taller_id)
    REFERENCES cotizacion (id, taller_id) ON DELETE CASCADE,
  CONSTRAINT fk_cotizacion_detalle_repuesto FOREIGN KEY (repuesto_id)
    REFERENCES repuesto (id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- Auditoria (append-only, SIN claves foraneas)
-- taller_id, usuario_id y registro_id son valores, no FK: el registro debe
-- sobrevivir a cualquier cambio del esquema y no puede bloquear operaciones.
-- clock_timestamp() y no now(): dentro de una transaccion now() es constante.
-- ----------------------------------------------------------------------------
CREATE TABLE auditoria_operacion (
  id                BIGINT GENERATED ALWAYS AS IDENTITY,
  ocurrido_en       TIMESTAMPTZ              NOT NULL DEFAULT clock_timestamp(),
  taller_id         BIGINT,
  usuario_id        BIGINT,
  rol               TEXT                     NOT NULL,
  operacion         tipo_operacion_auditoria NOT NULL,
  tabla             TEXT,
  registro_id       BIGINT,
  datos_anteriores  JSONB,
  datos_nuevos      JSONB,
  ip_origen         INET,
  resultado         tipo_resultado_auditoria NOT NULL,
  request_id        TEXT,
  CONSTRAINT pk_auditoria_operacion PRIMARY KEY (id)
);

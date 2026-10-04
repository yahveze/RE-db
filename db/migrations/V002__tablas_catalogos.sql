-- =============================================================================
-- V002 - Catalogos globales (sin taller_id, sin RLS).
-- Solo lectura para los talleres; los escribe unicamente app_owner.
-- Toda FK es ON DELETE RESTRICT: un catalogo en uso no puede desaparecer.
-- =============================================================================

CREATE TABLE marca_vehiculo (
  id          BIGINT GENERATED ALWAYS AS IDENTITY,
  id_publico  UUID        NOT NULL DEFAULT gen_random_uuid(),
  nombre      TEXT        NOT NULL,
  creado_en   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT pk_marca_vehiculo PRIMARY KEY (id),
  CONSTRAINT uq_marca_vehiculo_id_publico UNIQUE (id_publico),
  CONSTRAINT uq_marca_vehiculo_nombre UNIQUE (nombre),
  CONSTRAINT ck_marca_vehiculo_nombre_no_vacio CHECK (btrim(nombre) <> '')
);

CREATE TABLE modelo_vehiculo (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY,
  id_publico         UUID        NOT NULL DEFAULT gen_random_uuid(),
  marca_vehiculo_id  BIGINT      NOT NULL,
  nombre             TEXT        NOT NULL,
  creado_en          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT pk_modelo_vehiculo PRIMARY KEY (id),
  CONSTRAINT uq_modelo_vehiculo_id_publico UNIQUE (id_publico),
  CONSTRAINT uq_modelo_vehiculo_marca_nombre UNIQUE (marca_vehiculo_id, nombre),
  CONSTRAINT ck_modelo_vehiculo_nombre_no_vacio CHECK (btrim(nombre) <> ''),
  CONSTRAINT fk_modelo_vehiculo_marca_vehiculo FOREIGN KEY (marca_vehiculo_id)
    REFERENCES marca_vehiculo (id) ON DELETE RESTRICT
);

CREATE TABLE dtc_catalogo (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY,
  codigo              TEXT           NOT NULL,
  descripcion         TEXT           NOT NULL,
  severidad_sugerida  tipo_severidad NOT NULL,
  creado_en           TIMESTAMPTZ    NOT NULL DEFAULT now(),
  CONSTRAINT pk_dtc_catalogo PRIMARY KEY (id),
  CONSTRAINT uq_dtc_catalogo_codigo UNIQUE (codigo),
  CONSTRAINT ck_dtc_catalogo_codigo_formato CHECK (codigo ~ '^[PCBU][0-3][0-9A-F]{3}$'),
  CONSTRAINT ck_dtc_catalogo_descripcion_no_vacia CHECK (btrim(descripcion) <> '')
);

CREATE TABLE componente_repuesto (
  id           BIGINT GENERATED ALWAYS AS IDENTITY,
  id_publico   UUID        NOT NULL DEFAULT gen_random_uuid(),
  nombre       TEXT        NOT NULL,
  descripcion  TEXT,
  creado_en    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT pk_componente_repuesto PRIMARY KEY (id),
  CONSTRAINT uq_componente_repuesto_id_publico UNIQUE (id_publico),
  CONSTRAINT uq_componente_repuesto_nombre UNIQUE (nombre),
  CONSTRAINT ck_componente_repuesto_nombre_no_vacio CHECK (btrim(nombre) <> '')
);

-- N:M DTC <-> componente. PK compuesta natural, sin id propio.
CREATE TABLE dtc_componente (
  dtc_id         BIGINT NOT NULL,
  componente_id  BIGINT NOT NULL,
  CONSTRAINT pk_dtc_componente PRIMARY KEY (dtc_id, componente_id),
  CONSTRAINT fk_dtc_componente_dtc_catalogo FOREIGN KEY (dtc_id)
    REFERENCES dtc_catalogo (id) ON DELETE RESTRICT,
  CONSTRAINT fk_dtc_componente_componente_repuesto FOREIGN KEY (componente_id)
    REFERENCES componente_repuesto (id) ON DELETE RESTRICT
);

CREATE TABLE repuesto (
  id                       BIGINT GENERATED ALWAYS AS IDENTITY,
  id_publico               UUID                 NOT NULL DEFAULT gen_random_uuid(),
  componente_id            BIGINT               NOT NULL,
  perfil                   tipo_perfil_repuesto NOT NULL,
  marca                    TEXT                 NOT NULL,
  nombre                   TEXT                 NOT NULL,
  codigo_fabricante        TEXT                 NOT NULL,
  durabilidad_estimada_km  INTEGER              NOT NULL,
  riesgo                   tipo_nivel_riesgo    NOT NULL,
  precio_referencia        BIGINT               NOT NULL,
  disponible               BOOLEAN              NOT NULL DEFAULT true,
  creado_en                TIMESTAMPTZ          NOT NULL DEFAULT now(),
  actualizado_en           TIMESTAMPTZ          NOT NULL DEFAULT now(),
  CONSTRAINT pk_repuesto PRIMARY KEY (id),
  CONSTRAINT uq_repuesto_id_publico UNIQUE (id_publico),
  CONSTRAINT uq_repuesto_componente_marca_codigo UNIQUE (componente_id, marca, codigo_fabricante),
  CONSTRAINT ck_repuesto_marca_no_vacia CHECK (btrim(marca) <> ''),
  CONSTRAINT ck_repuesto_nombre_no_vacio CHECK (btrim(nombre) <> ''),
  CONSTRAINT ck_repuesto_codigo_fabricante_no_vacio CHECK (btrim(codigo_fabricante) <> ''),
  CONSTRAINT ck_repuesto_durabilidad_positiva CHECK (durabilidad_estimada_km > 0),
  CONSTRAINT ck_repuesto_precio_no_negativo CHECK (precio_referencia >= 0),
  CONSTRAINT fk_repuesto_componente_repuesto FOREIGN KEY (componente_id)
    REFERENCES componente_repuesto (id) ON DELETE RESTRICT
);

-- N:M repuesto <-> modelo con rango de anios. anio_desde es parte de la PK
-- para admitir rangos disjuntos del mismo par.
CREATE TABLE compatibilidad_repuesto (
  repuesto_id         BIGINT   NOT NULL,
  modelo_vehiculo_id  BIGINT   NOT NULL,
  anio_desde          SMALLINT NOT NULL,
  anio_hasta          SMALLINT NOT NULL,
  CONSTRAINT pk_compatibilidad_repuesto PRIMARY KEY (repuesto_id, modelo_vehiculo_id, anio_desde),
  CONSTRAINT ck_compatibilidad_repuesto_rango CHECK (anio_desde <= anio_hasta),
  CONSTRAINT ck_compatibilidad_repuesto_limites CHECK (anio_desde >= 1981 AND anio_hasta <= 2100),
  CONSTRAINT fk_compatibilidad_repuesto_repuesto FOREIGN KEY (repuesto_id)
    REFERENCES repuesto (id) ON DELETE RESTRICT,
  CONSTRAINT fk_compatibilidad_repuesto_modelo_vehiculo FOREIGN KEY (modelo_vehiculo_id)
    REFERENCES modelo_vehiculo (id) ON DELETE RESTRICT
);

-- DTC <-> repuesto es DERIVABLE (dtc -> componentes -> repuestos), por eso es
-- vista y no tabla. security_invoker: se evaluan los privilegios de quien
-- consulta, no los del propietario de la vista (PostgreSQL 15+).
CREATE VIEW v_dtc_repuesto WITH (security_invoker = true) AS
SELECT dc.dtc_id,
       dc.componente_id,
       r.id AS repuesto_id
FROM   dtc_componente dc
JOIN   repuesto r ON r.componente_id = dc.componente_id;

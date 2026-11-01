-- V015: captura OBD real, identidad lógica e idempotencia de sesiones.
ALTER TABLE dispositivo_diagnostico ALTER COLUMN mac DROP NOT NULL;
ALTER TABLE dispositivo_diagnostico ADD COLUMN nombre text NOT NULL DEFAULT 'Adaptador OBD2',
  ADD COLUMN clave_registro uuid,
  ADD CONSTRAINT ck_dispositivo_diagnostico_nombre CHECK (length(btrim(nombre)) BETWEEN 1 AND 80),
  ADD CONSTRAINT uq_dispositivo_diagnostico_registro UNIQUE(taller_id,clave_registro);
COMMENT ON COLUMN dispositivo_diagnostico.mac IS 'MAC opcional. Web Serial no expone necesariamente la dirección física; no se inventa una MAC.';
COMMENT ON COLUMN dispositivo_diagnostico.nombre IS 'Alias de inventario elegido por el propietario; no acredita la identidad del hardware.';
COMMENT ON COLUMN dispositivo_diagnostico.clave_registro IS 'Clave idempotente del alta lógica de un adaptador.';
GRANT INSERT(nombre,clave_registro) ON dispositivo_diagnostico TO taller_admin;

ALTER TABLE sesion_diagnostico ADD COLUMN clave_ingreso uuid,
  ADD COLUMN hash_ingreso text,
  ADD COLUMN capturada_en timestamptz,
  ADD COLUMN protocolo_obd text,
  ADD COLUMN servicios_obd jsonb,
  ADD CONSTRAINT uq_sesion_diagnostico_ingreso UNIQUE(taller_id,clave_ingreso),
  ADD CONSTRAINT ck_sesion_diagnostico_captura CHECK (
    (clave_ingreso IS NULL AND hash_ingreso IS NULL AND capturada_en IS NULL AND protocolo_obd IS NULL AND servicios_obd IS NULL)
    OR (clave_ingreso IS NOT NULL AND hash_ingreso IS NOT NULL AND hash_ingreso ~ '^[a-f0-9]{64}$'
      AND capturada_en IS NOT NULL AND protocolo_obd IS NOT NULL AND length(protocolo_obd) BETWEEN 1 AND 120
      AND servicios_obd IS NOT NULL AND jsonb_typeof(servicios_obd)='object' AND metodo_ingreso='obd_bluetooth'));
COMMENT ON COLUMN sesion_diagnostico.clave_ingreso IS 'Clave de reintento de una captura, única por taller.';
COMMENT ON COLUMN sesion_diagnostico.hash_ingreso IS 'SHA-256 del contenido validado; detecta reutilización de clave con otra captura.';
COMMENT ON COLUMN sesion_diagnostico.capturada_en IS 'Hora UTC declarada por el cliente; iniciada_en conserva la hora del servidor.';
COMMENT ON COLUMN sesion_diagnostico.protocolo_obd IS 'Protocolo de vehículo identificado por el adaptador.';
COMMENT ON COLUMN sesion_diagnostico.servicios_obd IS 'Resultado de cada servicio OBD consultado; no confunde falta de respuesta con ausencia de fallas.';
GRANT INSERT(clave_ingreso,hash_ingreso,capturada_en,protocolo_obd,servicios_obd) ON sesion_diagnostico TO taller_mecanico;

CREATE TABLE observacion_obd (
  sesion_id bigint NOT NULL,
  taller_id bigint NOT NULL,
  ecu text NOT NULL,
  codigo text NOT NULL,
  categoria text NOT NULL,
  creado_en timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_observacion_obd PRIMARY KEY(sesion_id,ecu,codigo,categoria),
  CONSTRAINT ck_observacion_obd_ecu CHECK (ecu ~ '^[0-9A-F]{2,8}$'),
  CONSTRAINT ck_observacion_obd_codigo CHECK (codigo ~ '^[PCBU][0-3][0-9A-F]{3}$'),
  CONSTRAINT ck_observacion_obd_categoria CHECK (categoria IN ('stored','pending','permanent')),
  CONSTRAINT fk_observacion_obd_sesion FOREIGN KEY(sesion_id,taller_id) REFERENCES sesion_diagnostico(id,taller_id) ON DELETE RESTRICT
);
COMMENT ON TABLE observacion_obd IS 'Observaciones OBD por ECU y categoría, incluidos códigos no catalogados. No contiene VIN ni tramas crudas.';
COMMENT ON COLUMN observacion_obd.sesion_id IS 'Sesión de diagnóstico que conserva la captura.';
COMMENT ON COLUMN observacion_obd.taller_id IS 'Taller, protegido por FK compuesta y RLS.';
COMMENT ON COLUMN observacion_obd.ecu IS 'Dirección de respuesta de la ECU en hexadecimal.';
COMMENT ON COLUMN observacion_obd.codigo IS 'Código normalizado leído; no requiere una descripción inventada en el catálogo.';
COMMENT ON COLUMN observacion_obd.categoria IS 'Código almacenado, pendiente o permanente, según el servicio consultado.';
COMMENT ON COLUMN observacion_obd.creado_en IS 'Hora de persistencia del servidor.';
CREATE INDEX ix_observacion_obd_taller_sesion ON observacion_obd(taller_id,sesion_id);
ALTER TABLE observacion_obd ENABLE ROW LEVEL SECURITY;
ALTER TABLE observacion_obd FORCE ROW LEVEL SECURITY;
CREATE POLICY pol_observacion_obd_miembros_select ON observacion_obd FOR SELECT TO taller_admin,taller_mecanico
  USING(taller_id=(SELECT fn_contexto_taller_id()));
CREATE POLICY pol_observacion_obd_mecanico_insert ON observacion_obd FOR INSERT TO taller_mecanico
  WITH CHECK(taller_id=(SELECT fn_contexto_taller_id()) AND EXISTS(
    SELECT 1 FROM sesion_diagnostico s WHERE s.id=sesion_id AND s.taller_id=observacion_obd.taller_id
      AND s.usuario_id=(SELECT fn_contexto_usuario_id()) AND s.clave_ingreso IS NOT NULL));
REVOKE ALL ON observacion_obd FROM PUBLIC;
GRANT SELECT ON observacion_obd TO taller_admin,taller_mecanico;
GRANT INSERT(sesion_id,taller_id,ecu,codigo,categoria) ON observacion_obd TO taller_mecanico;
SET ROLE app_funciones;
GRANT EXECUTE ON FUNCTION fn_trg_auditar() TO app_owner;
SET ROLE app_owner;
CREATE TRIGGER trg_observacion_obd_auditar AFTER INSERT ON observacion_obd
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar();
SET ROLE app_funciones;
REVOKE EXECUTE ON FUNCTION fn_trg_auditar() FROM app_owner;
SET ROLE app_owner;

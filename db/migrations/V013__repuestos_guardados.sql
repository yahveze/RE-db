-- V013: decisiones del técnico, separadas de cotizaciones y contenido comercial.
CREATE TABLE repuesto_guardado (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_publico uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  taller_id bigint NOT NULL REFERENCES taller(id),
  usuario_id bigint NOT NULL,
  dtc_id bigint NOT NULL,
  componente_id bigint NOT NULL,
  modelo_vehiculo_id bigint REFERENCES modelo_vehiculo(id),
  anio smallint,
  vehiculo_id bigint,
  sesion_id bigint,
  proveedor text NOT NULL CHECK (proveedor = 'mercadolibre'),
  id_externo text NOT NULL CHECK (id_externo ~ '^MLC[0-9]{5,20}$'),
  tipo_referencia text NOT NULL CHECK (tipo_referencia IN ('listing','catalog_product')),
  enlace text CHECK (length(enlace) BETWEEN 1 AND 2000 AND enlace ~ '^https://([a-z0-9-]+[.])*mercadolibre[.]cl/'),
  CONSTRAINT ck_guardado_enlace CHECK ((tipo_referencia='listing' AND enlace IS NOT NULL) OR (tipo_referencia='catalog_product' AND enlace IS NULL)),
  nota text NOT NULL DEFAULT '' CHECK (length(nota) <= 1000),
  clave_idempotencia uuid NOT NULL,
  hash_solicitud text NOT NULL CHECK (hash_solicitud ~ '^[a-f0-9]{64}$'),
  creado_en timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_repuesto_guardado_peticion UNIQUE(taller_id,clave_idempotencia),
  CONSTRAINT fk_guardado_usuario FOREIGN KEY(usuario_id,taller_id) REFERENCES usuario(id,taller_id),
  CONSTRAINT fk_guardado_dtc_componente FOREIGN KEY(dtc_id,componente_id) REFERENCES dtc_componente(dtc_id,componente_id),
  CONSTRAINT fk_guardado_vehiculo FOREIGN KEY(vehiculo_id,taller_id) REFERENCES vehiculo(id,taller_id),
  CONSTRAINT fk_guardado_sesion FOREIGN KEY(sesion_id,taller_id) REFERENCES sesion_diagnostico(id,taller_id),
  CONSTRAINT ck_guardado_anio CHECK (anio IS NULL OR (modelo_vehiculo_id IS NOT NULL AND anio BETWEEN 1981 AND 2100))
);
COMMENT ON TABLE repuesto_guardado IS 'Referencia elegida por un técnico, sin compra, precio congelado ni cambio de estado del diagnóstico. No almacena títulos, imágenes ni stock del proveedor.';
CREATE INDEX ix_guardado_historial ON repuesto_guardado(taller_id,creado_en DESC,id DESC);
CREATE INDEX ix_guardado_sesion ON repuesto_guardado(taller_id,sesion_id) WHERE sesion_id IS NOT NULL;
ALTER TABLE repuesto_guardado ENABLE ROW LEVEL SECURITY;
ALTER TABLE repuesto_guardado FORCE ROW LEVEL SECURITY;
CREATE POLICY pol_guardado_select ON repuesto_guardado FOR SELECT TO taller_admin,taller_mecanico
  USING (taller_id=(SELECT fn_contexto_taller_id()));
CREATE POLICY pol_guardado_insert ON repuesto_guardado FOR INSERT TO taller_admin,taller_mecanico
  WITH CHECK (taller_id=(SELECT fn_contexto_taller_id()) AND usuario_id=(SELECT fn_contexto_usuario_id()));
REVOKE ALL ON repuesto_guardado FROM PUBLIC;
GRANT SELECT ON repuesto_guardado TO taller_admin,taller_mecanico;
GRANT INSERT(taller_id,usuario_id,dtc_id,componente_id,modelo_vehiculo_id,anio,vehiculo_id,sesion_id,proveedor,id_externo,tipo_referencia,enlace,nota,clave_idempotencia,hash_solicitud)
  ON repuesto_guardado TO taller_admin,taller_mecanico;
GRANT USAGE ON SEQUENCE repuesto_guardado_id_seq TO taller_admin,taller_mecanico;
CREATE FUNCTION fn_trg_validar_repuesto_guardado() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE v_vehiculo bigint;
BEGIN
  IF NEW.sesion_id IS NOT NULL THEN
    SELECT s.vehiculo_id INTO v_vehiculo FROM public.sesion_diagnostico s
      JOIN public.falla_sesion f ON f.sesion_id=s.id AND f.taller_id=s.taller_id AND f.dtc_id=NEW.dtc_id
      WHERE s.id=NEW.sesion_id AND s.taller_id=NEW.taller_id;
    IF NOT FOUND OR NEW.vehiculo_id IS DISTINCT FROM v_vehiculo THEN
      RAISE EXCEPTION 'diagnostico o vehiculo no corresponde' USING ERRCODE='23514';
    END IF;
  END IF;
  IF NEW.vehiculo_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.vehiculo v WHERE v.id=NEW.vehiculo_id AND v.taller_id=NEW.taller_id
      AND v.modelo_vehiculo_id=NEW.modelo_vehiculo_id AND v.anio=NEW.anio
  ) THEN RAISE EXCEPTION 'modelo o anio no corresponde al vehiculo' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION fn_trg_validar_repuesto_guardado() FROM PUBLIC;
CREATE TRIGGER trg_guardado_validar BEFORE INSERT ON repuesto_guardado
  FOR EACH ROW EXECUTE FUNCTION fn_trg_validar_repuesto_guardado();
SET ROLE app_funciones;
GRANT EXECUTE ON FUNCTION public.fn_trg_auditar() TO app_owner;
SET ROLE app_owner;
CREATE TRIGGER trg_guardado_auditar AFTER INSERT ON repuesto_guardado
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar('nota','enlace','hash_solicitud');
SET ROLE app_funciones;
REVOKE EXECUTE ON FUNCTION public.fn_trg_auditar() FROM app_owner;
SET ROLE app_owner;

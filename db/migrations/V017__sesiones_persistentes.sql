-- Sesiones privadas de la API: sólo hashes de credenciales aleatorias.
CREATE TABLE sesion_acceso (
  id bigint GENERATED ALWAYS AS IDENTITY,
  taller_id bigint NOT NULL,
  usuario_id bigint NOT NULL,
  perfil text NOT NULL,
  acceso_hash text NOT NULL,
  renovacion_hash text NOT NULL,
  acceso_hasta timestamptz NOT NULL,
  renovacion_hasta timestamptz NOT NULL,
  creada_en timestamptz NOT NULL DEFAULT now(),
  revocada_en timestamptz,
  CONSTRAINT pk_sesion_acceso PRIMARY KEY(id),
  CONSTRAINT uq_sesion_acceso_taller UNIQUE(id,taller_id),
  CONSTRAINT uq_sesion_acceso_acceso UNIQUE(acceso_hash),
  CONSTRAINT uq_sesion_acceso_renovacion UNIQUE(renovacion_hash),
  CONSTRAINT ck_sesion_acceso_perfil CHECK(perfil IN ('propietario','mecanico')),
  CONSTRAINT ck_sesion_acceso_hash CHECK(acceso_hash ~ '^[a-f0-9]{64}$' AND renovacion_hash ~ '^[a-f0-9]{64}$' AND acceso_hash<>renovacion_hash),
  CONSTRAINT ck_sesion_acceso_vencimiento CHECK(acceso_hasta<=renovacion_hasta AND creada_en<renovacion_hasta),
  CONSTRAINT fk_sesion_acceso_usuario FOREIGN KEY(usuario_id,taller_id) REFERENCES usuario(id,taller_id) ON DELETE RESTRICT
);
CREATE TABLE renovacion_consumida (
  hash text NOT NULL,
  sesion_id bigint NOT NULL,
  taller_id bigint NOT NULL,
  usada_en timestamptz NOT NULL DEFAULT now(),
  vence_en timestamptz NOT NULL,
  CONSTRAINT pk_renovacion_consumida PRIMARY KEY(hash),
  CONSTRAINT ck_renovacion_consumida_hash CHECK(hash ~ '^[a-f0-9]{64}$'),
  CONSTRAINT fk_renovacion_consumida_sesion FOREIGN KEY(sesion_id,taller_id) REFERENCES sesion_acceso(id,taller_id) ON DELETE RESTRICT
);
CREATE INDEX ix_sesion_acceso_usuario ON sesion_acceso(taller_id,usuario_id);
CREATE INDEX ix_sesion_acceso_vencimiento ON sesion_acceso(renovacion_hasta);
CREATE INDEX ix_renovacion_consumida_sesion ON renovacion_consumida(taller_id,sesion_id);
ALTER TABLE sesion_acceso ENABLE ROW LEVEL SECURITY;
ALTER TABLE sesion_acceso FORCE ROW LEVEL SECURITY;
ALTER TABLE renovacion_consumida ENABLE ROW LEVEL SECURITY;
ALTER TABLE renovacion_consumida FORCE ROW LEVEL SECURITY;
-- Igual que usuario_credencial: sin políticas ni acceso directo para roles de taller.
REVOKE ALL ON sesion_acceso,renovacion_consumida FROM PUBLIC;
GRANT SELECT,INSERT,UPDATE,DELETE ON sesion_acceso,renovacion_consumida TO app_funciones;
GRANT USAGE ON SEQUENCE sesion_acceso_id_seq TO app_funciones;
COMMENT ON TABLE sesion_acceso IS 'Sesión privada de API persistente. Hashes SHA-256; nunca tokens ni credenciales Google. Acceso sólo mediante función de autenticación.';
COMMENT ON TABLE renovacion_consumida IS 'Hashes ya consumidos para detectar repetición de credenciales de renovación; se eliminan al vencer la familia.';
COMMENT ON COLUMN sesion_acceso.id IS 'Identidad interna de la familia, no expuesta al cliente.';
COMMENT ON COLUMN sesion_acceso.taller_id IS 'Taller validado al emitir, con FK compuesta al usuario.';
COMMENT ON COLUMN sesion_acceso.usuario_id IS 'Usuario autenticado; se revalidan actividad y perfil.';
COMMENT ON COLUMN sesion_acceso.perfil IS 'Perfil al emitir; cualquier cambio invalida la familia.';
COMMENT ON COLUMN sesion_acceso.acceso_hash IS 'SHA-256 del token de acceso de 256 bits.';
COMMENT ON COLUMN sesion_acceso.renovacion_hash IS 'SHA-256 del token rotatorio guardado en cookie HttpOnly.';
COMMENT ON COLUMN sesion_acceso.acceso_hasta IS 'Vencimiento corto del acceso, nunca posterior al absoluto.';
COMMENT ON COLUMN sesion_acceso.renovacion_hasta IS 'Límite absoluto de la familia, sin extensión por uso.';
COMMENT ON COLUMN sesion_acceso.creada_en IS 'Emisión de la familia en el reloj del servidor.';
COMMENT ON COLUMN sesion_acceso.revocada_en IS 'Revocación por cierre de sesión, repetición o identidad inhabilitada.';
COMMENT ON COLUMN renovacion_consumida.hash IS 'Hash irreversible del token de renovación usado.';
COMMENT ON COLUMN renovacion_consumida.sesion_id IS 'Familia de sesión que consumió el token.';
COMMENT ON COLUMN renovacion_consumida.taller_id IS 'Taller protegido por FK compuesta; no visible a roles operativos.';
COMMENT ON COLUMN renovacion_consumida.usada_en IS 'Instante de consumo; tolerancia de diez segundos a solicitudes simultáneas, sin emitir credenciales con un token usado.';
COMMENT ON COLUMN renovacion_consumida.vence_en IS 'Vencimiento absoluto de la familia para limpieza.';

CREATE FUNCTION fn_sesion_acceso(p_operacion text,p_datos jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE s public.sesion_acceso; u public.usuario; t public.taller;
  consumido public.renovacion_consumida; instante timestamptz:=clock_timestamp();
  caducadas bigint[];
  capacidad integer;
  segundos integer; limite integer; a text:=p_datos->>'acceso'; r text:=p_datos->>'renovacion';
  na text:=p_datos->>'nuevo_acceso'; nr text:=p_datos->>'nueva_renovacion';
BEGIN
  IF public.fn_contexto_rol()<>'app_backend_user' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Sólo autenticación de API';
  END IF;
  IF p_operacion='emitir' THEN
    segundos:=(p_datos->>'segundos')::integer;
    limite:=(p_datos->>'limite')::integer;
    capacidad:=COALESCE((p_datos->>'capacidad')::integer,10000);
    IF a IS NULL OR r IS NULL OR a !~ '^[a-f0-9]{64}$' OR r !~ '^[a-f0-9]{64}$' OR a=r
      OR segundos IS NULL OR segundos NOT BETWEEN 1 AND 3600
      OR limite IS NULL OR limite NOT BETWEEN segundos AND 604800
      OR capacidad NOT BETWEEN 1 AND 100000 THEN
      RETURN jsonb_build_object('status','invalid');
    END IF;
    SELECT * INTO u FROM public.usuario WHERE id=(p_datos->>'usuario')::bigint AND taller_id=(p_datos->>'taller')::bigint;
    IF NOT FOUND OR p_datos->>'perfil' IS NULL OR p_datos->>'perfil' NOT IN ('propietario','mecanico')
      OR public.fn_perfil_usuario(u.id,u.taller_id) IS DISTINCT FROM (p_datos->>'perfil') THEN
      RETURN jsonb_build_object('status','invalid');
    END IF;
    -- Serializa emisión para respetar capacidad compartida entre instancias.
    PERFORM pg_advisory_xact_lock(170017);
    -- Limpieza acotada a familias vencidas; no toca sesiones activas.
    SELECT array_agg(id) INTO caducadas FROM
      (SELECT id FROM public.sesion_acceso WHERE renovacion_hasta<=instante ORDER BY id LIMIT 500 FOR UPDATE SKIP LOCKED) vencidas;
    DELETE FROM public.renovacion_consumida WHERE sesion_id=ANY(caducadas);
    DELETE FROM public.sesion_acceso WHERE id=ANY(caducadas);
    IF (SELECT count(*) FROM public.sesion_acceso WHERE revocada_en IS NULL AND renovacion_hasta>instante)>=capacidad THEN
      RETURN jsonb_build_object('status','capacity');
    END IF;
    INSERT INTO public.sesion_acceso(taller_id,usuario_id,perfil,acceso_hash,renovacion_hash,acceso_hasta,renovacion_hasta)
      VALUES(u.taller_id,u.id,p_datos->>'perfil',a,r,instante+make_interval(secs=>segundos),instante+make_interval(secs=>limite)) RETURNING * INTO s;
  ELSIF p_operacion='resolver' THEN
    SELECT * INTO s FROM public.sesion_acceso WHERE acceso_hash=a;
    IF NOT FOUND OR s.acceso_hasta<=instante THEN RETURN jsonb_build_object('status','invalid'); END IF;
  ELSIF p_operacion='renovar' THEN
    IF r IS NULL OR r !~ '^[a-f0-9]{64}$' OR na IS NULL OR nr IS NULL
      OR na !~ '^[a-f0-9]{64}$' OR nr !~ '^[a-f0-9]{64}$' OR na=nr OR r=nr THEN
      RETURN jsonb_build_object('status','invalid');
    END IF;
    SELECT * INTO s FROM public.sesion_acceso WHERE renovacion_hash=r FOR UPDATE;
    IF NOT FOUND THEN
      SELECT * INTO consumido FROM public.renovacion_consumida WHERE hash=r;
      IF FOUND THEN
        SELECT * INTO s FROM public.sesion_acceso WHERE id=consumido.sesion_id FOR UPDATE;
        IF s.revocada_en IS NOT NULL OR s.renovacion_hasta<=instante THEN RETURN jsonb_build_object('status','invalid'); END IF;
        -- Un uso concurrente no recibe acceso ni revoca inmediatamente otra pestaña.
        IF consumido.usada_en>instante-interval '10 seconds' THEN RETURN jsonb_build_object('status','retry'); END IF;
        UPDATE public.sesion_acceso SET revocada_en=COALESCE(revocada_en,instante) WHERE id=consumido.sesion_id;
      END IF;
      RETURN jsonb_build_object('status','invalid');
    END IF;
  ELSIF p_operacion='revocar' THEN
    UPDATE public.sesion_acceso SET revocada_en=COALESCE(revocada_en,instante)
      WHERE acceso_hash=a OR renovacion_hash=r OR id IN(SELECT sesion_id FROM public.renovacion_consumida WHERE hash=r);
    RETURN jsonb_build_object('status','revoked');
  ELSE RETURN jsonb_build_object('status','invalid'); END IF;
  IF s.revocada_en IS NOT NULL OR s.renovacion_hasta<=instante THEN RETURN jsonb_build_object('status','invalid'); END IF;
  SELECT * INTO u FROM public.usuario WHERE id=s.usuario_id AND taller_id=s.taller_id;
  SELECT * INTO t FROM public.taller WHERE id=s.taller_id;
  IF NOT u.activo OR NOT t.activo OR public.fn_perfil_usuario(u.id,u.taller_id) IS DISTINCT FROM s.perfil THEN
    UPDATE public.sesion_acceso SET revocada_en=COALESCE(revocada_en,instante) WHERE id=s.id;
    RETURN jsonb_build_object('status','invalid');
  END IF;
  IF p_operacion='renovar' THEN
    segundos:=(p_datos->>'segundos')::integer;
    IF segundos IS NULL OR segundos NOT BETWEEN 1 AND 3600 THEN RETURN jsonb_build_object('status','invalid'); END IF;
    INSERT INTO public.renovacion_consumida(hash,sesion_id,taller_id,usada_en,vence_en)
      VALUES(r,s.id,s.taller_id,instante,s.renovacion_hasta);
    UPDATE public.sesion_acceso SET acceso_hash=na,renovacion_hash=nr,
      acceso_hasta=LEAST(instante+make_interval(secs=>segundos),renovacion_hasta) WHERE id=s.id RETURNING * INTO s;
  END IF;
  RETURN jsonb_build_object('status','authenticated','usuario_id',u.id,'taller_id',t.id,
    'usuario_id_publico',u.id_publico,'taller_id_publico',t.id_publico,'nombre',u.nombre,'perfil',s.perfil,
    'expires_at',s.acceso_hasta,'refresh_expires_at',s.renovacion_hasta);
END;
$$;
ALTER FUNCTION fn_sesion_acceso(text,jsonb) OWNER TO app_funciones;
SET ROLE app_funciones;
REVOKE ALL ON FUNCTION fn_sesion_acceso(text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_sesion_acceso(text,jsonb) TO app_backend_user;
COMMENT ON FUNCTION fn_sesion_acceso(text,jsonb) IS 'Emite, resuelve, rota y revoca familias opacas con expiración absoluta, protección de repetición y revalidación de perfil. No acepta tokens sin hash.';
SET ROLE app_owner;

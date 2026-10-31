-- Alta de talleres, identidades Google e invitaciones. Aplicar UNA vez, con migrate.sh V011.
-- Las funciones públicas de acceso sólo se conceden al backend confiable,
-- que verifica firma, audiencia, nonce y expiración antes de llamarlas.
CREATE TABLE identidad_externa (
  proveedor text NOT NULL CHECK (proveedor = 'google'),
  sujeto text NOT NULL CHECK (length(sujeto) BETWEEN 1 AND 255),
  usuario_id bigint NOT NULL,
  taller_id bigint NOT NULL,
  CONSTRAINT fk_identidad_externa_usuario FOREIGN KEY (usuario_id,taller_id)
    REFERENCES usuario(id,taller_id) ON DELETE RESTRICT,
  creado_en timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (proveedor, sujeto), UNIQUE (proveedor, usuario_id)
);
ALTER TABLE identidad_externa ENABLE ROW LEVEL SECURITY;
ALTER TABLE identidad_externa FORCE ROW LEVEL SECURITY;
REVOKE ALL ON identidad_externa FROM PUBLIC;
GRANT SELECT, INSERT ON identidad_externa TO app_funciones;

CREATE TABLE invitacion_taller (
  id bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT pk_invitacion_taller PRIMARY KEY,
  id_publico uuid NOT NULL DEFAULT gen_random_uuid()
    CONSTRAINT uq_invitacion_taller_id_publico UNIQUE,
  taller_id bigint NOT NULL REFERENCES taller(id) ON DELETE RESTRICT,
  email text NOT NULL CHECK (email = lower(btrim(email)) AND length(email) <= 254
    AND email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  rol tipo_rol_usuario NOT NULL,
  token_hash text NOT NULL UNIQUE CHECK (token_hash ~ '^[a-f0-9]{64}$'),
  invitado_por bigint NOT NULL,
  creado_en timestamptz NOT NULL DEFAULT now(),
  vence_en timestamptz NOT NULL DEFAULT now() + interval '7 days',
  aceptada_en timestamptz,
  revocada_en timestamptz,
  CONSTRAINT fk_invitacion_autor FOREIGN KEY (invitado_por,taller_id) REFERENCES usuario(id,taller_id) ON DELETE RESTRICT,
  CHECK (vence_en > creado_en AND vence_en <= creado_en + interval '7 days'),
  CHECK (aceptada_en IS NULL OR revocada_en IS NULL)
);
CREATE UNIQUE INDEX uq_invitacion_pendiente ON invitacion_taller(taller_id,email)
  WHERE aceptada_en IS NULL AND revocada_en IS NULL;
ALTER TABLE invitacion_taller ENABLE ROW LEVEL SECURITY;
ALTER TABLE invitacion_taller FORCE ROW LEVEL SECURITY;
CREATE POLICY pol_invitacion_taller_admin_select ON invitacion_taller FOR SELECT TO taller_admin
  USING (taller_id = (SELECT fn_contexto_taller_id()));
CREATE POLICY pol_invitacion_taller_admin_insert ON invitacion_taller FOR INSERT TO taller_admin
  WITH CHECK (taller_id = (SELECT fn_contexto_taller_id()) AND invitado_por = (SELECT fn_contexto_usuario_id()));
CREATE POLICY pol_invitacion_taller_admin_update ON invitacion_taller FOR UPDATE TO taller_admin
  USING (taller_id = (SELECT fn_contexto_taller_id()))
  WITH CHECK (taller_id = (SELECT fn_contexto_taller_id()));
REVOKE ALL ON invitacion_taller FROM PUBLIC;
GRANT SELECT ON invitacion_taller TO taller_admin;
GRANT INSERT (taller_id,email,rol,token_hash,invitado_por) ON invitacion_taller TO taller_admin;
GRANT UPDATE (revocada_en) ON invitacion_taller TO taller_admin;
GRANT SELECT, UPDATE ON invitacion_taller TO app_funciones;
SET ROLE app_funciones;
GRANT EXECUTE ON FUNCTION fn_trg_auditar() TO app_owner;
SET ROLE app_owner;
CREATE TRIGGER trg_invitacion_auditar AFTER INSERT OR UPDATE ON invitacion_taller
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar('token_hash');
SET ROLE app_funciones;
REVOKE EXECUTE ON FUNCTION fn_trg_auditar() FROM app_owner;
SET ROLE app_owner;

-- Primer administrador: privilegios sólo dentro de esta función de alta.
GRANT INSERT ON taller, taller_configuracion, usuario TO app_funciones;
GRANT SELECT ON identidad_externa, invitacion_taller TO app_funciones;

CREATE FUNCTION fn_google_acceso(p_sujeto text, p_email text, p_nombre text,
  p_accion text DEFAULT 'login', p_taller_nombre text DEFAULT NULL,
  p_invitacion_hash text DEFAULT NULL, p_usuario_vincular bigint DEFAULT NULL,
  p_email_autoritativo boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_usuario public.usuario;
  v_taller public.taller;
  v_invitacion public.invitacion_taller;
  v_vinculado bigint;
BEGIN
  IF p_sujeto IS NULL OR length(p_sujeto) NOT BETWEEN 1 AND 255
    OR p_email IS NULL OR p_nombre IS NULL OR length(btrim(p_nombre)) NOT BETWEEN 1 AND 200
    OR p_email <> lower(btrim(p_email)) THEN
    RAISE EXCEPTION 'invalid_google_identity' USING ERRCODE = 'RE020';
  END IF;
  -- Serializa altas concurrentes por correo y sujeto. La unicidad es la segunda barrera.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_email, 11));
  SELECT ie.usuario_id INTO v_vinculado FROM public.identidad_externa ie
    WHERE ie.proveedor='google' AND ie.sujeto=p_sujeto;
  IF v_vinculado IS NOT NULL THEN
    SELECT u.* INTO v_usuario FROM public.usuario u WHERE u.id=v_vinculado;
    IF p_accion <> 'login' THEN
      RETURN jsonb_build_object('status','already_linked');
    END IF;
  ELSE
    SELECT u.* INTO v_usuario FROM public.usuario u WHERE u.email=p_email;
    IF p_accion='login' THEN
      RETURN jsonb_build_object('status','onboarding','requires_link',v_usuario.id IS NOT NULL);
    ELSIF p_accion='link' THEN
      IF v_usuario.id IS NULL OR p_usuario_vincular IS DISTINCT FROM v_usuario.id
        OR NOT v_usuario.activo THEN
        RETURN jsonb_build_object('status','link_required');
      END IF;
    ELSIF p_accion='register' THEN
      IF NOT p_email_autoritativo THEN RETURN jsonb_build_object('status','email_verification_required'); END IF;
      IF v_usuario.id IS NOT NULL THEN RETURN jsonb_build_object('status','link_required'); END IF;
      IF p_taller_nombre IS NULL OR length(btrim(p_taller_nombre)) NOT BETWEEN 2 AND 120 THEN
        RETURN jsonb_build_object('status','invalid_workshop_name');
      END IF;
      INSERT INTO public.taller(nombre) VALUES (btrim(p_taller_nombre)) RETURNING * INTO v_taller;
      INSERT INTO public.taller_configuracion(taller_id) VALUES(v_taller.id);
      INSERT INTO public.usuario(taller_id,email,nombre,rol)
        VALUES(v_taller.id,p_email,btrim(p_nombre),'admin') RETURNING * INTO v_usuario;
    ELSIF p_accion='accept' THEN
      IF NOT p_email_autoritativo THEN RETURN jsonb_build_object('status','email_verification_required'); END IF;
      IF v_usuario.id IS NOT NULL THEN RETURN jsonb_build_object('status','link_required'); END IF;
      SELECT i.* INTO v_invitacion FROM public.invitacion_taller i
        WHERE i.token_hash=p_invitacion_hash FOR UPDATE;
      IF NOT FOUND OR v_invitacion.email<>p_email OR v_invitacion.aceptada_en IS NOT NULL
        OR v_invitacion.revocada_en IS NOT NULL OR v_invitacion.vence_en<=now() THEN
        RETURN jsonb_build_object('status','invalid_invitation');
      END IF;
      SELECT t.* INTO v_taller FROM public.taller t WHERE t.id=v_invitacion.taller_id;
      IF NOT v_taller.activo THEN RETURN jsonb_build_object('status','account_disabled'); END IF;
      INSERT INTO public.usuario(taller_id,email,nombre,rol)
        VALUES(v_taller.id,p_email,btrim(p_nombre),v_invitacion.rol) RETURNING * INTO v_usuario;
      UPDATE public.invitacion_taller SET aceptada_en=now() WHERE id_publico=v_invitacion.id_publico;
    ELSE
      RAISE EXCEPTION 'invalid_action' USING ERRCODE = 'RE020';
    END IF;
    -- Un usuario existente sólo vincula Google después de autenticar su contraseña.
    IF EXISTS(SELECT 1 FROM public.identidad_externa ie WHERE ie.proveedor='google' AND ie.usuario_id=v_usuario.id) THEN
      RETURN jsonb_build_object('status','already_linked');
    END IF;
    INSERT INTO public.identidad_externa(proveedor,sujeto,usuario_id,taller_id)
      VALUES('google',p_sujeto,v_usuario.id,v_usuario.taller_id);
  END IF;
  SELECT t.* INTO v_taller FROM public.taller t WHERE t.id=v_usuario.taller_id;
  IF NOT v_usuario.activo OR NOT v_taller.activo THEN
    RAISE EXCEPTION 'account_disabled' USING ERRCODE='RE021';
  END IF;
  PERFORM public.fn_registrar_auditoria(v_taller.id,v_usuario.id,'LOGIN','usuario',v_usuario.id,
    NULL,jsonb_build_object('proveedor','google'),'exito');
  RETURN jsonb_build_object('status','authenticated','usuario_id',v_usuario.id,
    'usuario_id_publico',v_usuario.id_publico,'taller_id',v_taller.id,
    'taller_id_publico',v_taller.id_publico,'rol',v_usuario.rol,'nombre',v_usuario.nombre);
END;
$$;
ALTER FUNCTION fn_google_acceso(text,text,text,text,text,text,bigint,boolean) OWNER TO app_funciones;
SET ROLE app_funciones;
REVOKE ALL ON FUNCTION fn_google_acceso(text,text,text,text,text,text,bigint,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_google_acceso(text,text,text,text,text,text,bigint,boolean) TO app_backend_user;
SET ROLE app_owner;

-- Un dueño también puede trabajar como técnico; conserva su rol admin en auditoría.
-- RESET ROLE vuelve al superusuario que ejecuta la migración, nunca al usuario de la API.
RESET ROLE;
GRANT taller_mecanico TO taller_admin WITH INHERIT TRUE, SET FALSE;
SET ROLE app_owner;


-- Nombres explícitos y documentación del contrato del catálogo PostgreSQL.
DO $$
DECLARE r record; v_prefijo text;
BEGIN
  FOR r IN SELECT c.conname,c.contype,t.relname
    FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid
    JOIN pg_namespace n ON n.oid=t.relnamespace
    WHERE n.nspname='public' AND t.relname IN ('identidad_externa','invitacion_taller')
      AND c.contype IN ('p','u','f','c') AND c.conname !~ '^(pk|uq|fk|ck)_'
  LOOP
    v_prefijo:=CASE r.contype WHEN 'p' THEN 'pk' WHEN 'u' THEN 'uq' WHEN 'f' THEN 'fk' ELSE 'ck' END;
    EXECUTE format('ALTER TABLE public.%I RENAME CONSTRAINT %I TO %I',r.relname,r.conname,v_prefijo||'_'||r.conname);
  END LOOP;
END;
$$;
COMMENT ON TABLE identidad_externa IS 'Identidades externas verificadas; sin acceso directo de los roles de taller.';
COMMENT ON COLUMN identidad_externa.proveedor IS 'Proveedor de identidad admitido.';
COMMENT ON COLUMN identidad_externa.sujeto IS 'Identificador estable sub de Google; no es un correo.';
COMMENT ON COLUMN identidad_externa.usuario_id IS 'Usuario vinculado a esta identidad.';
COMMENT ON COLUMN identidad_externa.taller_id IS 'Taller del usuario, protegido por clave foránea compuesta.';
COMMENT ON COLUMN identidad_externa.creado_en IS 'Fecha de vinculación en UTC.';
COMMENT ON TABLE invitacion_taller IS 'Invitaciones de incorporación; el enlace se consume una sola vez.';
COMMENT ON COLUMN invitacion_taller.id IS 'Identificador interno de auditoría.';
COMMENT ON COLUMN invitacion_taller.id_publico IS 'Identificador UUID expuesto por la API.';
COMMENT ON COLUMN invitacion_taller.taller_id IS 'Taller que invita.';
COMMENT ON COLUMN invitacion_taller.email IS 'Correo normalizado del destinatario.';
COMMENT ON COLUMN invitacion_taller.rol IS 'Rol autorizado por el administrador que invita.';
COMMENT ON COLUMN invitacion_taller.token_hash IS 'Hash SHA-256 del token; el token original nunca se persiste.';
COMMENT ON COLUMN invitacion_taller.invitado_por IS 'Administrador que creó la invitación, perteneciente al mismo taller.';
COMMENT ON COLUMN invitacion_taller.creado_en IS 'Fecha de creación en UTC.';
COMMENT ON COLUMN invitacion_taller.vence_en IS 'Vencimiento absoluto, hasta siete días desde creación.';
COMMENT ON COLUMN invitacion_taller.aceptada_en IS 'Fecha de aceptación; nulo si no se utilizó.';
COMMENT ON COLUMN invitacion_taller.revocada_en IS 'Fecha de revocación; nulo si no se canceló.';

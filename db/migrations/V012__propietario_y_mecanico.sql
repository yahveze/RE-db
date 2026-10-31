-- V012: propiedad explícita y dos perfiles de aplicación, sin reescribir roles históricos.
ALTER TABLE taller ADD COLUMN propietario_usuario_id bigint;
ALTER TABLE taller ADD COLUMN propietario_asignado_en timestamptz;
ALTER TABLE taller ADD CONSTRAINT fk_taller_propietario
  FOREIGN KEY (propietario_usuario_id,id) REFERENCES usuario(id,taller_id) ON DELETE RESTRICT;
ALTER TABLE taller ADD CONSTRAINT ck_taller_propietario_fecha
  CHECK ((propietario_usuario_id IS NULL) = (propietario_asignado_en IS NULL));
COMMENT ON COLUMN taller.propietario_usuario_id IS 'Propietario explícito del taller. NULL en talleres heredados pendientes de asignación verificada.';
COMMENT ON COLUMN taller.propietario_asignado_en IS 'Fecha UTC de asignación de la propiedad.';
GRANT UPDATE(propietario_usuario_id,propietario_asignado_en) ON taller TO app_funciones;

CREATE VIEW v_usuario_perfil WITH (security_invoker=true) AS
SELECT u.id,u.id_publico,u.taller_id,u.nombre,u.rol AS rol_tecnico,u.activo,
  CASE WHEN u.activo AND t.activo AND u.rol='admin' AND t.propietario_usuario_id=u.id THEN 'propietario'
       WHEN u.activo AND t.activo AND u.rol='mecanico' THEN 'mecanico'
       ELSE NULL END::text AS perfil
FROM usuario u JOIN taller t ON t.id=u.taller_id;
COMMENT ON VIEW v_usuario_perfil IS 'Perfiles de negocio derivados de propiedad y rol técnico. NULL significa perfil heredado no habilitado.';
GRANT SELECT ON v_usuario_perfil TO app_funciones,taller_admin,taller_mecanico;

CREATE FUNCTION fn_perfil_usuario(p_usuario bigint,p_taller bigint) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp
AS $$
  SELECT v.perfil FROM public.v_usuario_perfil v
  WHERE v.id=p_usuario AND v.taller_id=p_taller
    AND (public.fn_contexto_rol()='app_backend_user' OR
      (p_usuario=public.fn_contexto_usuario_id() AND p_taller=public.fn_contexto_taller_id()));
$$;
ALTER FUNCTION fn_perfil_usuario(bigint,bigint) OWNER TO app_funciones;

CREATE FUNCTION fn_es_propietario() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp
AS $$
  SELECT public.fn_contexto_rol()='taller_admin' AND EXISTS(
    SELECT 1 FROM public.taller t JOIN public.usuario u
      ON u.id=t.propietario_usuario_id AND u.taller_id=t.id
    WHERE t.id=public.fn_contexto_taller_id() AND u.id=public.fn_contexto_usuario_id()
      AND t.activo AND u.activo AND u.rol='admin');
$$;
ALTER FUNCTION fn_es_propietario() OWNER TO app_funciones;

CREATE FUNCTION fn_autenticar_aplicacion(p_email text,p_password text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp
AS $$
DECLARE a record; v_perfil text;
BEGIN
  SELECT * INTO a FROM public.fn_autenticar_usuario(p_email,p_password);
  IF NOT a.autenticado THEN RETURN jsonb_build_object('status','invalid_credentials'); END IF;
  v_perfil:=public.fn_perfil_usuario(a.usuario_id,a.taller_id);
  IF v_perfil IS NULL THEN
    PERFORM public.fn_registrar_auditoria(a.taller_id,a.usuario_id,'LOGIN_FALLIDO','usuario',a.usuario_id,
      NULL,jsonb_build_object('motivo','perfil_no_habilitado'),'denegado');
    RETURN jsonb_build_object('status','profile_not_enabled');
  END IF;
  RETURN jsonb_build_object('status','authenticated','usuario_id',a.usuario_id,
    'usuario_id_publico',a.usuario_id_publico,'taller_id',a.taller_id,
    'taller_id_publico',a.taller_id_publico,'perfil',v_perfil,'nombre',a.nombre);
END;
$$;
ALTER FUNCTION fn_autenticar_aplicacion(text,text) OWNER TO app_funciones;
SET ROLE app_funciones;
REVOKE ALL ON FUNCTION fn_perfil_usuario(bigint,bigint),fn_es_propietario(),fn_autenticar_aplicacion(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_perfil_usuario(bigint,bigint) TO app_backend_user,taller_admin,taller_mecanico;
GRANT EXECUTE ON FUNCTION fn_es_propietario() TO taller_admin,app_owner;
GRANT EXECUTE ON FUNCTION fn_autenticar_aplicacion(text,text) TO app_backend_user;
SET ROLE app_owner;

CREATE FUNCTION fn_trg_propiedad_taller() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,public,pg_temp AS $$
BEGIN
  IF OLD.propietario_usuario_id IS NOT NULL AND NEW.propietario_usuario_id IS DISTINCT FROM OLD.propietario_usuario_id THEN
    RAISE EXCEPTION 'la propiedad no se modifica mediante actualizaciones generales' USING ERRCODE='RE024';
  END IF;
  IF NEW.propietario_usuario_id IS DISTINCT FROM OLD.propietario_usuario_id THEN
    IF NOT EXISTS(SELECT 1 FROM public.usuario u WHERE u.id=NEW.propietario_usuario_id
      AND u.taller_id=NEW.id AND u.rol='admin' AND u.activo) THEN
      RAISE EXCEPTION 'el propietario debe ser un administrador activo del mismo taller' USING ERRCODE='RE024';
    END IF;
    NEW.propietario_asignado_en:=now();
  ELSE NEW.propietario_asignado_en:=OLD.propietario_asignado_en;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_taller_propiedad BEFORE UPDATE OF propietario_usuario_id,propietario_asignado_en ON taller
  FOR EACH ROW EXECUTE FUNCTION fn_trg_propiedad_taller();

CREATE FUNCTION fn_trg_gestion_propietario() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,public,pg_temp AS $$
BEGIN
  IF current_user IN ('app_owner','app_funciones') OR EXISTS(SELECT 1 FROM pg_roles WHERE rolname=current_user AND rolsuper) THEN RETURN NEW; END IF;
  IF NOT public.fn_es_propietario() THEN RAISE EXCEPTION 'se requiere el propietario del taller' USING ERRCODE='RE022'; END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_taller_configuracion_propietario BEFORE UPDATE ON taller_configuracion
  FOR EACH ROW EXECUTE FUNCTION fn_trg_gestion_propietario();
CREATE TRIGGER trg_dispositivo_diagnostico_propietario BEFORE INSERT OR UPDATE ON dispositivo_diagnostico
  FOR EACH ROW EXECUTE FUNCTION fn_trg_gestion_propietario();
CREATE TRIGGER trg_invitacion_taller_propietario BEFORE INSERT OR UPDATE ON invitacion_taller
  FOR EACH ROW EXECUTE FUNCTION fn_trg_gestion_propietario();
CREATE TRIGGER trg_solicitud_derecho_titular_propietario BEFORE INSERT OR UPDATE ON solicitud_derecho_titular
  FOR EACH ROW EXECUTE FUNCTION fn_trg_gestion_propietario();

CREATE FUNCTION fn_trg_usuario_propietario() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,public,pg_temp AS $$
BEGIN
  IF current_user IN ('app_owner','app_funciones') OR EXISTS(SELECT 1 FROM pg_roles WHERE rolname=current_user AND rolsuper) THEN RETURN NEW; END IF;
  IF NOT public.fn_es_propietario() THEN RAISE EXCEPTION 'se requiere el propietario del taller' USING ERRCODE='RE022'; END IF;
  IF NEW.taller_id IS DISTINCT FROM public.fn_contexto_taller_id() THEN
    RAISE EXCEPTION 'no se puede escribir en otro taller' USING ERRCODE='42501';
  END IF;
  IF TG_OP='UPDATE' AND EXISTS(SELECT 1 FROM public.taller t WHERE t.propietario_usuario_id=OLD.id)
     AND (NOT NEW.activo OR NEW.rol<>'admin') THEN
    RAISE EXCEPTION 'no se puede desactivar ni degradar al propietario' USING ERRCODE='RE024';
  END IF;
  IF (TG_OP='INSERT' OR NEW.rol IS DISTINCT FROM OLD.rol) AND NEW.rol<>'mecanico' THEN
    RAISE EXCEPTION 'sólo se incorporan mecánicos al taller' USING ERRCODE='RE023';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_usuario_propietario BEFORE INSERT OR UPDATE ON usuario
  FOR EACH ROW EXECUTE FUNCTION fn_trg_usuario_propietario();

-- Las invitaciones heredadas no operativas se conservan, revocadas.
SET ROLE app_funciones;
UPDATE invitacion_taller SET revocada_en=now() WHERE rol<>'mecanico'
  AND aceptada_en IS NULL AND revocada_en IS NULL;
SET ROLE app_owner;
CREATE FUNCTION fn_trg_invitacion_perfil() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,public,pg_temp AS $$
BEGIN
  IF NEW.rol<>'mecanico' THEN RAISE EXCEPTION 'sólo se invita a mecánicos' USING ERRCODE='RE023'; END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_invitacion_taller_perfil BEFORE INSERT OR UPDATE OF rol ON invitacion_taller
  FOR EACH ROW EXECUTE FUNCTION fn_trg_invitacion_perfil();

SET ROLE app_funciones;
GRANT EXECUTE ON FUNCTION fn_trg_auditar() TO app_owner;
SET ROLE app_owner;
CREATE TRIGGER trg_taller_propiedad_auditar AFTER UPDATE OF propietario_usuario_id ON taller
  FOR EACH ROW WHEN (OLD.propietario_usuario_id IS DISTINCT FROM NEW.propietario_usuario_id)
  EXECUTE FUNCTION fn_trg_auditar();
SET ROLE app_funciones;
REVOKE EXECUTE ON FUNCTION fn_trg_auditar() FROM app_owner;
SET ROLE app_owner;

SET ROLE app_funciones;
-- Únicamente las dos identidades ficticias definidas en la semilla 02.
UPDATE taller t SET propietario_usuario_id=u.id FROM usuario u
WHERE u.taller_id=t.id AND u.rol='admin' AND u.activo AND t.propietario_usuario_id IS NULL
  AND ((t.nombre='Taller Mecánico Los Aromos' AND u.email='admin@losaromos.example' AND u.nombre='Carla Fuentes')
    OR (t.nombre='Servicio Automotriz Ñuble' AND u.email='admin@nuble.example' AND u.nombre='Rodrigo Henríquez'));
SET ROLE app_owner;

SET ROLE app_funciones;
CREATE OR REPLACE FUNCTION fn_google_acceso(p_sujeto text, p_email text, p_nombre text,
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
  v_perfil text;
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
      UPDATE public.taller SET propietario_usuario_id=v_usuario.id WHERE id=v_taller.id;
    ELSIF p_accion='accept' THEN
      IF NOT p_email_autoritativo THEN RETURN jsonb_build_object('status','email_verification_required'); END IF;
      IF v_usuario.id IS NOT NULL THEN RETURN jsonb_build_object('status','link_required'); END IF;
      SELECT i.* INTO v_invitacion FROM public.invitacion_taller i
        WHERE i.token_hash=p_invitacion_hash FOR UPDATE;
      IF NOT FOUND OR v_invitacion.rol<>'mecanico' OR v_invitacion.email<>p_email OR v_invitacion.aceptada_en IS NOT NULL
        OR v_invitacion.revocada_en IS NOT NULL OR v_invitacion.vence_en<=now() THEN
        RETURN jsonb_build_object('status','invalid_invitation');
      END IF;
      SELECT t.* INTO v_taller FROM public.taller t WHERE t.id=v_invitacion.taller_id;
      IF NOT v_taller.activo THEN RETURN jsonb_build_object('status','account_disabled'); END IF;
      IF v_taller.propietario_usuario_id IS NULL OR v_invitacion.invitado_por IS DISTINCT FROM v_taller.propietario_usuario_id THEN
        RETURN jsonb_build_object('status','invalid_invitation');
      END IF;
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
  v_perfil:=public.fn_perfil_usuario(v_usuario.id,v_taller.id);
  IF v_perfil IS NULL THEN RETURN jsonb_build_object('status','profile_not_enabled'); END IF;
  PERFORM public.fn_registrar_auditoria(v_taller.id,v_usuario.id,'LOGIN','usuario',v_usuario.id,
    NULL,jsonb_build_object('proveedor','google'),'exito');
  RETURN jsonb_build_object('status','authenticated','usuario_id',v_usuario.id,
    'usuario_id_publico',v_usuario.id_publico,'taller_id',v_taller.id,
    'taller_id_publico',v_taller.id_publico,'rol',v_usuario.rol,'perfil',v_perfil,'nombre',v_usuario.nombre);
END;
$$;

SET ROLE app_owner;

SET ROLE app_funciones;
CREATE OR REPLACE FUNCTION fn_establecer_contrasena(
  p_usuario_id bigint,
  p_contrasena text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_taller_id bigint := fn_contexto_taller_id();
BEGIN
  IF NOT public.fn_es_propietario() THEN
    RAISE EXCEPTION 'operacion reservada al administrador con contexto de taller'
      USING ERRCODE = 'RE006';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id = p_usuario_id AND u.taller_id = v_taller_id) THEN
    RAISE EXCEPTION 'el usuario % no existe o no es visible', p_usuario_id
      USING ERRCODE = 'RE009';
  END IF;

  -- 72 bytes es el limite de bcrypt: una contrasena mas larga se truncaria
  -- en silencio, por eso se rechaza.
  IF p_contrasena IS NULL OR char_length(p_contrasena) < 8 OR octet_length(p_contrasena) > 72 THEN
    RAISE EXCEPTION 'la contrasena debe tener entre 8 caracteres y 72 bytes'
      USING ERRCODE = 'RE011';
  END IF;

  INSERT INTO usuario_credencial AS c (usuario_id, hash_contrasena)
  VALUES (p_usuario_id, crypt(p_contrasena, gen_salt('bf', 10)))
  ON CONFLICT (usuario_id) DO UPDATE
    SET hash_contrasena   = EXCLUDED.hash_contrasena,
        intentos_fallidos = 0,
        bloqueado_hasta   = NULL;

  -- usuario_credencial no tiene trigger de auditoria (jamas debe copiarse un
  -- hash); se deja constancia del hecho, sin datos.
  PERFORM fn_registrar_auditoria(v_taller_id, fn_contexto_usuario_id(), 'UPDATE',
                                 'usuario_credencial', p_usuario_id, NULL, NULL, 'exito');
END;
$$;
SET ROLE app_owner;

SET ROLE app_funciones;
CREATE OR REPLACE FUNCTION fn_solicitar_supresion_titular(p_titular_id bigint) RETURNS tipo_estado_tratamiento
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_taller_id       bigint := fn_contexto_taller_id();
  v_titular         titular;
  v_retencion_anios smallint;
  v_ultima_atencion timestamptz;
  v_limite          date;
BEGIN
  IF NOT public.fn_es_propietario() THEN
    RAISE EXCEPTION 'operacion reservada al administrador con contexto de taller'
      USING ERRCODE = 'RE006';
  END IF;

  SELECT t.* INTO v_titular
  FROM   titular t
  WHERE  t.id = p_titular_id
  AND    t.taller_id = v_taller_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'el titular % no existe o no es visible', p_titular_id
      USING ERRCODE = 'RE009';
  END IF;

  IF v_titular.estado_tratamiento = 'anonimizado' THEN
    RETURN 'anonimizado';
  END IF;

  IF NOT EXISTS (
       SELECT 1
       FROM   solicitud_derecho_titular s
       WHERE  s.titular_id = p_titular_id
       AND    s.tipo = 'supresion'
       AND    s.estado IN ('recibida', 'en_proceso')
  ) THEN
    INSERT INTO solicitud_derecho_titular (taller_id, titular_id, tipo, estado, usuario_responsable_id)
    VALUES (v_taller_id, p_titular_id, 'supresion', 'en_proceso', fn_contexto_usuario_id());
  END IF;

  SELECT tc.retencion_anios INTO v_retencion_anios
  FROM   taller_configuracion tc
  WHERE  tc.taller_id = v_taller_id;

  SELECT max(s.iniciada_en) INTO v_ultima_atencion
  FROM   sesion_diagnostico s
  JOIN   vehiculo v ON v.id = s.vehiculo_id AND v.taller_id = s.taller_id
  WHERE  v.titular_id = p_titular_id
  AND    v.taller_id  = v_taller_id
  AND    s.estado <> 'cancelado';

  v_limite := (v_ultima_atencion + make_interval(years => COALESCE(v_retencion_anios, 0)))::date;

  IF v_limite IS NOT NULL AND v_limite > current_date THEN
    UPDATE titular t
    SET    estado_tratamiento = 'bloqueado',
           bloqueado_hasta    = v_limite
    WHERE  t.id = p_titular_id;
    RETURN 'bloqueado';
  END IF;

  PERFORM fn_anonimizar_titular(p_titular_id);
  RETURN 'anonimizado';
END;
$$;
SET ROLE app_owner;

-- Pruebas de permisos y persistencia. Claims sintéticos: NO prueban un login real en Google.
-- Ejecutar como superusuario con psql -v ON_ERROR_STOP=1. Todo se revierte.
BEGIN;
DO $$
DECLARE
  v_owner jsonb; v_other jsonb; v_member jsonb; v_result jsonb;
  v_email text := 'owner-' || gen_random_uuid()::text || '@gmail.com';
  v_other_email text := 'other-' || gen_random_uuid()::text || '@gmail.com';
  v_member_email text := 'member-' || gen_random_uuid()::text || '@gmail.com';
  v_invite uuid; v_count int;
BEGIN
  SET LOCAL ROLE app_backend_user;
  v_result := public.fn_google_acceso(v_email,v_email,'Dueño');
  IF v_result->>'status'<>'onboarding' THEN RAISE EXCEPTION 'Debe solicitar onboarding'; END IF;
  v_owner := public.fn_google_acceso(v_email,v_email,'Dueño','register','Taller de prueba',NULL,NULL,true);
  IF v_owner->>'status'<>'authenticated' OR v_owner->>'rol'<>'admin' THEN RAISE EXCEPTION 'Alta de dueño incorrecta'; END IF;
  v_result := public.fn_google_acceso(v_email,v_email,'Dueño');
  IF v_result->>'usuario_id'<>v_owner->>'usuario_id' THEN RAISE EXCEPTION 'Login no idempotente'; END IF;
  v_result := public.fn_google_acceso('another-subject',v_email,'Impostor','register','Otro taller',NULL,NULL,true);
  IF v_result->>'status'<>'link_required' THEN RAISE EXCEPTION 'No debe vincular sólo por email'; END IF;
  v_result := public.fn_google_acceso('untrusted','untrusted@example.test','Prueba','register','Sin verificar',NULL,NULL,false);
  IF v_result->>'status'<>'email_verification_required' THEN RAISE EXCEPTION 'Correo no autoritativo aceptado'; END IF;
  v_other := public.fn_google_acceso(v_other_email,v_other_email,'Otro dueño','register','Otro taller',NULL,NULL,true);
  SET LOCAL ROLE taller_admin;
  PERFORM set_config('app.taller_id',v_owner->>'taller_id',true);
  PERFORM set_config('app.usuario_id',v_owner->>'usuario_id',true);
  SELECT count(*) INTO v_count FROM public.taller;
  IF v_count<>1 THEN RAISE EXCEPTION 'RLS no aísla taller'; END IF;
  IF NOT has_column_privilege('taller_admin','public.sesion_diagnostico','vehiculo_id','INSERT') THEN RAISE EXCEPTION 'Dueño no puede operar'; END IF;
  INSERT INTO public.invitacion_taller(taller_id,email,rol,token_hash,invitado_por)
    VALUES((v_owner->>'taller_id')::bigint,v_member_email,'mecanico',repeat('a',64),(v_owner->>'usuario_id')::bigint)
    RETURNING id_publico INTO v_invite;
  SET LOCAL ROLE app_backend_user;
  v_result := public.fn_google_acceso('wrong','wrong@gmail.com','Otro','accept',NULL,repeat('a',64),NULL,true);
  IF v_result->>'status'<>'invalid_invitation' THEN RAISE EXCEPTION 'Aceptó correo distinto'; END IF;
  v_member := public.fn_google_acceso(v_member_email,v_member_email,'Mecánico','accept',NULL,repeat('a',64),NULL,true);
  IF v_member->>'status'<>'authenticated' OR v_member->>'rol'<>'mecanico' OR v_member->>'taller_id'<>v_owner->>'taller_id' THEN
    RAISE EXCEPTION 'Aceptación no conserva rol y taller'; END IF;
  v_result := public.fn_google_acceso(v_member_email,v_member_email,'Mecánico','accept',NULL,repeat('a',64),NULL,true);
  IF v_result->>'status'<>'already_linked' THEN RAISE EXCEPTION 'Permite reutilizar invitación'; END IF;
  SET LOCAL ROLE taller_mecanico;
  PERFORM set_config('app.taller_id',v_member->>'taller_id',true);
  PERFORM set_config('app.usuario_id',v_member->>'usuario_id',true);
  BEGIN
    PERFORM 1 FROM public.invitacion_taller;
    RAISE EXCEPTION 'Mecánico pudo leer invitaciones';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM 1 FROM public.identidad_externa;
    RAISE EXCEPTION 'Mecánico pudo leer identidades externas';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  SET LOCAL ROLE taller_admin;
  PERFORM set_config('app.taller_id',v_other->>'taller_id',true);
  PERFORM set_config('app.usuario_id',v_other->>'usuario_id',true);
  SELECT count(*) INTO v_count FROM public.invitacion_taller WHERE id_publico=v_invite;
  IF v_count<>0 THEN RAISE EXCEPTION 'Otro taller ve invitación'; END IF;
  RESET ROLE;
  -- Expiración y revocación, sin consumir ni crear usuarios.
  UPDATE public.invitacion_taller SET email='expired@gmail.com',aceptada_en=NULL,creado_en=now()-interval '2 days',vence_en=now()-interval '1 day' WHERE id_publico=v_invite;
  SET LOCAL ROLE app_backend_user;
  v_result := public.fn_google_acceso('expired','expired@gmail.com','Prueba','accept',NULL,repeat('a',64),NULL,true);
  IF v_result->>'status'<>'invalid_invitation' THEN RAISE EXCEPTION 'Invitación vencida aceptada'; END IF;
  RESET ROLE;
  UPDATE public.invitacion_taller SET email='revoked@gmail.com',vence_en=now()+interval '1 day',revocada_en=now() WHERE id_publico=v_invite;
  SET LOCAL ROLE app_backend_user;
  v_result := public.fn_google_acceso('revoked','revoked@gmail.com','Prueba','accept',NULL,repeat('a',64),NULL,true);
  IF v_result->>'status'<>'invalid_invitation' THEN RAISE EXCEPTION 'Invitación revocada aceptada'; END IF;
  RESET ROLE;
  RAISE NOTICE 'Google onboarding: alta, aislamiento, roles, correo, enlace único y revocación OK';
END;
$$;
\echo PASS | GOOGLE-01: alta, identidad, roles, aislamiento e invitaciones verificadas
ROLLBACK;

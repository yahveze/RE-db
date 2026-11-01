-- Sólo hashes sintéticos. Una transacción con ROLLBACK: no deja sesiones.
\ir incluir/inicio.sql
\echo '### 13 Sesiones persistentes'
\ir incluir/rol_backend.sql
SELECT public.fn_sesion_acceso('emitir',jsonb_build_object('usuario',:mec_1,'taller',:taller_1,'perfil','mecanico','acceso',repeat('a',64),'renovacion',repeat('b',64),'segundos',3600,'limite',604800))->>'status' AS estado \gset
\set prueba 'SES-01 emite una familia autenticada y persistente'
SELECT :'estado'='authenticated' AS ok \gset
\ir incluir/afirmar.sql
\set prueba 'SES-02 resuelve identidad y taller del usuario validado'
SELECT public.fn_sesion_acceso('resolver',jsonb_build_object('acceso',repeat('a',64)))->>'taller_id'=(:taller_1)::text AS ok \gset
\ir incluir/afirmar.sql
SELECT public.fn_sesion_acceso('renovar',jsonb_build_object('renovacion',repeat('b',64),'nuevo_acceso',repeat('c',64),'nueva_renovacion',repeat('d',64),'segundos',3600))->>'status' AS estado \gset
\set prueba 'SES-03 renovación rota acceso y cookie'
SELECT :'estado'='authenticated' AND public.fn_sesion_acceso('resolver',jsonb_build_object('acceso',repeat('a',64)))->>'status'='invalid' AS ok \gset
\ir incluir/afirmar.sql
\set prueba 'SES-04 solicitud simultánea con token usado no recibe acceso'
SELECT public.fn_sesion_acceso('renovar',jsonb_build_object('renovacion',repeat('b',64),'nuevo_acceso',repeat('e',64),'nueva_renovacion',repeat('f',64),'segundos',3600))->>'status'='retry' AS ok \gset
\ir incluir/afirmar.sql
\ir incluir/rol_plataforma.sql
UPDATE renovacion_consumida SET usada_en=clock_timestamp()-interval '11 seconds' WHERE hash=repeat('b',64);
\ir incluir/rol_backend.sql
\set prueba 'SES-05 repetición fuera de tolerancia revoca toda la familia'
SELECT public.fn_sesion_acceso('renovar',jsonb_build_object('renovacion',repeat('b',64),'nuevo_acceso',repeat('e',64),'nueva_renovacion',repeat('f',64),'segundos',3600))->>'status'='invalid'
 AND public.fn_sesion_acceso('resolver',jsonb_build_object('acceso',repeat('c',64)))->>'status'='invalid' AS ok \gset
\ir incluir/afirmar.sql
SELECT public.fn_sesion_acceso('emitir',jsonb_build_object('usuario',:mec_1,'taller',:taller_1,'perfil','mecanico','acceso',repeat('1',64),'renovacion',repeat('2',64),'segundos',3600,'limite',604800));
SELECT public.fn_sesion_acceso('revocar',jsonb_build_object('renovacion',repeat('2',64)));
\set prueba 'SES-06 logout por cookie revoca también el acceso'
SELECT public.fn_sesion_acceso('resolver',jsonb_build_object('acceso',repeat('1',64)))->>'status'='invalid' AS ok \gset
\ir incluir/afirmar.sql
SELECT public.fn_sesion_acceso('emitir',jsonb_build_object('usuario',:mec_1,'taller',:taller_1,'perfil','mecanico','acceso',repeat('3',64),'renovacion',repeat('4',64),'segundos',3600,'limite',604800));
\ir incluir/rol_plataforma.sql
UPDATE sesion_acceso SET creada_en=now()-interval '8 days',acceso_hasta=now()-interval '1 day',renovacion_hasta=now()-interval '1 day' WHERE acceso_hash=repeat('3',64);
\ir incluir/rol_backend.sql
\set prueba 'SES-07 vencimiento absoluto impide renovar'
SELECT public.fn_sesion_acceso('renovar',jsonb_build_object('renovacion',repeat('4',64),'nuevo_acceso',repeat('5',64),'nueva_renovacion',repeat('6',64),'segundos',3600))->>'status'='invalid' AS ok \gset
\ir incluir/afirmar.sql
SELECT public.fn_sesion_acceso('emitir',jsonb_build_object('usuario',:mec_1,'taller',:taller_1,'perfil','mecanico','acceso',repeat('7',64),'renovacion',repeat('8',64),'segundos',3600,'limite',604800));
\ir incluir/rol_plataforma.sql
UPDATE usuario SET activo=false WHERE id=:mec_1;
\ir incluir/rol_backend.sql
\set prueba 'SES-08 usuario desactivado no mantiene acceso ni renovación'
SELECT public.fn_sesion_acceso('resolver',jsonb_build_object('acceso',repeat('7',64)))->>'status'='invalid'
 AND public.fn_sesion_acceso('renovar',jsonb_build_object('renovacion',repeat('8',64),'nuevo_acceso',repeat('9',64),'nueva_renovacion',repeat('0',64),'segundos',3600))->>'status'='invalid' AS ok \gset
\ir incluir/afirmar.sql
\ir incluir/rol_plataforma.sql
\set prueba 'SES-09 ningún rol operativo ni conexión backend puede leer o modificar hashes directamente'
SELECT NOT EXISTS(SELECT 1 FROM information_schema.table_privileges WHERE table_schema='public'
 AND table_name IN ('sesion_acceso','renovacion_consumida') AND grantee IN ('app_backend_user','taller_admin','taller_mecanico','taller_auditor','public')) AS ok \gset
\ir incluir/afirmar.sql
\set prueba 'SES-10 tablas privadas tienen RLS forzado y sin políticas operativas'
SELECT (SELECT bool_and(relrowsecurity AND relforcerowsecurity) FROM pg_class WHERE oid IN ('sesion_acceso'::regclass,'renovacion_consumida'::regclass))
 AND NOT EXISTS(SELECT 1 FROM pg_policies WHERE tablename IN ('sesion_acceso','renovacion_consumida')) AS ok \gset
\ir incluir/afirmar.sql
\ir incluir/rol_plataforma.sql
UPDATE sesion_acceso SET creada_en=now()-interval '8 days',acceso_hasta=now()-interval '1 day',renovacion_hasta=now()-interval '1 day' WHERE renovacion_hash=repeat('d',64);
\ir incluir/rol_backend.sql
SELECT public.fn_sesion_acceso('emitir',jsonb_build_object('usuario',:admin_1,'taller',:taller_1,'perfil','propietario','acceso',repeat('f',63)||'1','renovacion',repeat('f',63)||'2','segundos',3600,'limite',604800));
\ir incluir/rol_plataforma.sql
\set prueba 'SES-11 limpieza de familias vencidas elimina también el historial de renovación'
SELECT NOT EXISTS(SELECT 1 FROM sesion_acceso WHERE renovacion_hash=repeat('d',64))
 AND NOT EXISTS(SELECT 1 FROM renovacion_consumida WHERE hash=repeat('b',64)) AS ok \gset
\ir incluir/afirmar.sql
\ir incluir/rol_backend.sql
\set prueba 'SES-12 capacidad rechaza emisión nueva sin expulsar una familia activa'
SELECT public.fn_sesion_acceso('emitir',jsonb_build_object('usuario',:admin_1,'taller',:taller_1,'perfil','propietario','acceso',repeat('f',63)||'3','renovacion',repeat('f',63)||'4','segundos',3600,'limite',604800,'capacidad',1))->>'status'='capacity'
 AND public.fn_sesion_acceso('resolver',jsonb_build_object('acceso',repeat('f',63)||'1'))->>'status'='authenticated' AS ok \gset
\ir incluir/afirmar.sql
ROLLBACK;

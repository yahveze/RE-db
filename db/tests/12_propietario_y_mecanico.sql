-- Perfiles efectivos y propiedad. Identidades Google sintéticas sólo dentro de ROLLBACK.
\ir incluir/inicio.sql
\echo '### 12 Propietario y mecánico'
\o /dev/null
\ir incluir/rol_admin_1.sql
\set prueba 'PRO-01 la cuenta de plataforma del taller demo es su propietario explícito'
SELECT propietario_usuario_id=:admin_1 AND propietario_asignado_en IS NOT NULL AS ok FROM taller WHERE id=:taller_1 \gset
\ir incluir/afirmar.sql
\set prueba 'PRO-02 propietario es un perfil SQL, separado del rol técnico admin'
SELECT perfil='propietario' AND rol_tecnico='admin' AS ok FROM v_usuario_perfil WHERE id=:admin_1 \gset
\ir incluir/afirmar.sql
\set prueba 'PRO-03 contexto de propietario validado en base de datos'
SELECT fn_es_propietario() AS ok \gset
\ir incluir/afirmar.sql
\set prueba 'PRO-04 el propietario no puede desactivarse por la edición general de usuarios'
\set esperado RE024
UPDATE usuario SET activo=false WHERE id=:admin_1;
\ir incluir/error.sql
\set prueba 'PRO-05 no puede degradarse al propietario a mecánico'
\set esperado RE024
UPDATE usuario SET rol='mecanico' WHERE id=:admin_1;
\ir incluir/error.sql
\set prueba 'PRO-06 no se incorporan otros administradores'
\set esperado RE023
INSERT INTO usuario(taller_id,email,nombre,rol) VALUES(:taller_1,'admin-nuevo@gmail.com','No permitido','admin');
\ir incluir/error.sql
\set prueba 'PRO-07 no se incorporan auditores'
\set esperado RE023
INSERT INTO usuario(taller_id,email,nombre,rol) VALUES(:taller_1,'auditor-nuevo@gmail.com','No permitido','auditor');
\ir incluir/error.sql
\set prueba 'PRO-08 no se puede invitar otro propietario o administrador manipulando SQL'
\set esperado RE023
INSERT INTO invitacion_taller(taller_id,email,rol,token_hash,invitado_por)
  VALUES(:taller_1,'perfil-no-permitido@gmail.com','admin',repeat('4',64),:admin_1);
\ir incluir/error.sql
\set prueba 'PRO-09 el grupo operativo no puede modificar la propiedad directamente'
\set esperado 42501
UPDATE taller SET propietario_usuario_id=:mec_1 WHERE id=:taller_1;
\ir incluir/error.sql

\ir incluir/rol_mecanico_1.sql
\set prueba 'PRO-10 mecánico obtiene sólo su perfil operativo'
SELECT fn_perfil_usuario(:mec_1,:taller_1)='mecanico' AS ok \gset
\ir incluir/afirmar.sql
\set prueba 'PRO-11 mecánico no puede consultar o crear invitaciones'
\set esperado 42501
SELECT * FROM invitacion_taller;
\ir incluir/error.sql
\set prueba 'PRO-12 mecánico no puede modificar configuración del taller'
\set esperado 42501
UPDATE taller_configuracion SET margen_pct=1;
\ir incluir/error.sql

\ir incluir/rol_plataforma.sql
INSERT INTO usuario(taller_id,email,nombre,rol) VALUES(:taller_1,'admin-sin-propiedad@example.test','Administrador heredado','admin') RETURNING id AS legado_id \gset
\ir incluir/rol_backend.sql
SET LOCAL ROLE taller_admin;
EXECUTE ctx(:'taller_1',:'legado_id','127.0.0.1','prueba-propiedad-legada') \gset ctx_
\set prueba 'PRO-13 tener el rol técnico admin no otorga propiedad'
SELECT NOT fn_es_propietario() AND fn_perfil_usuario(:legado_id,:taller_1) IS NULL AS ok \gset
\ir incluir/afirmar.sql
\set prueba 'PRO-14 un administrador heredado sin propiedad no puede gestionar el taller'
\set esperado RE022
UPDATE taller_configuracion SET margen_pct=1;
\ir incluir/error.sql

\ir incluir/rol_backend.sql
SELECT 'owner-' || gen_random_uuid()::text || '@gmail.com' AS email \gset nuevo_
WITH r AS MATERIALIZED(SELECT fn_google_acceso(:'nuevo_email',:'nuevo_email','Propietario prueba','register','Taller prueba propietario',NULL,NULL,true) AS data)
SELECT data->>'status' AS status,data->>'perfil' AS perfil,data->>'usuario_id' AS usuario_id,data->>'taller_id' AS taller_id FROM r \gset alta_
\set prueba 'PRO-15 registrar un taller crea un propietario en la misma transacción'
SELECT :'alta_status'='authenticated' AND :'alta_perfil'='propietario' AS ok \gset
\ir incluir/afirmar.sql
SET LOCAL ROLE taller_admin;
EXECUTE ctx(:'alta_taller_id',:'alta_usuario_id','127.0.0.1','prueba-alta-propietario') \gset ctx_
\set prueba 'PRO-16 la propiedad se guarda con referencia al usuario del mismo taller'
SELECT propietario_usuario_id=:'alta_usuario_id'::bigint AS ok FROM taller WHERE id=:'alta_taller_id'::bigint \gset
\ir incluir/afirmar.sql
SELECT 'mechanic-'||gen_random_uuid()::text||'@gmail.com' AS email \gset nuevo_mec_
INSERT INTO invitacion_taller(taller_id,email,rol,token_hash,invitado_por)
VALUES(:'alta_taller_id'::bigint,:'nuevo_mec_email','mecanico',repeat('b',64),:'alta_usuario_id'::bigint);
\ir incluir/rol_backend.sql
WITH r AS MATERIALIZED(SELECT fn_google_acceso(:'nuevo_mec_email',:'nuevo_mec_email','Mecánico prueba','accept',NULL,repeat('b',64),NULL,true) AS data)
SELECT data->>'status' AS status,data->>'perfil' AS perfil,data->>'usuario_id' AS usuario_id,data->>'taller_id' AS taller_id FROM r \gset ingreso_
\set prueba 'PRO-17 aceptar la invitación incorpora un mecánico al taller correcto'
SELECT :'ingreso_status'='authenticated' AND :'ingreso_perfil'='mecanico' AND :'ingreso_taller_id'=:'alta_taller_id' AS ok \gset
\ir incluir/afirmar.sql
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'ingreso_taller_id',:'ingreso_usuario_id','127.0.0.1','prueba-ingreso-mecanico') \gset ctx_
\set prueba 'PRO-18 el mecánico incorporado sólo ve su taller'
SELECT count(*)=1 AND bool_and(id=:'alta_taller_id'::bigint) AS ok FROM taller \gset
\ir incluir/afirmar.sql
\set prueba 'PRO-19 el mecánico incorporado no puede promoverse ni cambiar roles'
\set esperado 42501
UPDATE usuario SET rol='admin' WHERE id=:'ingreso_usuario_id'::bigint;
\ir incluir/error.sql

\ir incluir/rol_backend.sql
\set prueba 'PRO-20 el auditor histórico no tiene acceso a la aplicación de dos perfiles'
SELECT fn_autenticar_aplicacion('auditor@losaromos.example',:'clave_demo')->>'status'='profile_not_enabled' AS ok \gset
\ir incluir/afirmar.sql
\ir incluir/rol_plataforma.sql
\set prueba 'PRO-21 sólo existen los dos perfiles habilitados en la vista autoritativa'
SELECT bool_and(perfil IN ('propietario','mecanico')) AS ok FROM v_usuario_perfil WHERE perfil IS NOT NULL \gset
\ir incluir/afirmar.sql
\set prueba 'PRO-22 la relación de propiedad tiene clave foránea compuesta hacia usuario y taller'
SELECT array_length(conkey,1)=2 AND confrelid='usuario'::regclass AND confdeltype='r' AS ok
FROM pg_constraint WHERE conname='fk_taller_propietario' \gset
\ir incluir/afirmar.sql
ROLLBACK;

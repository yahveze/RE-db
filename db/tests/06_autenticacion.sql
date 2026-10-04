-- =============================================================================
-- 06 - Autenticacion y contrasenas.
-- El login se ejecuta con la conexion del backend, sin rol ni contexto. Las
-- comprobaciones sobre usuario_credencial las hace la plataforma (ningun rol de
-- ejecucion puede leerla).
-- =============================================================================
\ir incluir/inicio.sql
\echo '### 06 Autenticacion'
\o /dev/null

-- ------------------------------------------------------------------- login
\ir incluir/rol_backend.sql
EXECUTE q_login('mecanico1@losaromos.example', :'clave_demo') \gset l_

\ir incluir/rol_plataforma.sql
\set prueba 'Login correcto: devuelve usuario, taller, rol y nombre (ids internos y publicos)'
SELECT :'l_autenticado'::boolean AND :l_usuario_id = u.id AND :'l_usuario_id_publico' = u.id_publico::text
       AND :l_taller_id = t.id AND :'l_taller_id_publico' = t.id_publico::text
       AND :'l_rol' = 'mecanico' AND :'l_nombre' = u.nombre AS ok
FROM   usuario u JOIN taller t ON t.id = u.taller_id WHERE u.id = :mec_1 \gset
\ir incluir/afirmar.sql

\set prueba 'La funcion de login no devuelve el hash ni ningun dato de la credencial'
SELECT pg_get_function_result('fn_autenticar_usuario(text, text)'::regprocedure) !~* '(hash|contrasena|intentos|bloqueado)' AS ok \gset
\ir incluir/afirmar.sql

\ir incluir/rol_backend.sql
\set prueba 'Login correcto: el email se normaliza (mayusculas y espacios)'
SELECT a.autenticado AND a.usuario_id = :mec_1 AS ok
FROM   fn_autenticar_usuario('  MECANICO1@LosAromos.EXAMPLE ', :'clave_demo') a \gset
\ir incluir/afirmar.sql

\set prueba 'Clave incorrecta: una fila con autenticado = false y todo lo demas NULL'
SELECT count(*) = 1 AND bool_and(NOT a.autenticado AND a.usuario_id IS NULL AND a.usuario_id_publico IS NULL
       AND a.taller_id IS NULL AND a.taller_id_publico IS NULL AND a.rol IS NULL AND a.nombre IS NULL) AS ok
FROM   fn_autenticar_usuario('mecanico1@losaromos.example', 'clave-incorrecta') a \gset
\ir incluir/afirmar.sql

\set prueba 'Email inexistente: misma respuesta que una clave incorrecta (no delata que emails existen)'
SELECT count(*) = 1 AND bool_and(NOT a.autenticado AND a.usuario_id IS NULL AND a.taller_id IS NULL AND a.rol IS NULL) AS ok
FROM   fn_autenticar_usuario('nadie@losaromos.example', :'clave_demo') a \gset
\ir incluir/afirmar.sql

\set prueba 'Email y clave NULL o vacios: no autentica y no falla'
SELECT NOT (SELECT a.autenticado FROM fn_autenticar_usuario(NULL, NULL) a)
   AND NOT (SELECT a.autenticado FROM fn_autenticar_usuario('', '') a)
   AND NOT (SELECT a.autenticado FROM fn_autenticar_usuario('mecanico1@losaromos.example', NULL) a) AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'Usuario dado de baja: no autentica aunque la clave sea correcta'
SELECT NOT a.autenticado AS ok FROM fn_autenticar_usuario('exmecanico@losaromos.example', :'clave_demo') a \gset
\ir incluir/afirmar.sql

\ir incluir/rol_plataforma.sql
UPDATE taller SET activo = false WHERE id = :taller_2;
INSERT INTO usuario (taller_id, email, nombre, rol) VALUES (:taller_1, 'sincredencial@losaromos.example', 'Sin Credencial', 'mecanico');
\ir incluir/rol_backend.sql

\set prueba 'Taller inactivo: sus usuarios no autentican'
SELECT NOT a.autenticado AS ok FROM fn_autenticar_usuario('mecanico@nuble.example', :'clave_demo') a \gset
\ir incluir/afirmar.sql

\set prueba 'Usuario sin credencial: no autentica'
SELECT NOT a.autenticado AS ok FROM fn_autenticar_usuario('sincredencial@losaromos.example', :'clave_demo') a \gset
\ir incluir/afirmar.sql

-- ------------------------------------------------- intentos y bloqueo
-- (Los fallos anteriores de mecanico1 ya cuentan: 2 con clave incorrecta o NULL.)
\ir incluir/rol_plataforma.sql
\set prueba 'Cada clave incorrecta incrementa intentos_fallidos'
SELECT c.intentos_fallidos = 2 AND c.bloqueado_hasta IS NULL AS ok FROM usuario_credencial c WHERE c.usuario_id = :mec_1 \gset
\ir incluir/afirmar.sql

\ir incluir/rol_backend.sql
SELECT a.autenticado AS ok_login FROM fn_autenticar_usuario('mecanico1@losaromos.example', :'clave_demo') a \gset
\ir incluir/rol_plataforma.sql
\set prueba 'Un login correcto pone el contador en cero y registra ultimo_login_en'
SELECT :'ok_login'::boolean AND c.intentos_fallidos = 0 AND c.ultimo_login_en = now() AS ok
FROM   usuario_credencial c WHERE c.usuario_id = :mec_1 \gset
\ir incluir/afirmar.sql

\ir incluir/rol_backend.sql
SELECT count(*) AS fallos FROM generate_series(1, 4) g, LATERAL fn_autenticar_usuario('mecanico1@losaromos.example', 'mala-' || g) a \gset
\ir incluir/rol_plataforma.sql
\set prueba 'Tras 4 fallos consecutivos la cuenta aun no esta bloqueada'
SELECT c.intentos_fallidos = 4 AND c.bloqueado_hasta IS NULL AS ok FROM usuario_credencial c WHERE c.usuario_id = :mec_1 \gset
\ir incluir/afirmar.sql

\ir incluir/rol_backend.sql
SELECT a.autenticado AS quinto FROM fn_autenticar_usuario('mecanico1@losaromos.example', 'mala-5') a \gset
\ir incluir/rol_plataforma.sql
\set prueba 'El 5.o fallo consecutivo bloquea la cuenta 15 minutos'
SELECT c.bloqueado_hasta = now() + interval '15 minutes' AND c.intentos_fallidos = 0 AS ok
FROM   usuario_credencial c WHERE c.usuario_id = :mec_1 \gset
\ir incluir/afirmar.sql

\ir incluir/rol_backend.sql
\set prueba 'Cuenta bloqueada: ni la clave correcta autentica'
SELECT NOT a.autenticado AS ok FROM fn_autenticar_usuario('mecanico1@losaromos.example', :'clave_demo') a \gset
\ir incluir/afirmar.sql

\ir incluir/rol_plataforma.sql
\set prueba 'El bloqueo es por cuenta: otro usuario del mismo taller sigue autenticando'
SELECT a.autenticado AS ok FROM fn_autenticar_usuario('mecanico2@losaromos.example', :'clave_demo') a \gset
\ir incluir/afirmar.sql

-- Se simula el paso del tiempo: el bloqueo ya vencio.
UPDATE usuario_credencial SET bloqueado_hasta = now() - interval '1 minute' WHERE usuario_id = :mec_1;
\ir incluir/rol_backend.sql
SELECT a.autenticado AS ok_login FROM fn_autenticar_usuario('mecanico1@losaromos.example', :'clave_demo') a \gset
\ir incluir/rol_plataforma.sql
\set prueba 'Bloqueo vencido: la clave correcta autentica y limpia el bloqueo'
SELECT :'ok_login'::boolean AND c.bloqueado_hasta IS NULL AND c.intentos_fallidos = 0 AS ok
FROM   usuario_credencial c WHERE c.usuario_id = :mec_1 \gset
\ir incluir/afirmar.sql

-- ---------------------------------------------------- auditoria del login
\set prueba 'Auditoria: LOGIN con exito y LOGIN_FALLIDO con fallo o denegado, con el rol de conexion y sin datos'
SELECT count(*) FILTER (WHERE a.operacion = 'LOGIN' AND a.resultado = 'exito') >= 3
   AND count(*) FILTER (WHERE a.operacion = 'LOGIN_FALLIDO' AND a.resultado = 'fallo') >= 7
   AND count(*) FILTER (WHERE a.operacion = 'LOGIN_FALLIDO' AND a.resultado = 'denegado') >= 3
   AND bool_and(a.datos_anteriores IS NULL AND a.datos_nuevos IS NULL AND a.tabla IS NULL)
   AND bool_and(a.rol IN ('app_backend_user', session_user)) AS ok
FROM   auditoria_operacion a
WHERE  a.ocurrido_en >= now() AND a.operacion IN ('LOGIN', 'LOGIN_FALLIDO') \gset
\ir incluir/afirmar.sql

\set prueba 'Auditoria: el fallo de un email inexistente queda sin taller ni usuario (T-14)'
SELECT count(*) >= 3 AS ok
FROM   auditoria_operacion a
WHERE  a.ocurrido_en >= now() AND a.operacion = 'LOGIN_FALLIDO' AND a.taller_id IS NULL AND a.usuario_id IS NULL \gset
\ir incluir/afirmar.sql

\set prueba 'Auditoria: ningun registro contiene un email (ni el intentado ni el del usuario)'
SELECT count(*) = 0 AS ok
FROM   auditoria_operacion a
WHERE  (COALESCE(a.datos_anteriores, '{}')::text || COALESCE(a.datos_nuevos, '{}')::text || COALESCE(a.request_id, '')) LIKE '%@%' \gset
\ir incluir/afirmar.sql

-- ------------------------------------------------------------------ hashes
\set prueba 'Los hashes son bcrypt de costo 10 (60 caracteres)'
SELECT count(*) > 0 AND bool_and(c.hash_contrasena LIKE '$2a$10$%' AND length(c.hash_contrasena) = 60) AS ok
FROM   usuario_credencial c \gset
\ir incluir/afirmar.sql

\set prueba 'La misma clave produce hashes distintos por usuario (sal aleatoria)'
SELECT count(DISTINCT c.hash_contrasena) = count(*) AND count(*) = 8 AS ok FROM usuario_credencial c \gset
\ir incluir/afirmar.sql

\set prueba 'La clave de demostracion no aparece en texto plano en ninguna columna de credenciales'
SELECT count(*) = 0 AS ok FROM usuario_credencial c WHERE c.hash_contrasena LIKE '%' || :'clave_demo' || '%' \gset
\ir incluir/afirmar.sql

-- ------------------------------------------- fn_establecer_contrasena
\ir incluir/rol_admin_1.sql

\set prueba 'RE011 contrasena de 7 caracteres'
\set esperado RE011
SELECT fn_establecer_contrasena(:mec_1b, '1234567');
\ir incluir/error.sql
\set prueba 'RE011 contrasena de 73 bytes (bcrypt la truncaria en silencio)'
\set esperado RE011
SELECT fn_establecer_contrasena(:mec_1b, repeat('a', 73));
\ir incluir/error.sql
\set prueba 'RE011 contrasena de 37 caracteres que ocupan 74 bytes'
\set esperado RE011
SELECT fn_establecer_contrasena(:mec_1b, repeat('ñ', 37));
\ir incluir/error.sql
\set prueba 'RE011 contrasena NULL'
\set esperado RE011
SELECT fn_establecer_contrasena(:mec_1b, NULL);
\ir incluir/error.sql
\set prueba 'RE009 usuario inexistente'
\set esperado RE009
SELECT fn_establecer_contrasena(999999999, 'Clave-Nueva-123');
\ir incluir/error.sql

\set prueba 'RE006 rol de administrador sin contexto de taller'
EXECUTE ctx('', '', '', '') \gset ctx_
\set esperado RE006
SELECT fn_establecer_contrasena(:mec_1b, 'Clave-Nueva-123');
\ir incluir/error.sql
\ir incluir/rol_admin_1.sql

SELECT fn_establecer_contrasena(:mec_1b, repeat('b', 72));
\ir incluir/rol_backend.sql
\set prueba 'Contrasena de exactamente 72 bytes: se acepta y autentica'
SELECT a.autenticado AS ok FROM fn_autenticar_usuario('mecanico2@losaromos.example', repeat('b', 72)) a \gset
\ir incluir/afirmar.sql
\set prueba 'Tras el cambio, la contrasena anterior deja de servir'
SELECT NOT a.autenticado AS ok FROM fn_autenticar_usuario('mecanico2@losaromos.example', :'clave_demo') a \gset
\ir incluir/afirmar.sql

-- Bloqueo y restablecimiento por el administrador.
SELECT count(*) AS fallos FROM generate_series(1, 5) g, LATERAL fn_autenticar_usuario('mecanico2@losaromos.example', 'mala-' || g) a \gset
\ir incluir/rol_admin_1.sql
SELECT fn_establecer_contrasena(:mec_1b, 'Clave-Restablecida-9');
\ir incluir/rol_backend.sql
\set prueba 'Restablecer la contrasena levanta el bloqueo de la cuenta'
SELECT a.autenticado AS ok FROM fn_autenticar_usuario('mecanico2@losaromos.example', 'Clave-Restablecida-9') a \gset
\ir incluir/afirmar.sql

\ir incluir/rol_plataforma.sql
\set prueba 'El cambio de contrasena queda auditado sin datos (ni hash ni clave)'
SELECT count(*) = 2 AND bool_and(a.operacion = 'UPDATE' AND a.rol = 'taller_admin' AND a.usuario_id = :admin_1
       AND a.registro_id = :mec_1b AND a.datos_anteriores IS NULL AND a.datos_nuevos IS NULL) AS ok
FROM   auditoria_operacion a
WHERE  a.ocurrido_en >= now() AND a.tabla = 'usuario_credencial' \gset
\ir incluir/afirmar.sql

\set prueba 'usuario_credencial no tiene trigger de auditoria (un hash jamas se copia)'
SELECT count(*) = 0 AS ok
FROM   pg_trigger t WHERE t.tgrelid = 'usuario_credencial'::regclass AND NOT t.tgisinternal AND t.tgname LIKE '%auditar%' \gset
\ir incluir/afirmar.sql

ROLLBACK;

-- =============================================================================
-- 08 - Privacidad: supresion con retencion, bloqueo y anonimizacion
--      (RN-61 a RN-64).
-- Estado de partida (semillas del taller 1): Elena Vargas bloqueada (una
-- atencion completada dentro de la retencion) y un titular anonimizado (su
-- unica atencion fue cancelada).
-- =============================================================================
\ir incluir/inicio.sql
\echo '### 08 Privacidad'
\o /dev/null

\ir incluir/rol_plataforma.sql
SELECT t.id AS bloq  FROM titular t WHERE t.taller_id = :taller_1 AND t.estado_tratamiento = 'bloqueado' \gset
SELECT t.id AS anon  FROM titular t WHERE t.taller_id = :taller_1 AND t.estado_tratamiento = 'anonimizado' \gset
SELECT t.id AS marco, t.id_publico AS marco_pub FROM titular t WHERE t.taller_id = :taller_1 AND t.nombre = 'Marco Díaz Leiva' \gset
SELECT t.id AS juana FROM titular t WHERE t.taller_id = :taller_1 AND t.nombre = 'Juana Pérez Soto' \gset
SELECT count(*) AS sesiones_antes, sum(c.total) AS total_antes
FROM   sesion_diagnostico s LEFT JOIN cotizacion c ON c.sesion_id = s.id AND c.vigente WHERE s.taller_id = :taller_1 \gset
SELECT count(*) AS fallas_antes FROM falla_sesion WHERE taller_id = :taller_1 \gset

-- ---------------------------------------------------- estado de las semillas
\set prueba 'RN-61 bloqueado: conserva sus datos y vence en (ultima atencion no cancelada + 6 anios)'
SELECT t.estado_tratamiento = 'bloqueado' AND t.nombre IS NOT NULL AND t.anonimizado_en IS NULL
       AND t.bloqueado_hasta = (SELECT (max(s.iniciada_en) + interval '6 years')::date
                                FROM sesion_diagnostico s JOIN vehiculo v ON v.id = s.vehiculo_id
                                WHERE v.titular_id = t.id AND s.estado <> 'cancelado') AS ok
FROM   titular t WHERE t.id = :bloq \gset
\ir incluir/afirmar.sql

\set prueba 'RN-61 bloqueado: su vehiculo conserva patente y VIN; la solicitud queda en proceso'
SELECT (SELECT bool_and(v.patente IS NOT NULL AND v.anonimizado_en IS NULL) FROM vehiculo v WHERE v.titular_id = :bloq)
   AND (SELECT count(*) = 1 AND bool_and(s.estado = 'en_proceso' AND s.resuelta_en IS NULL)
        FROM solicitud_derecho_titular s WHERE s.titular_id = :bloq AND s.tipo = 'supresion') AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'RN-63 anonimizado: sin nombre, telefono, email ni HMAC'
SELECT t.nombre IS NULL AND t.telefono IS NULL AND t.email IS NULL AND t.identificador_hmac IS NULL
       AND t.anonimizado_en IS NOT NULL AND t.bloqueado_hasta IS NULL AS ok
FROM   titular t WHERE t.id = :anon \gset
\ir incluir/afirmar.sql

\set prueba 'RN-63 anonimizado: su vehiculo pierde patente y VIN, y conserva modelo, anio y motor'
SELECT count(*) = 1 AND bool_and(v.patente IS NULL AND v.vin IS NULL AND v.anonimizado_en IS NOT NULL
       AND v.modelo_vehiculo_id IS NOT NULL AND v.anio = 2016 AND v.motor IS NOT NULL) AS ok
FROM   vehiculo v WHERE v.titular_id = :anon \gset
\ir incluir/afirmar.sql

\set prueba 'RN-62 anonimizado: consentimientos revocados y solicitud de supresion resuelta'
SELECT (SELECT count(*) > 0 AND bool_and(c.revocado_en IS NOT NULL) FROM consentimiento_titular c WHERE c.titular_id = :anon)
   AND (SELECT count(*) = 1 AND bool_and(s.estado = 'resuelta' AND s.resuelta_en IS NOT NULL)
        FROM solicitud_derecho_titular s WHERE s.titular_id = :anon AND s.tipo = 'supresion') AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'RN-62 anonimizado: su sesion y sus fallas se conservan (trazabilidad tecnica sin persona)'
SELECT count(*) = 1 AND bool_and(EXISTS (SELECT 1 FROM falla_sesion f WHERE f.sesion_id = s.id)) AS ok
FROM   sesion_diagnostico s JOIN vehiculo v ON v.id = s.vehiculo_id WHERE v.titular_id = :anon \gset
\ir incluir/afirmar.sql

-- ------------------------------------------------ irreversibilidad
\ir incluir/rol_admin_1.sql
\set prueba 'La anonimizacion es irreversible: no se puede volver a escribir el nombre'
\set esperado 23514
UPDATE titular SET nombre = 'Reaparecido' WHERE id = :anon;
\ir incluir/error.sql
\set prueba 'La anonimizacion es irreversible: no se puede volver a escribir la patente'
\set esperado 23514
UPDATE vehiculo SET patente = 'WXYZ31' WHERE titular_id = :anon;
\ir incluir/error.sql

-- ------------------------------------------------ solicitudes repetidas
\set prueba 'Repetir la supresion de un titular bloqueado: sigue bloqueado y no duplica la solicitud'
SELECT fn_solicitar_supresion_titular(:bloq) = 'bloqueado'
   AND (SELECT count(*) FROM solicitud_derecho_titular s WHERE s.titular_id = :bloq AND s.tipo = 'supresion') = 1 AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'Repetir la supresion de un titular anonimizado: devuelve anonimizado sin cambios'
SELECT fn_solicitar_supresion_titular(:anon) = 'anonimizado'
   AND (SELECT count(*) FROM solicitud_derecho_titular s WHERE s.titular_id = :anon) = 1 AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'RE009 supresion de un titular inexistente'
\set esperado RE009
SELECT fn_solicitar_supresion_titular(999999999);
\ir incluir/error.sql

\set prueba 'RE006 supresion con rol de administrador pero sin contexto de taller'
EXECUTE ctx('', '', '', '') \gset ctx_
\set esperado RE006
SELECT fn_solicitar_supresion_titular(:juana);
\ir incluir/error.sql
\ir incluir/rol_admin_1.sql

-- --------------------------------------- titular sin atenciones: inmediato
EXECUTE tx_crear_titular('Sin Atenciones', '+56900000001', NULL, NULL) \gset n_
EXECUTE tx_solicitar_supresion(:'n_id_publico') \gset r_
\set prueba 'RN-62 un titular sin atenciones se anonimiza de inmediato'
SELECT :'r_estado_tratamiento' = 'anonimizado'
   AND (SELECT t.nombre IS NULL AND t.telefono IS NULL AND t.estado_tratamiento = 'anonimizado'
        FROM titular t WHERE t.id_publico = :'n_id_publico') AS ok \gset
\ir incluir/afirmar.sql

-- ------------------------------------- retencion 0: anonimiza de inmediato
EXECUTE tx_actualizar_configuracion(NULL, NULL, 0);
EXECUTE tx_solicitar_supresion(:'marco_pub') \gset r_
\set prueba 'Con retencion_anios = 0 la supresion anonimiza aunque haya atenciones recientes'
SELECT :'r_estado_tratamiento' = 'anonimizado'
   AND (SELECT t.nombre IS NULL AND t.identificador_hmac IS NULL FROM titular t WHERE t.id = :marco) AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'RN-63 se anonimizan TODOS los vehiculos del titular en la misma operacion'
SELECT count(*) = 2 AND bool_and(v.patente IS NULL AND v.vin IS NULL AND v.anonimizado_en IS NOT NULL) AS ok
FROM   vehiculo v WHERE v.titular_id = :marco \gset
\ir incluir/afirmar.sql

\ir incluir/rol_plataforma.sql
\set prueba 'RN-62 la anonimizacion no borra ni altera sesiones, fallas ni totales cotizados'
SELECT (SELECT count(*) FROM sesion_diagnostico WHERE taller_id = :taller_1) = :sesiones_antes
   AND (SELECT count(*) FROM falla_sesion WHERE taller_id = :taller_1) = :fallas_antes
   AND (SELECT sum(c.total) FROM cotizacion c WHERE c.taller_id = :taller_1 AND c.vigente) = :total_antes AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'RN-71 la auditoria de la anonimizacion no contiene los datos borrados'
SELECT count(*) >= 1 AND bool_and(NOT (a.datos_anteriores || a.datos_nuevos) ?| ARRAY['nombre', 'telefono', 'email', 'identificador_hmac']
       AND a.datos_nuevos ->> 'estado_tratamiento' = 'anonimizado') AS ok
FROM   auditoria_operacion a
WHERE  a.tabla = 'titular' AND a.registro_id = :marco AND a.operacion = 'UPDATE' AND a.ocurrido_en >= now() \gset
\ir incluir/afirmar.sql

\ir incluir/rol_mecanico_1.sql
\set prueba 'RN-64 tras la anonimizacion el mecanico no ve al titular ni sus vehiculos, pero si sus sesiones'
SELECT (SELECT count(*) FROM titular WHERE id = :marco) = 0
   AND (SELECT count(*) FROM vehiculo WHERE titular_id = :marco) = 0
   AND (SELECT count(*) FROM sesion_diagnostico) = :sesiones_antes AS ok \gset
\ir incluir/afirmar.sql

-- --------------------------------------------- proceso periodico (vencidos)
\ir incluir/rol_plataforma.sql
SET LOCAL ROLE app_owner;
\set prueba 'fn_anonimizar_vencidos: sin bloqueos vencidos no procesa a nadie'
SELECT fn_anonimizar_vencidos() = 0 AS ok \gset
\ir incluir/afirmar.sql
RESET ROLE;

-- Se simula el paso del tiempo: el bloqueo vence hoy.
UPDATE titular SET bloqueado_hasta = current_date WHERE id = :bloq;
SET LOCAL ROLE app_owner;
\set prueba 'fn_anonimizar_vencidos: procesa el bloqueo vencido (ejecutada como app_owner)'
SELECT fn_anonimizar_vencidos() = 1 AS ok \gset
\ir incluir/afirmar.sql
\set prueba 'fn_anonimizar_vencidos: una segunda ejecucion no encuentra nada (idempotente)'
SELECT fn_anonimizar_vencidos() = 0 AS ok \gset
\ir incluir/afirmar.sql
RESET ROLE;

\set prueba 'RN-62 el titular vencido queda anonimizado, con su vehiculo, y la solicitud resuelta'
SELECT (SELECT t.estado_tratamiento = 'anonimizado' AND t.nombre IS NULL AND t.bloqueado_hasta IS NULL FROM titular t WHERE t.id = :bloq)
   AND (SELECT bool_and(v.patente IS NULL AND v.vin IS NULL) FROM vehiculo v WHERE v.titular_id = :bloq)
   AND (SELECT bool_and(s.estado = 'resuelta' AND s.resuelta_en IS NOT NULL)
        FROM solicitud_derecho_titular s WHERE s.titular_id = :bloq AND s.tipo = 'supresion')
   AND (SELECT bool_and(c.revocado_en IS NOT NULL) FROM consentimiento_titular c WHERE c.titular_id = :bloq) AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'La anonimizacion por proceso queda auditada con el rol app_owner'
SELECT count(*) = 1 AND bool_and(a.rol = 'app_owner') AS ok
FROM   auditoria_operacion a
WHERE  a.tabla = 'titular' AND a.registro_id = :bloq AND a.operacion = 'UPDATE' AND a.ocurrido_en >= now()
AND    a.datos_nuevos ->> 'estado_tratamiento' = 'anonimizado' \gset
\ir incluir/afirmar.sql

\set prueba 'Ningun titular anonimizado conserva datos y ningun vehiculo anonimizado conserva identificadores'
SELECT (SELECT count(*) FROM titular WHERE estado_tratamiento = 'anonimizado'
        AND (nombre IS NOT NULL OR telefono IS NOT NULL OR email IS NOT NULL OR identificador_hmac IS NOT NULL)) = 0
   AND (SELECT count(*) FROM vehiculo WHERE anonimizado_en IS NOT NULL AND (patente IS NOT NULL OR vin IS NOT NULL)) = 0
   AND (SELECT count(*) FROM titular WHERE estado_tratamiento = 'anonimizado') = 4 AS ok \gset
\ir incluir/afirmar.sql

ROLLBACK;

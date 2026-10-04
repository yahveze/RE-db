-- =============================================================================
-- 02 - Restricciones declarativas (CHECK, UNIQUE, FK, NOT NULL).
-- Se prueban como plataforma (superusuario): asi lo que rechaza la operacion es
-- la restriccion y no un privilegio ni una politica. Las reglas RN-xx son las
-- de docs/modelo/01_dominio_y_reglas.md.
-- =============================================================================
\ir incluir/inicio.sql
\ir incluir/rol_plataforma.sql
\echo '### 02 Restricciones'

SELECT id AS modelo_hilux FROM modelo_vehiculo WHERE nombre = 'Hilux' \gset
SELECT id AS veh_hilux_1  FROM vehiculo WHERE taller_id = :taller_1 AND patente = 'LPRS56' \gset
SELECT id AS titular_1    FROM titular  WHERE taller_id = :taller_1 AND nombre = 'Juana Pérez Soto' \gset
SELECT id AS disp_1       FROM dispositivo_diagnostico WHERE taller_id = :taller_1 AND estado = 'activo' \gset
SELECT id AS ses_pend     FROM sesion_diagnostico s WHERE s.taller_id = :taller_1 AND s.estado = 'pendiente'
                          AND EXISTS (SELECT 1 FROM cotizacion c WHERE c.sesion_id = s.id AND c.cerrada_en IS NULL) \gset
SELECT id AS cot_borrador FROM cotizacion WHERE sesion_id = :ses_pend AND cerrada_en IS NULL \gset
SELECT id AS dtc_p0301    FROM dtc_catalogo WHERE codigo = 'P0301' \gset
SELECT id AS comp_bujia   FROM componente_repuesto WHERE nombre = 'Bujía' \gset
SELECT id AS rep_ngk      FROM repuesto WHERE codigo_fabricante = 'ILKAR7B11' \gset

-- ------------------------------------------------------------ multi-taller
\set prueba 'RN-01 una sesion sin taller_id se rechaza'
\set esperado 23502
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, metodo_ingreso, kilometraje)
VALUES (NULL, :veh_hilux_1, :mec_1, 'manual', 10);
\ir incluir/error.sql

\set prueba 'RN-02 FK compuesta: una sesion del taller 2 no puede apuntar a un vehiculo del taller 1'
\set esperado 23503
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, metodo_ingreso, kilometraje)
VALUES (:taller_2, :veh_hilux_1, :mec_2, 'manual', 10);
\ir incluir/error.sql

\set prueba 'RN-02 FK compuesta: una sesion del taller 1 no puede quedar a nombre de un usuario del taller 2'
\set esperado 23503
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, metodo_ingreso, kilometraje)
VALUES (:taller_1, :veh_hilux_1, :mec_2, 'manual', 10);
\ir incluir/error.sql

\set prueba 'RN-02 FK compuesta: un vehiculo del taller 2 no puede tener un titular del taller 1'
\set esperado 23503
INSERT INTO vehiculo (taller_id, titular_id, modelo_vehiculo_id, anio, motor, patente)
VALUES (:taller_2, :titular_1, :modelo_hilux, 2020, '2.4', 'WXYZ11');
\ir incluir/error.sql

\set prueba 'RN-02 un vehiculo con sesiones no puede cambiar de taller'
\set esperado 23503
UPDATE vehiculo SET taller_id = :taller_2, titular_id = NULL WHERE id = :veh_hilux_1;
\ir incluir/error.sql

\set prueba 'RN-03 email con mayusculas se rechaza'
\set esperado 23514
INSERT INTO usuario (taller_id, email, nombre, rol) VALUES (:taller_1, 'Nuevo@losaromos.example', 'Nuevo', 'mecanico');
\ir incluir/error.sql

\set prueba 'RN-03 email sin formato valido se rechaza'
\set esperado 23514
INSERT INTO usuario (taller_id, email, nombre, rol) VALUES (:taller_1, 'sin-arroba', 'Nuevo', 'mecanico');
\ir incluir/error.sql

\set prueba 'RN-03 el email es unico entre TODOS los talleres'
\set esperado 23505
INSERT INTO usuario (taller_id, email, nombre, rol) VALUES (:taller_2, 'mecanico1@losaromos.example', 'Otro', 'mecanico');
\ir incluir/error.sql

\set prueba 'RN-04 margen sobre 200 % se rechaza'
\set esperado 23514
UPDATE taller_configuracion SET margen_pct = 200.01 WHERE taller_id = :taller_1;
\ir incluir/error.sql

\set prueba 'RN-04 margen negativo se rechaza'
\set esperado 23514
UPDATE taller_configuracion SET margen_pct = -0.01 WHERE taller_id = :taller_1;
\ir incluir/error.sql

\set prueba 'RN-04 los limites 0 y 200 se aceptan'
UPDATE taller_configuracion SET margen_pct = 0 WHERE taller_id = :taller_1;
UPDATE taller_configuracion SET margen_pct = 200 WHERE taller_id = :taller_1;
\ir incluir/exito.sql
UPDATE taller_configuracion SET margen_pct = 30 WHERE taller_id = :taller_1;

\set prueba 'Retencion fuera de 0-30 anios se rechaza'
\set esperado 23514
UPDATE taller_configuracion SET retencion_anios = 31 WHERE taller_id = :taller_1;
\ir incluir/error.sql

\set prueba 'Moneda que no es un codigo de 3 letras mayusculas se rechaza'
\set esperado 23514
UPDATE taller_configuracion SET moneda = 'clp' WHERE taller_id = :taller_1;
\ir incluir/error.sql

-- ---------------------------------------------------------------- vehiculo
\set prueba 'RN-10 VIN con la letra I se rechaza'
\set esperado 23514
INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, motor, vin, patente)
VALUES (:taller_1, :modelo_hilux, 2020, '2.4', '8AJFR22G5B451234I', 'WXYZ11');
\ir incluir/error.sql

\set prueba 'RN-10 VIN de 16 caracteres se rechaza'
\set esperado 23514
INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, motor, vin, patente)
VALUES (:taller_1, :modelo_hilux, 2020, '2.4', '8AJFR22G5B451234', 'WXYZ11');
\ir incluir/error.sql

\set prueba 'RN-11 patente en minusculas se rechaza'
\set esperado 23514
INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, motor, patente)
VALUES (:taller_1, :modelo_hilux, 2020, '2.4', 'wxyz11');
\ir incluir/error.sql

\set prueba 'RN-11 patente nueva con vocales se rechaza'
\set esperado 23514
INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, motor, patente)
VALUES (:taller_1, :modelo_hilux, 2020, '2.4', 'BACA11');
\ir incluir/error.sql

\set prueba 'RN-11 los dos formatos validos (AA1234 y BBBB12) se aceptan'
INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, motor, patente) VALUES
  (:taller_1, :modelo_hilux, 2005, '2.5', 'AB1234'),
  (:taller_1, :modelo_hilux, 2020, '2.4', 'WXYZ11');
\set esperado 2
\ir incluir/filas.sql

\set prueba 'RN-12 vehiculo no anonimizado sin patente se rechaza'
\set esperado 23514
INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, motor) VALUES (:taller_1, :modelo_hilux, 2020, '2.4');
\ir incluir/error.sql

\set prueba 'RN-13 sin VIN y sin motor se rechaza'
\set esperado 23514
INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, patente) VALUES (:taller_1, :modelo_hilux, 2020, 'WXYZ12');
\ir incluir/error.sql

\set prueba 'RN-13 con VIN el motor es opcional'
INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, vin, patente)
VALUES (:taller_1, :modelo_hilux, 2020, '8AJFR22G5B4599999', 'WXYZ12');
\ir incluir/exito.sql

\set prueba 'RN-14 anio 1980 se rechaza'
\set esperado 23514
INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, motor, patente) VALUES (:taller_1, :modelo_hilux, 1980, '2.4', 'WXYZ13');
\ir incluir/error.sql

\set prueba 'RN-15 patente repetida en el mismo taller se rechaza'
\set esperado 23505
INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, motor, patente) VALUES (:taller_1, :modelo_hilux, 2020, '2.4', 'LPRS56');
\ir incluir/error.sql

\set prueba 'RN-15 VIN repetido en el mismo taller se rechaza'
\set esperado 23505
INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, motor, vin, patente)
VALUES (:taller_1, :modelo_hilux, 2020, '2.4', '8AJFR22G5B4512345', 'WXYZ13');
\ir incluir/error.sql

\set prueba 'RN-15 la misma patente y el mismo VIN en OTRO taller se aceptan'
INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, motor, vin, patente)
VALUES (:taller_2, :modelo_hilux, 2021, '2.4', '8AJFR22G5B4512345', 'LPRS56');
\ir incluir/exito.sql

\set prueba 'RN-16 marcar anonimizado un vehiculo que conserva la patente se rechaza'
\set esperado 23514
UPDATE vehiculo SET anonimizado_en = now() WHERE id = :veh_hilux_1;
\ir incluir/error.sql

-- ------------------------------------------------------------- diagnostico
\set prueba 'RN-20 metodo obd_bluetooth sin dispositivo se rechaza'
\set esperado 23514
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, metodo_ingreso, kilometraje)
VALUES (:taller_1, :veh_hilux_1, :mec_1, 'obd_bluetooth', 10);
\ir incluir/error.sql

\set prueba 'RN-20 metodo manual con dispositivo se rechaza'
\set esperado 23514
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, dispositivo_id, metodo_ingreso, kilometraje)
VALUES (:taller_1, :veh_hilux_1, :mec_1, :disp_1, 'manual', 10);
\ir incluir/error.sql

\set prueba 'RN-21 kilometraje negativo se rechaza'
\set esperado 23514
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, metodo_ingreso, kilometraje)
VALUES (:taller_1, :veh_hilux_1, :mec_1, 'manual', -1);
\ir incluir/error.sql

\set prueba 'RN-22 el mismo DTC dos veces en una sesion se rechaza'
\set esperado 23505
INSERT INTO falla_sesion (sesion_id, dtc_id, taller_id, severidad)
SELECT f.sesion_id, f.dtc_id, f.taller_id, 'baja' FROM falla_sesion f WHERE f.sesion_id = :ses_pend LIMIT 1;
\ir incluir/error.sql

\set prueba 'RN-23 codigo DTC con formato invalido se rechaza'
\set esperado 23514
INSERT INTO dtc_catalogo (codigo, descripcion, severidad_sugerida) VALUES ('X0301', 'Invalido', 'baja');
\ir incluir/error.sql

\set prueba 'RN-23 falla con un DTC que no existe en el catalogo se rechaza'
\set esperado 23503
INSERT INTO falla_sesion (sesion_id, dtc_id, taller_id, severidad) VALUES (:ses_pend, 999999, :taller_1, 'baja');
\ir incluir/error.sql

\set prueba 'freeze_frame que no es un objeto JSON se rechaza'
\set esperado 23514
UPDATE falla_sesion SET freeze_frame = '[1, 2]' WHERE sesion_id = :ses_pend;
\ir incluir/error.sql

\set prueba 'RN-24 MAC mal formada se rechaza (tipo macaddr)'
\set esperado 22P02
INSERT INTO dispositivo_diagnostico (taller_id, mac) VALUES (:taller_1, '00:1D:A5:ZZ');
\ir incluir/error.sql

\set prueba 'RN-24 MAC repetida en el taller se rechaza, aunque se escriba con otro formato'
\set esperado 23505
INSERT INTO dispositivo_diagnostico (taller_id, mac) VALUES (:taller_1, '001da5-68988a');
\ir incluir/error.sql

-- ---------------------------------------------------------------- catalogo
\set prueba 'RN-41 durabilidad 0 se rechaza'
\set esperado 23514
UPDATE repuesto SET durabilidad_estimada_km = 0 WHERE id = :rep_ngk;
\ir incluir/error.sql

\set prueba 'RN-41 precio de referencia negativo se rechaza'
\set esperado 23514
UPDATE repuesto SET precio_referencia = -1 WHERE id = :rep_ngk;
\ir incluir/error.sql

\set prueba 'RN-42 (componente, marca, codigo_fabricante) repetido se rechaza'
\set esperado 23505
INSERT INTO repuesto (componente_id, perfil, marca, nombre, codigo_fabricante, durabilidad_estimada_km, riesgo, precio_referencia)
VALUES (:comp_bujia, 'generico', 'NGK', 'Duplicada', 'ILKAR7B11', 1000, 'alto', 100);
\ir incluir/error.sql

\set prueba 'RN-46 compatibilidad con anio_desde > anio_hasta se rechaza'
\set esperado 23514
INSERT INTO compatibilidad_repuesto (repuesto_id, modelo_vehiculo_id, anio_desde, anio_hasta)
VALUES (:rep_ngk, :modelo_hilux, 2000, 1999);
\ir incluir/error.sql

\set prueba 'RN-72 un DTC en uso no se puede borrar (ON DELETE RESTRICT)'
\set esperado 23503
DELETE FROM dtc_catalogo WHERE id = :dtc_p0301;
\ir incluir/error.sql

\set prueba 'RN-72 un usuario con sesiones no se puede borrar'
\set esperado 23503
DELETE FROM usuario WHERE id = :mec_1;
\ir incluir/error.sql

\set prueba 'RN-72 un vehiculo con sesiones no se puede borrar'
\set esperado 23503
DELETE FROM vehiculo WHERE id = :veh_hilux_1;
\ir incluir/error.sql

-- ------------------------------------------------------------ cotizaciones
\set prueba 'RN-52 un segundo borrador en la misma sesion se rechaza'
\set esperado 23505
INSERT INTO cotizacion (taller_id, sesion_id, clave_idempotencia) VALUES (:taller_1, :ses_pend, gen_random_uuid());
\ir incluir/error.sql

\set prueba 'RN-53 un borrador no puede marcarse vigente'
\set esperado 23514
UPDATE cotizacion SET vigente = true WHERE id = :cot_borrador;
\ir incluir/error.sql

\set prueba 'RN-54 un borrador no puede tener total (el trigger lo anula aunque se envie)'
UPDATE cotizacion SET total = 12345 WHERE id = :cot_borrador;
SELECT total IS NULL AS ok FROM cotizacion WHERE id = :cot_borrador \gset
\ir incluir/afirmar.sql

\set prueba 'RN-57 la clave de idempotencia es unica por taller'
\set esperado 23505
INSERT INTO cotizacion (taller_id, sesion_id, clave_idempotencia)
SELECT c.taller_id, (SELECT s.id FROM sesion_diagnostico s WHERE s.taller_id = :taller_1 AND s.estado = 'pendiente' AND s.id <> :ses_pend LIMIT 1),
       c.clave_idempotencia
FROM   cotizacion c WHERE c.id = :cot_borrador;
\ir incluir/error.sql

\set prueba 'RN-58 cantidad 0 se rechaza'
\set esperado 23514
UPDATE cotizacion_detalle SET cantidad = 0 WHERE cotizacion_id = :cot_borrador;
\ir incluir/error.sql

\set prueba 'RN-58 el mismo repuesto dos veces en una cotizacion se rechaza'
\set esperado 23505
INSERT INTO cotizacion_detalle (cotizacion_id, repuesto_id, taller_id, cantidad)
SELECT d.cotizacion_id, d.repuesto_id, d.taller_id, 1 FROM cotizacion_detalle d WHERE d.cotizacion_id = :cot_borrador LIMIT 1;
\ir incluir/error.sql

\set prueba 'RN-56 ni la plataforma puede cambiar el precio de una linea (RE012)'
\set esperado RE012
UPDATE cotizacion_detalle SET precio_unitario = 1 WHERE cotizacion_id = :cot_borrador;
\ir incluir/error.sql

\set prueba 'RN-45 toda linea cumple precio_unitario = ROUND(precio_referencia * (1 + margen / 100))'
SELECT count(*) > 0 AND bool_and(precio_unitario = ROUND(precio_referencia_snapshot * (1 + margen_pct_snapshot / 100))) AS ok
FROM   cotizacion_detalle \gset
\ir incluir/afirmar.sql

\set prueba 'RN-51 a lo mas una cotizacion vigente y un borrador por sesion (datos actuales)'
SELECT NOT EXISTS (SELECT 1 FROM cotizacion GROUP BY sesion_id HAVING count(*) FILTER (WHERE vigente) > 1
                                                               OR count(*) FILTER (WHERE cerrada_en IS NULL) > 1) AS ok \gset
\ir incluir/afirmar.sql

-- -------------------------------------------------------------- privacidad
\set prueba 'RN-60 identificador_hmac que no mide 32 bytes se rechaza'
\set esperado 23514
INSERT INTO titular (taller_id, nombre, identificador_hmac) VALUES (:taller_1, 'Prueba', '\x0102');
\ir incluir/error.sql

\set prueba 'RN-60 el mismo identificador_hmac dos veces en un taller se rechaza'
\set esperado 23505
INSERT INTO titular (taller_id, nombre, identificador_hmac)
SELECT taller_id, 'Duplicado', identificador_hmac FROM titular WHERE id = :titular_1;
\ir incluir/error.sql

\set prueba 'RN-60 el mismo identificador_hmac en otro taller se acepta'
INSERT INTO titular (taller_id, nombre, identificador_hmac)
SELECT :taller_2, 'Misma persona, otro taller', identificador_hmac FROM titular WHERE id = :titular_1;
\ir incluir/exito.sql

\set prueba 'Titular activo sin nombre se rechaza'
\set esperado 23514
INSERT INTO titular (taller_id, nombre) VALUES (:taller_1, '   ');
\ir incluir/error.sql

\set prueba 'Estado bloqueado sin fecha de vencimiento se rechaza'
\set esperado 23514
UPDATE titular SET estado_tratamiento = 'bloqueado' WHERE id = :titular_1;
\ir incluir/error.sql

\set prueba 'RN-63 estado anonimizado conservando el nombre se rechaza'
\set esperado 23514
UPDATE titular SET estado_tratamiento = 'anonimizado', anonimizado_en = now() WHERE id = :titular_1;
\ir incluir/error.sql

\set prueba 'RN-65 un segundo consentimiento activo para la misma finalidad se rechaza'
\set esperado 23505
INSERT INTO consentimiento_titular (taller_id, titular_id, finalidad, version_terminos, canal)
VALUES (:taller_1, :titular_1, 'prestacion_servicio', 'v2.0', 'web');
\ir incluir/error.sql

\set prueba 'RN-65 tras una revocacion se puede otorgar de nuevo la misma finalidad'
INSERT INTO consentimiento_titular (taller_id, titular_id, finalidad, version_terminos, canal)
VALUES (:taller_1, :titular_1, 'marketing', 'v2.0', 'web');
\ir incluir/exito.sql

\set prueba 'Canal de consentimiento fuera de la lista se rechaza'
\set esperado 23514
INSERT INTO consentimiento_titular (taller_id, titular_id, finalidad, version_terminos, canal)
VALUES (:taller_1, :titular_1, 'contacto_seguimiento', 'v2.0', 'fax');
\ir incluir/error.sql

\set prueba 'Revocacion anterior al otorgamiento se rechaza'
\set esperado 23514
UPDATE consentimiento_titular SET revocado_en = otorgado_en - interval '1 day'
WHERE  titular_id = :titular_1 AND finalidad = 'prestacion_servicio';
\ir incluir/error.sql

\set prueba 'Solicitud resuelta sin fecha de resolucion se rechaza'
\set esperado 23514
UPDATE solicitud_derecho_titular SET estado = 'resuelta' WHERE titular_id = :titular_1;
\ir incluir/error.sql

\set prueba 'Valor fuera de un tipo enumerado se rechaza'
\set esperado 22P02
UPDATE sesion_diagnostico SET estado = 'en_proceso' WHERE id = :ses_pend;
\ir incluir/error.sql

ROLLBACK;

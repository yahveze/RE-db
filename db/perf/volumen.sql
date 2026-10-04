-- =============================================================================
-- Carga de volumen sintetico para medir rendimiento (Fase 5).
-- Se ejecuta SOLO sobre la base de rendimiento (<base>_perf), clonada de la
-- principal con sus semillas. Nunca sobre la base principal.
--
-- Variables psql (las fija db/perf/run.sh):
--   sesiones_grande   sesiones del taller grande ("Taller Volumen 01")
--   sesiones_chico    sesiones de cada uno de los otros talleres de volumen
--   talleres          cantidad de talleres de volumen
--   auditoria         filas de auditoria
--
-- Como se carga. Con session_replication_role = replica los triggers y las FK
-- no se ejecutan: es una carga masiva, no el flujo de negocio (ese ya lo
-- recorren las semillas y lo verifica la suite). Los CHECK, UNIQUE y NOT NULL
-- SI se evaluan, asi que los datos generados cumplen todas las reglas
-- declarativas: estados con sus timestamps, formula del precio, una vigente por
-- sesion, patentes validas y unicas por taller.
--
-- Distribucion pensada para que los planes se parezcan a los reales:
--   * un taller grande y varios chicos (la selectividad de taller_id importa);
--   * sesiones repartidas en 3 anios; pendientes y cotizadas solo entre las de
--     los ultimos 20 dias, el resto completadas o canceladas;
--   * catalogo ampliado: 1.000 DTC, 100 componentes, ~9.000 repuestos y
--     ~225.000 compatibilidades.
-- =============================================================================
\set ON_ERROR_STOP on
\encoding UTF8
SET session_replication_role = replica;
SELECT setseed(0.42) \gset semilla_

BEGIN;

-- ----------------------------------------------------------------------------
-- Catalogo
-- ----------------------------------------------------------------------------
INSERT INTO marca_vehiculo (nombre)
SELECT 'Marca ' || lpad(g::text, 2, '0') FROM generate_series(1, 34) g;

INSERT INTO modelo_vehiculo (marca_vehiculo_id, nombre)
SELECT m.id, 'Modelo ' || g
FROM   marca_vehiculo m, generate_series(1, 15) g
WHERE  m.nombre LIKE 'Marca %';

INSERT INTO componente_repuesto (nombre)
SELECT 'Componente ' || lpad(g::text, 3, '0') FROM generate_series(1, 90) g;

INSERT INTO dtc_catalogo (codigo, descripcion, severidad_sugerida)
SELECT 'P' || (1000 + g), 'Falla sintetica ' || g, (ARRAY['baja', 'media', 'alta', 'critica'])[1 + g % 4]::tipo_severidad
FROM   generate_series(0, 987) g;

CREATE TEMP TABLE v_comp AS
SELECT id, row_number() OVER (ORDER BY id) - 1 AS n FROM componente_repuesto WHERE nombre LIKE 'Componente %';

-- Cada DTC sintetico apunta a 3 componentes distintos.
INSERT INTO dtc_componente (dtc_id, componente_id)
SELECT d.id, c.id
FROM  (SELECT id, row_number() OVER (ORDER BY id) AS n FROM dtc_catalogo WHERE descripcion LIKE 'Falla sintetica%') d
CROSS  JOIN generate_series(0, 2) k
JOIN   v_comp c ON c.n = (d.n * 7 + k * 31) % 90;

-- 100 repuestos por componente sintetico, repartidos en los tres perfiles.
INSERT INTO repuesto (componente_id, perfil, marca, nombre, codigo_fabricante,
                      durabilidad_estimada_km, riesgo, precio_referencia)
SELECT c.id,
       (ARRAY['genuino', 'oem', 'generico'])[1 + g % 3]::tipo_perfil_repuesto,
       'Fabricante ' || (g % 25),
       'Repuesto ' || c.n || '-' || g,
       'SIN-' || c.n || '-' || g,
       20000 + (g * 997) % 180000,
       (ARRAY['bajo', 'medio', 'alto'])[1 + g % 3]::tipo_nivel_riesgo,
       3000 + (random() * 500000)::int
FROM   v_comp c, generate_series(1, 100) g;

-- Arreglos de ids para elegir por posicion.
CREATE TEMP TABLE v_arr AS
SELECT (SELECT array_agg(id ORDER BY id) FROM modelo_vehiculo)                           AS modelo,
       (SELECT array_agg(id ORDER BY id) FROM dtc_catalogo)                              AS dtc,
       (SELECT array_agg(id ORDER BY id) FROM repuesto WHERE disponible)                 AS repuesto;

-- Cada repuesto sintetico es compatible con 25 modelos distintos.
INSERT INTO compatibilidad_repuesto (repuesto_id, modelo_vehiculo_id, anio_desde, anio_hasta)
SELECT r.id, a.modelo[1 + (r.n * 17 + k * 21) % cardinality(a.modelo)], 2000 + (r.n % 10), 2012 + (r.n % 15)
FROM  (SELECT id, row_number() OVER (ORDER BY id) AS n FROM repuesto WHERE codigo_fabricante LIKE 'SIN-%') r
CROSS  JOIN generate_series(0, 24) k
CROSS  JOIN v_arr a;

-- ----------------------------------------------------------------------------
-- Talleres, usuarios y dispositivos
-- ----------------------------------------------------------------------------
INSERT INTO taller (nombre)
SELECT 'Taller Volumen ' || lpad(g::text, 2, '0') FROM generate_series(1, :talleres) g;

-- Tamanios por taller: el 01 es el grande.
CREATE TEMP TABLE v_taller AS
SELECT t.id,
       row_number() OVER (ORDER BY t.id) AS n,
       CASE WHEN t.nombre = 'Taller Volumen 01' THEN :sesiones_grande ELSE :sesiones_chico END AS n_sesiones
FROM   taller t WHERE t.nombre LIKE 'Taller Volumen %';
ALTER TABLE v_taller ADD COLUMN n_vehiculos integer, ADD COLUMN n_titulares integer;
UPDATE v_taller SET n_vehiculos = greatest(n_sesiones / 5, 10), n_titulares = greatest(n_sesiones / 8, 10);

INSERT INTO taller_configuracion (taller_id) SELECT id FROM v_taller;

INSERT INTO usuario (taller_id, email, nombre, rol)
SELECT t.id,
       x.prefijo || '@volumen' || lpad(t.n::text, 2, '0') || '.example',
       x.nombre || ' ' || t.n,
       x.rol::tipo_rol_usuario
FROM   v_taller t
CROSS  JOIN (SELECT 'admin' AS prefijo, 'Administrador' AS nombre, 'admin' AS rol
             UNION ALL SELECT 'auditor', 'Auditor', 'auditor'
             UNION ALL SELECT 'mecanico' || g, 'Mecanico ' || g, 'mecanico' FROM generate_series(1, 8) g) x;

-- Credenciales solo para el taller grande (bcrypt es caro a proposito).
INSERT INTO usuario_credencial (usuario_id, hash_contrasena)
SELECT u.id, crypt(:'clave_demo', gen_salt('bf', 10))
FROM   usuario u JOIN v_taller t ON t.id = u.taller_id
WHERE  t.n = 1 AND (u.rol <> 'mecanico' OR u.email LIKE 'mecanico1@%');

INSERT INTO dispositivo_diagnostico (taller_id, mac, fabricante, modelo, firmware)
SELECT t.id, ('02' || lpad(to_hex(t.n::int), 4, '0') || lpad(to_hex(g), 6, '0'))::macaddr, 'OBDLink', 'MX+', '5.6.19'
FROM   v_taller t, generate_series(1, 3) g;

CREATE TEMP TABLE v_mecanico AS
SELECT u.id, u.taller_id, row_number() OVER (PARTITION BY u.taller_id ORDER BY u.id) AS n
FROM   usuario u JOIN v_taller t ON t.id = u.taller_id WHERE u.rol = 'mecanico';
CREATE TEMP TABLE v_dispositivo AS
SELECT d.id, d.taller_id, row_number() OVER (PARTITION BY d.taller_id ORDER BY d.id) AS n
FROM   dispositivo_diagnostico d JOIN v_taller t ON t.id = d.taller_id;

-- ----------------------------------------------------------------------------
-- Titulares y vehiculos
-- ----------------------------------------------------------------------------
INSERT INTO titular (taller_id, nombre, telefono)
SELECT t.id, 'Titular ' || g, '+569' || lpad(g::text, 8, '0')
FROM   v_taller t, generate_series(1, t.n_titulares) g;

CREATE TEMP TABLE v_titular AS
SELECT x.id, x.taller_id, row_number() OVER (PARTITION BY x.taller_id ORDER BY x.id) AS n
FROM   titular x JOIN v_taller t ON t.id = x.taller_id;
CREATE INDEX ON v_titular (taller_id, n);
ANALYZE v_titular;

INSERT INTO consentimiento_titular (taller_id, titular_id, finalidad, version_terminos, canal, otorgado_en)
SELECT x.taller_id, x.id, 'prestacion_servicio', 'v1.0', 'presencial', now() - interval '400 days'
FROM   v_titular x;

-- Patente: 4 consonantes + 2 digitos, unica por taller (1 de cada 10 vehiculos
-- no tiene titular registrado). La mitad tiene VIN.
INSERT INTO vehiculo (taller_id, titular_id, modelo_vehiculo_id, anio, motor, vin, patente)
SELECT t.id,
       x.id,
       a.modelo[1 + (g * 31) % cardinality(a.modelo)],
       2003 + g % 22,
       (ARRAY['1.2', '1.4', '1.6', '2.0', '2.4'])[1 + g % 5] || ' Bencina',
       CASE WHEN g % 2 = 0 THEN 'VF' || lpad(t.n::text, 3, '0') || lpad(g::text, 12, '0') END,
          substr('BCDFGHJKLPRSTVWXYZ', 1 + (g / 100) % 18, 1)
       || substr('BCDFGHJKLPRSTVWXYZ', 1 + (g / 1800) % 18, 1)
       || substr('BCDFGHJKLPRSTVWXYZ', 1 + (g / 32400) % 18, 1)
       || substr('BCDFGHJKLPRSTVWXYZ', 1 + (g / 583200) % 18, 1)
       || lpad((g % 100)::text, 2, '0')
FROM   v_taller t
CROSS  JOIN generate_series(1, t.n_vehiculos) g
CROSS  JOIN v_arr a
LEFT   JOIN v_titular x ON x.taller_id = t.id AND x.n = 1 + g % t.n_titulares AND g % 10 <> 0;

CREATE TEMP TABLE v_vehiculo AS
SELECT v.id, v.taller_id, row_number() OVER (PARTITION BY v.taller_id ORDER BY v.id) AS n
FROM   vehiculo v JOIN v_taller t ON t.id = v.taller_id;
CREATE INDEX ON v_vehiculo (taller_id, n);
ANALYZE v_vehiculo;

-- ----------------------------------------------------------------------------
-- Sesiones: repartidas en 1.095 dias. Entre las de los ultimos 20 dias hay
-- pendientes y cotizadas; las anteriores estan completadas (88 %) o canceladas.
-- ----------------------------------------------------------------------------
INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, dispositivo_id, metodo_ingreso, kilometraje,
                                estado, iniciada_en, cotizada_en, completada_en, cancelada_en, version)
SELECT z.taller_id, z.vehiculo_id, z.usuario_id, z.dispositivo_id,
       CASE WHEN z.dispositivo_id IS NULL THEN 'manual' ELSE 'obd_bluetooth' END::tipo_metodo_ingreso,
       10000 + (z.g * 37) % 290000,
       z.estado,
       z.iniciada_en,
       CASE WHEN z.estado IN ('cotizado', 'completado') OR (z.estado = 'cancelado' AND z.g % 2 = 0)
            THEN z.iniciada_en + interval '1 hour' END,
       CASE WHEN z.estado = 'completado' THEN z.iniciada_en + interval '1 day' END,
       CASE WHEN z.estado = 'cancelado'  THEN z.iniciada_en + interval '2 hours' END,
       CASE z.estado WHEN 'pendiente' THEN 1 WHEN 'completado' THEN 3 ELSE 2 END
FROM  (SELECT t.id AS taller_id, g, v.id AS vehiculo_id, m.id AS usuario_id, d.id AS dispositivo_id,
              now() - (interval '1095 days' * (g::float8 / t.n_sesiones)) - interval '1 minute' * (g % 600) AS iniciada_en,
              CASE WHEN g::float8 / t.n_sesiones < 20.0 / 1095
                   THEN (ARRAY['pendiente', 'pendiente', 'pendiente', 'pendiente', 'cotizado', 'cotizado', 'cotizado',
                               'completado', 'completado', 'cancelado'])[1 + g % 10]
                   ELSE CASE WHEN g % 25 < 22 THEN 'completado' ELSE 'cancelado' END
              END::tipo_estado_atencion AS estado
       FROM   v_taller t
       CROSS  JOIN generate_series(1, t.n_sesiones) g
       JOIN   v_vehiculo v ON v.taller_id = t.id AND v.n = 1 + (g::bigint * 7919) % t.n_vehiculos
       JOIN   v_mecanico m ON m.taller_id = t.id AND m.n = 1 + g % 8
       LEFT   JOIN v_dispositivo d ON d.taller_id = t.id AND d.n = 1 + g % 3 AND g % 2 = 0) z;

-- 1 a 3 fallas por sesion; 1 de cada 20 es critica.
INSERT INTO falla_sesion (sesion_id, dtc_id, taller_id, severidad, freeze_frame)
SELECT s.id,
       a.dtc[1 + (s.id * 13 + k * 101) % cardinality(a.dtc)],
       s.taller_id,
       CASE WHEN (s.id + k) % 20 = 0 THEN 'critica' ELSE (ARRAY['baja', 'media', 'alta'])[1 + (s.id + k) % 3] END::tipo_severidad,
       CASE WHEN s.dispositivo_id IS NOT NULL THEN jsonb_build_object('rpm', 700 + s.id % 3000, 'velocidad_kmh', s.id % 120) END
FROM   sesion_diagnostico s
JOIN   v_taller t ON t.id = s.taller_id
CROSS  JOIN v_arr a
CROSS  JOIN LATERAL generate_series(0, (s.id % 3)::int) k;

-- ----------------------------------------------------------------------------
-- Cotizaciones. Toda sesion con cotizada_en tiene una vigente cerrada; 1 de
-- cada 5 tiene ademas una revision anterior. 1 de cada 3 pendientes tiene un
-- borrador. El total se fija despues de cargar el detalle.
-- ----------------------------------------------------------------------------
INSERT INTO cotizacion (taller_id, sesion_id, numero_revision, vigente, cerrada_en, total, moneda, clave_idempotencia, version, creado_en)
SELECT s.taller_id, s.id, r.revision,
       r.revision = (CASE WHEN s.id % 5 = 0 THEN 2 ELSE 1 END),
       s.cotizada_en, 0, 'CLP', gen_random_uuid(), 2, s.iniciada_en + interval '30 minutes'
FROM   sesion_diagnostico s
JOIN   v_taller t ON t.id = s.taller_id
CROSS  JOIN LATERAL generate_series(1, CASE WHEN s.id % 5 = 0 THEN 2 ELSE 1 END) AS r (revision)
WHERE  s.cotizada_en IS NOT NULL;

INSERT INTO cotizacion (taller_id, sesion_id, numero_revision, vigente, cerrada_en, total, moneda, clave_idempotencia, version, creado_en)
SELECT s.taller_id, s.id, 1, false, NULL, NULL, 'CLP', gen_random_uuid(), 1, s.iniciada_en + interval '30 minutes'
FROM   sesion_diagnostico s
JOIN   v_taller t ON t.id = s.taller_id
WHERE  s.estado = 'pendiente' AND s.id % 3 = 0;

INSERT INTO cotizacion_detalle (cotizacion_id, repuesto_id, taller_id, cantidad, nombre_snapshot, marca_snapshot,
                                perfil_snapshot, precio_referencia_snapshot, margen_pct_snapshot, precio_unitario, creado_en)
SELECT c.id, r.id, c.taller_id, 1 + k % 3, r.nombre, r.marca, r.perfil, r.precio_referencia, 30.00,
       ROUND(r.precio_referencia * 1.30), c.creado_en
FROM   cotizacion c
JOIN   v_taller t ON t.id = c.taller_id
CROSS  JOIN v_arr a
CROSS  JOIN LATERAL generate_series(0, (c.id % 4)::int) k
JOIN   repuesto r ON r.id = a.repuesto[1 + (c.id * 17 + k * 1009) % cardinality(a.repuesto)];

UPDATE cotizacion c
SET    total = x.total
FROM  (SELECT d.cotizacion_id, sum(d.cantidad::bigint * d.precio_unitario) AS total
       FROM cotizacion_detalle d JOIN v_taller t ON t.id = d.taller_id GROUP BY d.cotizacion_id) x
WHERE  x.cotizacion_id = c.id AND c.cerrada_en IS NOT NULL;

-- ----------------------------------------------------------------------------
-- Auditoria: la mitad del taller grande, el resto repartida.
-- ----------------------------------------------------------------------------
INSERT INTO auditoria_operacion (ocurrido_en, taller_id, usuario_id, rol, operacion, tabla, registro_id,
                                 datos_nuevos, ip_origen, resultado, request_id)
SELECT now() - interval '1095 days' * (g::float8 / :auditoria),
       CASE WHEN g % 2 = 0 THEN (SELECT id FROM v_taller WHERE n = 1)
            ELSE (SELECT min(id) FROM v_taller) + 1 + g % (:talleres - 1) END,
       NULL,
       'taller_mecanico',
       (ARRAY['INSERT', 'UPDATE'])[1 + g % 2]::tipo_operacion_auditoria,
       (ARRAY['sesion_diagnostico', 'falla_sesion', 'cotizacion', 'cotizacion_detalle', 'vehiculo', 'titular'])[1 + g % 6],
       g,
       jsonb_build_object('id', g, 'estado', 'pendiente', 'version', 1),
       '10.0.0.1',
       'exito',
       'vol-' || g
FROM   generate_series(1, :auditoria) g;

COMMIT;
SET session_replication_role = origin;

\echo '--- Volumen cargado (filas por tabla) ---'
SELECT (SELECT count(*) FROM taller)                  AS talleres,
       (SELECT count(*) FROM usuario)                 AS usuarios,
       (SELECT count(*) FROM titular)                 AS titulares,
       (SELECT count(*) FROM vehiculo)                AS vehiculos,
       (SELECT count(*) FROM sesion_diagnostico)      AS sesiones,
       (SELECT count(*) FROM falla_sesion)            AS fallas,
       (SELECT count(*) FROM cotizacion)              AS cotizaciones,
       (SELECT count(*) FROM cotizacion_detalle)      AS lineas,
       (SELECT count(*) FROM auditoria_operacion)     AS auditoria;
SELECT (SELECT count(*) FROM dtc_catalogo)            AS dtc,
       (SELECT count(*) FROM componente_repuesto)     AS componentes,
       (SELECT count(*) FROM dtc_componente)          AS dtc_componente,
       (SELECT count(*) FROM repuesto)                AS repuestos,
       (SELECT count(*) FROM compatibilidad_repuesto) AS compatibilidades,
       (SELECT count(*) FROM modelo_vehiculo)         AS modelos;

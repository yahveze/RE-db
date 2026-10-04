-- =============================================================================
-- Semilla 03 - Operacion: titulares, consentimientos, vehiculos y atenciones.
--
-- Cada bloque es una transaccion de UN mecanico, con su rol y su contexto:
--     BEGIN; SET LOCAL ROLE taller_mecanico; set_config('app.taller_id', ...);
-- La politica de insercion de sesion_diagnostico exige usuario_id = contexto,
-- por eso cada mecanico registra sus propias atenciones.
--
-- Las atenciones recorren el flujo real (incluir/flujo_atencion.sql). Cubren:
-- los cuatro estados, ingreso manual y por OBD, varias revisiones, un borrador,
-- una cancelacion desde 'cotizado', un DTC sin componente y un vehiculo cuyo
-- anio deja fuera a genuinos y OEM.
--
-- identificador_hmac: en produccion lo calcula el backend con su propia clave
-- secreta. Aqui se simula con hmac() de pgcrypto y la clave de demostracion,
-- sobre identificadores ficticios, para no escribir ningun secreto en el archivo.
-- =============================================================================
\encoding UTF8
\o /dev/null

SELECT id AS taller_1 FROM taller WHERE nombre = 'Taller Mecánico Los Aromos' \gset
SELECT id AS taller_2 FROM taller WHERE nombre = 'Servicio Automotriz Ñuble'  \gset
SELECT id AS mecanico_1a FROM usuario WHERE email = 'mecanico1@losaromos.example' \gset
SELECT id AS mecanico_1b FROM usuario WHERE email = 'mecanico2@losaromos.example' \gset
SELECT id AS mecanico_2  FROM usuario WHERE email = 'mecanico@nuble.example'      \gset

-- ============================================================================
-- Taller 1 - mecanico 1 (Diego Rojas)
-- ============================================================================
BEGIN;
SET LOCAL ROLE taller_mecanico;
SELECT set_config('app.taller_id',  :'taller_1',    true),
       set_config('app.usuario_id', :'mecanico_1a', true),
       set_config('app.ip_origen',  '192.168.10.21', true),
       set_config('app.request_id', 'semilla-03-mecanico-1a', true);

INSERT INTO titular (taller_id, nombre, telefono, email, identificador_hmac) VALUES
  (:taller_1, 'Juana Pérez Soto',  '+56911111111', 'juana.perez@correo.example', hmac('ID-DEMO-001', :'clave_demo', 'sha256')),
  (:taller_1, 'Marco Díaz Leiva',  '+56922222222', NULL,                         hmac('ID-DEMO-002', :'clave_demo', 'sha256')),
  (:taller_1, 'Elena Vargas Mora', '+56933333333', 'elena.vargas@correo.example', hmac('ID-DEMO-003', :'clave_demo', 'sha256')),
  (:taller_1, 'Tomás Reyes Cid',   '+56944444444', NULL,                         NULL);

INSERT INTO consentimiento_titular (taller_id, titular_id, finalidad, version_terminos, canal, otorgado_en)
SELECT :taller_1, t.id, x.finalidad::tipo_finalidad_tratamiento, 'v1.0', x.canal, now() - x.hace::interval
FROM  (VALUES
  ('Juana Pérez Soto',  'prestacion_servicio',  'presencial', '75 days'),
  ('Juana Pérez Soto',  'contacto_seguimiento', 'presencial', '75 days'),
  ('Juana Pérez Soto',  'marketing',            'app',        '70 days'),
  ('Marco Díaz Leiva',  'prestacion_servicio',  'presencial', '52 days'),
  ('Elena Vargas Mora', 'prestacion_servicio',  'web',        '40 days'),
  ('Elena Vargas Mora', 'contacto_seguimiento', 'web',        '40 days'),
  ('Tomás Reyes Cid',   'prestacion_servicio',  'telefono',   '33 days')
) AS x (titular, finalidad, canal, hace)
JOIN titular t ON t.nombre = x.titular;

-- Revocacion: la fila no se borra, se fija revocado_en.
UPDATE consentimiento_titular c
SET    revocado_en = now() - interval '10 days'
FROM   titular t
WHERE  t.id = c.titular_id
AND    t.nombre = 'Juana Pérez Soto'
AND    c.finalidad = 'marketing';

-- La Corolla es 2006: los genuinos (2010+) y los OEM (2008+) no le sirven.
-- La Morning no tiene titular registrado (titular_id NULL).
INSERT INTO vehiculo (taller_id, titular_id, modelo_vehiculo_id, anio, motor, vin, patente)
SELECT :taller_1, t.id, mo.id, x.anio, x.motor, x.vin, x.patente
FROM  (VALUES
  ('Juana Pérez Soto',  'Toyota',    'Hilux',   2021, '2.4 Diésel',   '8AJFR22G5B4512345', 'LPRS56'),
  ('Marco Díaz Leiva',  'Toyota',    'Yaris',   2018, '1.5 Bencina',  'JTDBR32E720123456', 'GHJK34'),
  ('Marco Díaz Leiva',  'Toyota',    'Corolla', 2006, '1.6 Bencina',  NULL,                'XK4521'),
  ('Elena Vargas Mora', 'Hyundai',   'Accent',  2019, '1.4 Bencina',  'KMHCT41DAEU123456', 'BCDF12'),
  ('Tomás Reyes Cid',   'Chevrolet', 'Sail',    2016, '1.5 Bencina',  NULL,                'TVWX78'),
  (NULL,                'Kia',       'Morning', 2015, '1.0 Bencina',  NULL,                'DFGH21')
) AS x (titular, marca, modelo, anio, motor, vin, patente)
JOIN      marca_vehiculo  ma ON ma.nombre = x.marca
JOIN      modelo_vehiculo mo ON mo.marca_vehiculo_id = ma.id AND mo.nombre = x.modelo
LEFT JOIN titular         t  ON t.nombre = x.titular;

SELECT set_config('semilla.atenciones', $json$[
  {"patente": "LPRS56", "mac": "00:1D:A5:68:98:8A", "km": 84500, "hace": "75 days", "final": "completado",
   "fallas": [{"codigo": "P0301", "severidad": "critica",
               "freeze_frame": {"rpm": 850, "temperatura_refrigerante_c": 92, "velocidad_kmh": 0, "carga_motor_pct": 31.4}},
              {"codigo": "P0300"}],
   "revisiones": [[{"repuesto": "90919-01253", "cantidad": 4}, {"repuesto": "673-1307", "cantidad": 1}]]},

  {"patente": "GHJK34", "km": 61200, "hace": "52 days", "final": "completado",
   "fallas": [{"codigo": "P0420"}, {"codigo": "P0135"}],
   "revisiones": [[{"repuesto": "GEN-CAT-01", "cantidad": 1}, {"repuesto": "0258006537", "cantidad": 1}],
                  [{"repuesto": "25051-0C011", "cantidad": 1}, {"repuesto": "0258006537", "cantidad": 1}]]},

  {"patente": "BCDF12", "mac": "00:1D:A5:68:98:8A", "km": 45210, "hace": "40 days", "final": "completado",
   "fallas": [{"codigo": "P0171",
               "freeze_frame": {"rpm": 2100, "ajuste_combustible_largo_pct": 18.7, "velocidad_kmh": 64}}],
   "revisiones": [[{"repuesto": "0280218190", "cantidad": 1}, {"repuesto": "28113-1R100", "cantidad": 1}]]},

  {"patente": "TVWX78", "km": 112300, "hace": "33 days", "final": "cancelado",
   "fallas": [{"codigo": "P0335"}]},

  {"patente": "XK4521", "km": 238900, "hace": "20 days", "final": "cotizado",
   "fallas": [{"codigo": "P0401"}],
   "revisiones": [[{"repuesto": "GEN-EGR-01", "cantidad": 1}]]},

  {"patente": "LPRS56", "mac": "00:1D:A5:68:98:8A", "km": 91800, "hace": "6 days", "final": "cotizado",
   "fallas": [{"codigo": "C0035", "freeze_frame": {"velocidad_kmh": 48, "abs_activo": true}}],
   "revisiones": [[{"repuesto": "89543-0K020", "cantidad": 1}]],
   "borrador": [{"repuesto": "0265007905", "cantidad": 1}]},

  {"patente": "DFGH21", "mac": "00:1D:A5:68:98:8A", "km": 143750, "hace": "2 days", "final": "pendiente",
   "fallas": [{"codigo": "P0201"}, {"codigo": "P0300", "severidad": "media"}],
   "borrador": [{"repuesto": "GEN-INY-01", "cantidad": 3}, {"repuesto": "ILKAR7B11", "cantidad": 3}]},

  {"patente": "GHJK34", "km": 66480, "hace": "3 hours", "final": "pendiente",
   "fallas": [{"codigo": "U0100"}]}
]$json$, true);

\ir incluir/flujo_atencion.sql

COMMIT;

-- ============================================================================
-- Taller 1 - mecanico 2 (Paula Soto)
-- ============================================================================
BEGIN;
SET LOCAL ROLE taller_mecanico;
SELECT set_config('app.taller_id',  :'taller_1',    true),
       set_config('app.usuario_id', :'mecanico_1b', true),
       set_config('app.ip_origen',  '192.168.10.22', true),
       set_config('app.request_id', 'semilla-03-mecanico-1b', true);

INSERT INTO titular (taller_id, nombre, telefono, email, identificador_hmac) VALUES
  (:taller_1, 'Sofía Castro Vera', '+56955555555', 'sofia.castro@correo.example', hmac('ID-DEMO-005', :'clave_demo', 'sha256'));

INSERT INTO consentimiento_titular (taller_id, titular_id, finalidad, version_terminos, canal, otorgado_en)
SELECT :taller_1, t.id, 'prestacion_servicio', 'v1.0', 'app', now() - interval '60 days'
FROM   titular t
WHERE  t.nombre = 'Sofía Castro Vera';

INSERT INTO vehiculo (taller_id, titular_id, modelo_vehiculo_id, anio, motor, vin, patente)
SELECT :taller_1, t.id, mo.id, x.anio, x.motor, x.vin, x.patente
FROM  (VALUES
  ('Hyundai', 'Tucson', 2020, '2.0 Bencina', 'KM8J3CA46LU123456', 'JKLP43'),
  ('Suzuki',  'Swift',  2017, '1.2 Bencina', NULL,                'YZBC90')
) AS x (marca, modelo, anio, motor, vin, patente)
JOIN marca_vehiculo  ma ON ma.nombre = x.marca
JOIN modelo_vehiculo mo ON mo.marca_vehiculo_id = ma.id AND mo.nombre = x.modelo
JOIN titular         t  ON t.nombre = 'Sofía Castro Vera';

SELECT set_config('semilla.atenciones', $json$[
  {"patente": "JKLP43", "mac": "00:1D:A5:68:98:8A", "km": 38900, "hace": "60 days", "final": "completado",
   "fallas": [{"codigo": "P0302"}],
   "revisiones": [[{"repuesto": "18846-10060", "cantidad": 4}]]},

  {"patente": "YZBC90", "km": 97400, "hace": "28 days", "final": "cancelado",
   "fallas": [{"codigo": "P0101"}, {"codigo": "P0171"}],
   "revisiones": [[{"repuesto": "0280218190", "cantidad": 1}, {"repuesto": "C 27 009", "cantidad": 1}]]},

  {"patente": "JKLP43", "mac": "00:1D:A5:68:98:8A", "km": 44150, "hace": "9 days", "final": "cotizado",
   "fallas": [{"codigo": "P0135"}],
   "revisiones": [[{"repuesto": "39210-2B310", "cantidad": 1}]]},

  {"patente": "YZBC90", "km": 99020, "hace": "1 day", "final": "pendiente",
   "fallas": [{"codigo": "P0301", "severidad": "critica"}]}
]$json$, true);

\ir incluir/flujo_atencion.sql

COMMIT;

-- ============================================================================
-- Taller 2 - mecanica (Valentina Muñoz). Margen 45,5 %.
-- La patente BCDF12 se repite respecto del taller 1: la unicidad es por taller.
-- ============================================================================
BEGIN;
SET LOCAL ROLE taller_mecanico;
SELECT set_config('app.taller_id',  :'taller_2',   true),
       set_config('app.usuario_id', :'mecanico_2', true),
       set_config('app.ip_origen',  '10.20.0.5',   true),
       set_config('app.request_id', 'semilla-03-mecanico-2', true);

INSERT INTO titular (taller_id, nombre, telefono, email, identificador_hmac) VALUES
  (:taller_2, 'Pedro Aguilar Ríos', '+56966666666', NULL,                          hmac('ID-DEMO-101', :'clave_demo', 'sha256')),
  (:taller_2, 'Camila Ortiz Lagos', '+56977777777', 'camila.ortiz@correo.example', hmac('ID-DEMO-102', :'clave_demo', 'sha256'));

INSERT INTO consentimiento_titular (taller_id, titular_id, finalidad, version_terminos, canal, otorgado_en)
SELECT :taller_2, t.id, 'prestacion_servicio', 'v1.0', 'presencial', now() - interval '45 days'
FROM   titular t;

INSERT INTO vehiculo (taller_id, titular_id, modelo_vehiculo_id, anio, motor, vin, patente)
SELECT :taller_2, t.id, mo.id, x.anio, x.motor, x.vin, x.patente
FROM  (VALUES
  ('Pedro Aguilar Ríos', 'Toyota',    'Hilux', 2019, '2.8 Diésel',  '8AJHA3CD2K2123456', 'BCDF12'),
  ('Camila Ortiz Lagos', 'Chevrolet', 'Spark', 2014, '1.2 Bencina', NULL,                'HJKL65'),
  ('Camila Ortiz Lagos', 'Nissan',    'Versa', 2022, '1.6 Bencina', '3N1CN8AE5NL123456', 'PRST09')
) AS x (titular, marca, modelo, anio, motor, vin, patente)
JOIN marca_vehiculo  ma ON ma.nombre = x.marca
JOIN modelo_vehiculo mo ON mo.marca_vehiculo_id = ma.id AND mo.nombre = x.modelo
JOIN titular         t  ON t.nombre = x.titular;

SELECT set_config('semilla.atenciones', $json$[
  {"patente": "BCDF12", "mac": "00:04:3E:9A:11:22", "km": 128400, "hace": "45 days", "final": "completado",
   "fallas": [{"codigo": "P0401"}, {"codigo": "P0101"}],
   "revisiones": [[{"repuesto": "7.24809.17.0", "cantidad": 1}, {"repuesto": "22204-0C020", "cantidad": 1}]]},

  {"patente": "HJKL65", "km": 156200, "hace": "15 days", "final": "cotizado",
   "fallas": [{"codigo": "C0035"}],
   "revisiones": [[{"repuesto": "95996129", "cantidad": 2}]]},

  {"patente": "PRST09", "mac": "00:04:3E:9A:11:22", "km": 31800, "hace": "4 days", "final": "pendiente",
   "fallas": [{"codigo": "P0420"}],
   "borrador": [{"repuesto": "16468", "cantidad": 1}]},

  {"patente": "HJKL65", "km": 157050, "hace": "5 hours", "final": "pendiente",
   "fallas": [{"codigo": "P0300", "severidad": "critica"}]}
]$json$, true);

\ir incluir/flujo_atencion.sql

COMMIT;

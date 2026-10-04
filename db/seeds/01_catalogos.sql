-- =============================================================================
-- Semilla 01 - Catalogos globales (plataforma).
-- Datos FICTICIOS de demostracion: los codigos de fabricante y los precios son
-- verosimiles, no una lista de precios real.
-- Se carga como superusuario: los catalogos no tienen RLS y ningun rol de
-- taller puede escribirlos.
-- Las filas se enlazan por clave natural (nombre, codigo), no por id.
-- =============================================================================
\encoding UTF8
\o /dev/null

BEGIN;

-- ----------------------------------------------------------------------------
-- Marcas y modelos
-- ----------------------------------------------------------------------------
INSERT INTO marca_vehiculo (nombre) VALUES
  ('Toyota'), ('Hyundai'), ('Chevrolet'), ('Kia'), ('Suzuki'), ('Nissan');

INSERT INTO modelo_vehiculo (marca_vehiculo_id, nombre)
SELECT m.id, x.modelo
FROM  (VALUES
  ('Toyota',    'Hilux'),
  ('Toyota',    'Yaris'),
  ('Toyota',    'Corolla'),
  ('Hyundai',   'Accent'),
  ('Hyundai',   'Tucson'),
  ('Chevrolet', 'Sail'),
  ('Chevrolet', 'Spark'),
  ('Kia',       'Morning'),
  ('Kia',       'Rio'),
  ('Suzuki',    'Swift'),
  ('Nissan',    'Versa')
) AS x (marca, modelo)
JOIN marca_vehiculo m ON m.nombre = x.marca;

-- ----------------------------------------------------------------------------
-- Codigos de falla OBD-II
-- U0100 queda deliberadamente SIN componente asociado: un DTC que no se
-- resuelve con un repuesto produce una matriz vacia, no un error.
-- ----------------------------------------------------------------------------
INSERT INTO dtc_catalogo (codigo, descripcion, severidad_sugerida) VALUES
  ('P0101', 'Rango o rendimiento del sensor de flujo de aire (MAF)',              'media'),
  ('P0135', 'Circuito del calefactor del sensor de oxígeno (banco 1, sensor 1)', 'media'),
  ('P0171', 'Mezcla demasiado pobre (banco 1)',                                   'media'),
  ('P0201', 'Circuito del inyector abierto, cilindro 1',                          'alta'),
  ('P0300', 'Fallas de encendido aleatorias o en varios cilindros',               'alta'),
  ('P0301', 'Falla de encendido en el cilindro 1',                                'alta'),
  ('P0302', 'Falla de encendido en el cilindro 2',                                'alta'),
  ('P0335', 'Circuito del sensor de posición del cigüeñal',                       'critica'),
  ('P0401', 'Flujo insuficiente de recirculación de gases de escape (EGR)',       'baja'),
  ('P0420', 'Eficiencia del catalizador bajo el umbral (banco 1)',                'media'),
  ('C0035', 'Circuito del sensor de velocidad de la rueda delantera izquierda',   'alta'),
  ('U0100', 'Pérdida de comunicación con el módulo de control del motor (ECM)',   'critica');

-- ----------------------------------------------------------------------------
-- Componentes
-- ----------------------------------------------------------------------------
INSERT INTO componente_repuesto (nombre, descripcion) VALUES
  ('Bujía',                           'Genera la chispa que enciende la mezcla en el cilindro.'),
  ('Bobina de encendido',             'Eleva el voltaje de la batería para alimentar la bujía.'),
  ('Sensor de oxígeno',               'Mide el oxígeno en los gases de escape para ajustar la mezcla.'),
  ('Catalizador',                     'Reduce las emisiones contaminantes de los gases de escape.'),
  ('Sensor de flujo de aire (MAF)',   'Mide la masa de aire que entra al motor.'),
  ('Sensor de posición del cigüeñal', 'Informa la posición y velocidad de giro del cigüeñal.'),
  ('Válvula EGR',                     'Recircula parte de los gases de escape hacia la admisión.'),
  ('Inyector de combustible',         'Dosifica y pulveriza el combustible en la admisión o el cilindro.'),
  ('Sensor de velocidad de rueda',    'Informa la velocidad de cada rueda al sistema ABS.'),
  ('Filtro de aire',                  'Retiene partículas del aire de admisión.');

-- ----------------------------------------------------------------------------
-- DTC <-> componente (N:M)
-- ----------------------------------------------------------------------------
INSERT INTO dtc_componente (dtc_id, componente_id)
SELECT d.id, c.id
FROM  (VALUES
  ('P0300', 'Bujía'), ('P0300', 'Bobina de encendido'), ('P0300', 'Inyector de combustible'),
  ('P0301', 'Bujía'), ('P0301', 'Bobina de encendido'), ('P0301', 'Inyector de combustible'),
  ('P0302', 'Bujía'), ('P0302', 'Bobina de encendido'),
  ('P0171', 'Sensor de flujo de aire (MAF)'), ('P0171', 'Sensor de oxígeno'),
  ('P0171', 'Filtro de aire'),                ('P0171', 'Inyector de combustible'),
  ('P0420', 'Catalizador'), ('P0420', 'Sensor de oxígeno'),
  ('P0135', 'Sensor de oxígeno'),
  ('P0101', 'Sensor de flujo de aire (MAF)'), ('P0101', 'Filtro de aire'),
  ('P0335', 'Sensor de posición del cigüeñal'),
  ('P0401', 'Válvula EGR'),
  ('P0201', 'Inyector de combustible'),
  ('C0035', 'Sensor de velocidad de rueda')
) AS x (codigo, componente)
JOIN dtc_catalogo        d ON d.codigo = x.codigo
JOIN componente_repuesto c ON c.nombre = x.componente;

-- ----------------------------------------------------------------------------
-- Repuestos: cada componente tiene alternativas en los tres perfiles.
-- precio_referencia en pesos (unidad minima de CLP).
-- ----------------------------------------------------------------------------
INSERT INTO repuesto (componente_id, perfil, marca, nombre, codigo_fabricante,
                      durabilidad_estimada_km, riesgo, precio_referencia, disponible)
SELECT c.id, x.perfil::tipo_perfil_repuesto, x.marca, x.nombre, x.codigo,
       x.km, x.riesgo::tipo_nivel_riesgo, x.precio, x.disponible
FROM  (VALUES
  -- componente, perfil, marca, nombre, codigo, km, riesgo, precio, disponible
  ('Bujía', 'genuino',  'Toyota',    'Bujía de iridio Toyota',            '90919-01253',  100000, 'bajo',   12990, true),
  ('Bujía', 'genuino',  'Hyundai',   'Bujía de iridio Hyundai',           '18846-10060',  100000, 'bajo',   11990, true),
  ('Bujía', 'genuino',  'Chevrolet', 'Bujía de platino Chevrolet',        '55570064',      80000, 'bajo',   10990, true),
  ('Bujía', 'oem',      'NGK',       'Bujía de iridio NGK Laser',         'ILKAR7B11',     90000, 'bajo',    8990, true),
  ('Bujía', 'oem',      'Denso',     'Bujía de iridio Denso',             'SC20HR11',      90000, 'bajo',    9490, true),
  ('Bujía', 'generico', 'Autolab',   'Bujía de cobre',                    'GEN-BUJ-01',    30000, 'medio',   3490, true),

  ('Bobina de encendido', 'genuino',  'Toyota',  'Bobina de encendido Toyota',   '90919-02258', 150000, 'bajo', 62990, true),
  ('Bobina de encendido', 'genuino',  'Hyundai', 'Bobina de encendido Hyundai',  '27301-2B010', 150000, 'bajo', 54990, true),
  ('Bobina de encendido', 'oem',      'Denso',   'Bobina de encendido Denso',    '673-1307',    120000, 'bajo', 38990, true),
  ('Bobina de encendido', 'generico', 'Autolab', 'Bobina de encendido genérica', 'GEN-BOB-01',   50000, 'alto', 17990, true),

  ('Sensor de oxígeno', 'genuino',  'Toyota',  'Sensor de oxígeno Toyota',      '89465-0K240', 160000, 'bajo',  119990, true),
  ('Sensor de oxígeno', 'genuino',  'Hyundai', 'Sensor de oxígeno Hyundai',     '39210-2B310', 150000, 'bajo',   99990, true),
  ('Sensor de oxígeno', 'oem',      'Bosch',   'Sonda lambda Bosch',            '0258006537',  130000, 'bajo',   64990, true),
  ('Sensor de oxígeno', 'oem',      'Denso',   'Sensor de oxígeno Denso',       '234-4622',    130000, 'bajo',   67990, true),
  ('Sensor de oxígeno', 'generico', 'Autolab', 'Sensor de oxígeno universal',   'GEN-O2-01',    60000, 'medio',  27990, true),

  ('Catalizador', 'genuino',  'Toyota',  'Catalizador Toyota',           '25051-0C011', 200000, 'bajo',  689990, true),
  ('Catalizador', 'oem',      'Walker',  'Catalizador Walker',           '16468',       160000, 'medio', 349990, true),
  ('Catalizador', 'generico', 'Autolab', 'Catalizador universal',        'GEN-CAT-01',   80000, 'alto',  149990, true),

  ('Sensor de flujo de aire (MAF)', 'genuino',  'Toyota',    'Sensor MAF Toyota',     '22204-0C020', 180000, 'bajo', 139990, true),
  ('Sensor de flujo de aire (MAF)', 'genuino',  'Chevrolet', 'Sensor MAF Chevrolet',  '13301682',    160000, 'bajo', 109990, true),
  ('Sensor de flujo de aire (MAF)', 'oem',      'Bosch',     'Sensor MAF Bosch',      '0280218190',  150000, 'bajo',  74990, true),
  ('Sensor de flujo de aire (MAF)', 'generico', 'Autolab',   'Sensor MAF genérico',   'GEN-MAF-01',   60000, 'alto',  29990, true),

  ('Sensor de posición del cigüeñal', 'genuino',  'Toyota',  'Sensor de cigüeñal Toyota',   '90919-05057', 200000, 'bajo', 58990, true),
  ('Sensor de posición del cigüeñal', 'genuino',  'Hyundai', 'Sensor de cigüeñal Hyundai',  '39180-2B000', 200000, 'bajo', 45990, true),
  ('Sensor de posición del cigüeñal', 'oem',      'Bosch',   'Sensor de cigüeñal Bosch',    '0261210170',  160000, 'bajo', 32990, true),
  ('Sensor de posición del cigüeñal', 'generico', 'Autolab', 'Sensor de cigüeñal genérico', 'GEN-CKP-01',   70000, 'alto', 12990, true),

  ('Válvula EGR', 'genuino',  'Toyota',   'Válvula EGR Toyota',    '25620-30090',  180000, 'bajo',  289990, true),
  ('Válvula EGR', 'oem',      'Pierburg', 'Válvula EGR Pierburg',  '7.24809.17.0', 150000, 'medio', 159990, true),
  ('Válvula EGR', 'generico', 'Autolab',  'Válvula EGR genérica',  'GEN-EGR-01',    60000, 'alto',   69990, true),

  ('Inyector de combustible', 'genuino',  'Toyota',  'Inyector Toyota',                '23250-0C010', 200000, 'bajo', 94990, true),
  ('Inyector de combustible', 'genuino',  'Hyundai', 'Inyector Hyundai',               '35310-2B010', 200000, 'bajo', 79990, true),
  ('Inyector de combustible', 'oem',      'Bosch',   'Inyector Bosch',                 '0280158117',  160000, 'bajo', 49990, true),
  ('Inyector de combustible', 'generico', 'Autolab', 'Inyector genérico',              'GEN-INY-01',   70000, 'alto', 22990, true),
  -- Descontinuado: no aparece en la matriz ni se puede cotizar (RE010).
  ('Inyector de combustible', 'generico', 'Autolab', 'Inyector genérico (serie antigua)', 'GEN-INY-02', 50000, 'alto', 19990, false),

  ('Sensor de velocidad de rueda', 'genuino',  'Toyota',    'Sensor ABS Toyota',     '89543-0K020', 180000, 'bajo',  84990, true),
  ('Sensor de velocidad de rueda', 'genuino',  'Chevrolet', 'Sensor ABS Chevrolet',  '95996129',    150000, 'bajo',  59990, true),
  ('Sensor de velocidad de rueda', 'oem',      'Bosch',     'Sensor ABS Bosch',      '0265007905',  150000, 'bajo',  44990, true),
  ('Sensor de velocidad de rueda', 'generico', 'Autolab',   'Sensor ABS genérico',   'GEN-ABS-01',   60000, 'medio', 18990, true),

  ('Filtro de aire', 'genuino',  'Toyota',  'Filtro de aire Toyota',    '17801-0C010', 20000, 'bajo',  24990, true),
  ('Filtro de aire', 'genuino',  'Hyundai', 'Filtro de aire Hyundai',   '28113-1R100', 20000, 'bajo',  18990, true),
  ('Filtro de aire', 'oem',      'Mann',    'Filtro de aire Mann',      'C 27 009',    20000, 'bajo',  14990, true),
  ('Filtro de aire', 'generico', 'Autolab', 'Filtro de aire genérico',  'GEN-FIL-01',  10000, 'medio',  6990, true)
) AS x (componente, perfil, marca, nombre, codigo, km, riesgo, precio, disponible)
JOIN componente_repuesto c ON c.nombre = x.componente;

-- ----------------------------------------------------------------------------
-- Compatibilidad repuesto <-> modelo (rango de anios)
--   * genuino : solo los modelos de la marca del repuesto, 2010-2026.
--   * oem     : todos los modelos, 2008-2026.
--   * generico: todos los modelos, 1996-2026.
-- Excepcion: el catalizador Walker se carga a mano, con dos rangos DISJUNTOS
-- para la Hilux (2005-2015 y 2018-2024): una Hilux 2016 o 2017 no lo ve.
-- ----------------------------------------------------------------------------
INSERT INTO compatibilidad_repuesto (repuesto_id, modelo_vehiculo_id, anio_desde, anio_hasta)
SELECT r.id, mo.id, 2010, 2026
FROM   repuesto r
JOIN   marca_vehiculo  ma ON ma.nombre = r.marca
JOIN   modelo_vehiculo mo ON mo.marca_vehiculo_id = ma.id
WHERE  r.perfil = 'genuino';

INSERT INTO compatibilidad_repuesto (repuesto_id, modelo_vehiculo_id, anio_desde, anio_hasta)
SELECT r.id, mo.id, 2008, 2026
FROM   repuesto r
CROSS  JOIN modelo_vehiculo mo
WHERE  r.perfil = 'oem'
AND    r.codigo_fabricante <> '16468';

INSERT INTO compatibilidad_repuesto (repuesto_id, modelo_vehiculo_id, anio_desde, anio_hasta)
SELECT r.id, mo.id, 1996, 2026
FROM   repuesto r
CROSS  JOIN modelo_vehiculo mo
WHERE  r.perfil = 'generico';

INSERT INTO compatibilidad_repuesto (repuesto_id, modelo_vehiculo_id, anio_desde, anio_hasta)
SELECT r.id, mo.id, x.desde, x.hasta
FROM  (VALUES
  ('Toyota',    'Hilux',   2005, 2015),
  ('Toyota',    'Hilux',   2018, 2024),
  ('Toyota',    'Yaris',   2008, 2020),
  ('Toyota',    'Corolla', 2008, 2020),
  ('Hyundai',   'Accent',  2011, 2020),
  ('Chevrolet', 'Sail',    2010, 2020),
  ('Nissan',    'Versa',   2012, 2026)
) AS x (marca, modelo, desde, hasta)
JOIN marca_vehiculo  ma ON ma.nombre = x.marca
JOIN modelo_vehiculo mo ON mo.marca_vehiculo_id = ma.id AND mo.nombre = x.modelo
JOIN repuesto        r  ON r.codigo_fabricante = '16468';

COMMIT;

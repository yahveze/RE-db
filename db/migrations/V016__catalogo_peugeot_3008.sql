-- Catálogo mínimo para registrar el vehículo de aceptación: Peugeot 3008 2017.
-- No crea vehículos, VIN, fallas ni compatibilidades de repuestos ficticias.
INSERT INTO marca_vehiculo(nombre) VALUES ('Peugeot')
  ON CONFLICT (nombre) DO NOTHING;
INSERT INTO modelo_vehiculo(marca_vehiculo_id,nombre)
  SELECT id,'3008' FROM marca_vehiculo WHERE nombre='Peugeot'
  ON CONFLICT (marca_vehiculo_id,nombre) DO NOTHING;

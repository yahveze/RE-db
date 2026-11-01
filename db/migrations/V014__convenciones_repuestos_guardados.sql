-- V014: alinear referencias guardadas con las invariantes del esquema.
-- V013 ya puede estar aplicada: se conserva y se corrige de forma incremental.
ALTER TABLE repuesto_guardado RENAME CONSTRAINT repuesto_guardado_pkey TO pk_repuesto_guardado;
ALTER TABLE repuesto_guardado RENAME CONSTRAINT repuesto_guardado_id_publico_key TO uq_repuesto_guardado_id_publico;
ALTER TABLE repuesto_guardado RENAME CONSTRAINT repuesto_guardado_proveedor_check TO ck_repuesto_guardado_proveedor;
ALTER TABLE repuesto_guardado RENAME CONSTRAINT repuesto_guardado_id_externo_check TO ck_repuesto_guardado_id_externo;
ALTER TABLE repuesto_guardado RENAME CONSTRAINT repuesto_guardado_tipo_referencia_check TO ck_repuesto_guardado_tipo_referencia;
ALTER TABLE repuesto_guardado RENAME CONSTRAINT repuesto_guardado_enlace_check TO ck_repuesto_guardado_enlace;
ALTER TABLE repuesto_guardado RENAME CONSTRAINT repuesto_guardado_nota_check TO ck_repuesto_guardado_nota;
ALTER TABLE repuesto_guardado RENAME CONSTRAINT repuesto_guardado_hash_solicitud_check TO ck_repuesto_guardado_hash_solicitud;

-- RESTRICT explícito, como en el resto del modelo; no se borran referencias en cascada.
ALTER TABLE repuesto_guardado
  DROP CONSTRAINT repuesto_guardado_taller_id_fkey,
  DROP CONSTRAINT repuesto_guardado_modelo_vehiculo_id_fkey,
  DROP CONSTRAINT fk_guardado_usuario,
  DROP CONSTRAINT fk_guardado_dtc_componente,
  DROP CONSTRAINT fk_guardado_vehiculo,
  DROP CONSTRAINT fk_guardado_sesion,
  ADD CONSTRAINT fk_repuesto_guardado_taller FOREIGN KEY(taller_id) REFERENCES taller(id) ON DELETE RESTRICT,
  ADD CONSTRAINT fk_repuesto_guardado_modelo FOREIGN KEY(modelo_vehiculo_id) REFERENCES modelo_vehiculo(id) ON DELETE RESTRICT,
  ADD CONSTRAINT fk_repuesto_guardado_usuario FOREIGN KEY(usuario_id,taller_id) REFERENCES usuario(id,taller_id) ON DELETE RESTRICT,
  ADD CONSTRAINT fk_repuesto_guardado_dtc_componente FOREIGN KEY(dtc_id,componente_id) REFERENCES dtc_componente(dtc_id,componente_id) ON DELETE RESTRICT,
  ADD CONSTRAINT fk_repuesto_guardado_vehiculo FOREIGN KEY(vehiculo_id,taller_id) REFERENCES vehiculo(id,taller_id) ON DELETE RESTRICT,
  ADD CONSTRAINT fk_repuesto_guardado_sesion FOREIGN KEY(sesion_id,taller_id) REFERENCES sesion_diagnostico(id,taller_id) ON DELETE RESTRICT;

ALTER POLICY pol_guardado_select ON repuesto_guardado RENAME TO pol_repuesto_guardado_miembros_select;
ALTER POLICY pol_guardado_insert ON repuesto_guardado RENAME TO pol_repuesto_guardado_miembros_insert;

COMMENT ON COLUMN repuesto_guardado.id IS 'Identificador interno generado por PostgreSQL.';
COMMENT ON COLUMN repuesto_guardado.id_publico IS 'UUID público de la alternativa guardada.';
COMMENT ON COLUMN repuesto_guardado.taller_id IS 'Taller al que pertenece la decisión; sujeto a RLS.';
COMMENT ON COLUMN repuesto_guardado.usuario_id IS 'Autor de la selección, perteneciente al mismo taller.';
COMMENT ON COLUMN repuesto_guardado.dtc_id IS 'Falla que motivó la búsqueda; no implica diagnóstico confirmado.';
COMMENT ON COLUMN repuesto_guardado.componente_id IS 'Componente candidato asociado a la falla.';
COMMENT ON COLUMN repuesto_guardado.modelo_vehiculo_id IS 'Modelo utilizado en la búsqueda, si fue seleccionado.';
COMMENT ON COLUMN repuesto_guardado.anio IS 'Año utilizado como contexto; no certifica compatibilidad.';
COMMENT ON COLUMN repuesto_guardado.vehiculo_id IS 'Vehículo opcional del mismo taller.';
COMMENT ON COLUMN repuesto_guardado.sesion_id IS 'Sesión de diagnóstico opcional del mismo taller y vehículo.';
COMMENT ON COLUMN repuesto_guardado.proveedor IS 'Proveedor externo de la referencia.';
COMMENT ON COLUMN repuesto_guardado.id_externo IS 'Identificador del proveedor; permite volver a consultar la referencia.';
COMMENT ON COLUMN repuesto_guardado.tipo_referencia IS 'Publicación comercial o referencia técnica de catálogo.';
COMMENT ON COLUMN repuesto_guardado.enlace IS 'Enlace HTTPS de la publicación; nulo para referencias de catálogo.';
COMMENT ON COLUMN repuesto_guardado.nota IS 'Nota del técnico; excluida de la captura de auditoría.';
COMMENT ON COLUMN repuesto_guardado.clave_idempotencia IS 'Clave del cliente para evitar duplicados al reintentar.';
COMMENT ON COLUMN repuesto_guardado.hash_solicitud IS 'Huella de la solicitud que impide reutilizar una clave con otro contenido.';
COMMENT ON COLUMN repuesto_guardado.creado_en IS 'Instante de guardado en UTC, generado por la base de datos.';

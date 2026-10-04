-- =============================================================================
-- V006 - Indices de rendimiento.
--
-- Ya existen (no se repiten aqui): los indices de PRIMARY KEY y UNIQUE, y los
-- unicos parciales de V003 (reglas de integridad).
--
-- Criterios:
--   * PostgreSQL NO indexa automaticamente las columnas de una FK.
--   * En tablas con RLS toda consulta lleva el filtro taller_id = <contexto>,
--     por eso los indices de tablas operativas EMPIEZAN por taller_id.
--   * Cada indice declara la consulta que optimiza y su costo. Los que la
--     Fase 5 demuestre que no se usan se eliminan o se justifican
--     (docs/evidencia/rendimiento.md).
--
-- FK deliberadamente SIN indice propio (el padre nunca se borra y no hay
-- consulta por esa columna): sesion_diagnostico.usuario_id y .dispositivo_id,
-- solicitud_derecho_titular.usuario_responsable_id,
-- cotizacion_detalle.repuesto_id, vehiculo.modelo_vehiculo_id (cubierta
-- parcialmente por ix_vehiculo_taller_modelo_anio).
-- FK ya cubiertas por un indice existente cuyo prefijo es la columna:
-- modelo_vehiculo.marca_vehiculo_id, repuesto.componente_id,
-- compatibilidad_repuesto.repuesto_id, dtc_componente.dtc_id,
-- falla_sesion.sesion_id, cotizacion.sesion_id, cotizacion_detalle.cotizacion_id,
-- dispositivo_diagnostico.taller_id.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Catalogos
-- ----------------------------------------------------------------------------

-- Sentido inverso de la N:M: "que DTC apuntan a este componente" y FK hacia
-- componente_repuesto. La PK (dtc_id, componente_id) solo sirve por dtc_id.
-- Costo: minimo, catalogo pequeno y casi estatico.
CREATE INDEX ix_dtc_componente_componente
  ON dtc_componente (componente_id);

-- FK hacia modelo_vehiculo y consulta "que repuestos sirven para este modelo".
-- La PK empieza por repuesto_id y no sirve para buscar por modelo.
CREATE INDEX ix_compatibilidad_repuesto_modelo
  ON compatibilidad_repuesto (modelo_vehiculo_id);

-- ----------------------------------------------------------------------------
-- Multi-taller y privacidad
-- ----------------------------------------------------------------------------

-- Listado de usuarios del taller (RLS) y FK hacia taller.
CREATE INDEX ix_usuario_taller
  ON usuario (taller_id);

-- Listado de titulares del taller (RLS) y FK hacia taller.
CREATE INDEX ix_titular_taller
  ON titular (taller_id);

-- fn_anonimizar_vencidos: bloqueos vencidos. Parcial: solo indexa las pocas
-- filas en estado 'bloqueado'.
CREATE INDEX ix_titular_bloqueado_hasta
  ON titular (bloqueado_hasta)
  WHERE estado_tratamiento = 'bloqueado';

-- Consentimientos de un titular y FK compuesta (titular_id, taller_id).
CREATE INDEX ix_consentimiento_titular_taller_titular
  ON consentimiento_titular (taller_id, titular_id);

-- Solicitudes de un titular y FK compuesta (titular_id, taller_id).
CREATE INDEX ix_solicitud_derecho_titular_taller_titular
  ON solicitud_derecho_titular (taller_id, titular_id);

-- ----------------------------------------------------------------------------
-- Operacion
-- ----------------------------------------------------------------------------

-- /search por marca + modelo + anio. Orden: taller_id (RLS, igualdad),
-- modelo (igualdad), anio (igualdad o rango).
-- /search por VIN usa uq_vehiculo_taller_vin (V003).
CREATE INDEX ix_vehiculo_taller_modelo_anio
  ON vehiculo (taller_id, modelo_vehiculo_id, anio);

-- Vehiculos de un titular (anonimizacion, politica RLS del mecanico) y FK
-- compuesta hacia titular. Parcial: los vehiculos sin titular no se indexan.
CREATE INDEX ix_vehiculo_taller_titular
  ON vehiculo (taller_id, titular_id)
  WHERE titular_id IS NOT NULL;

-- /history sin filtro de estado, con keyset pagination (iniciada_en, id).
-- El orden del indice coincide con el ORDER BY: el plan lee en orden y corta
-- en el LIMIT, sin ordenar.
CREATE INDEX ix_sesion_diagnostico_historial
  ON sesion_diagnostico (taller_id, iniciada_en DESC, id DESC);

-- /history filtrado por estado y conteos del dashboard.
CREATE INDEX ix_sesion_diagnostico_estado
  ON sesion_diagnostico (taller_id, estado, iniciada_en DESC, id DESC);

-- Cola de trabajo: sesiones pendientes. Parcial: 'pendiente' es una fraccion
-- pequena del total y la que mas se consulta. Candidato a eliminar si la
-- Fase 5 muestra que ix_sesion_diagnostico_estado lo hace redundante.
CREATE INDEX ix_sesion_diagnostico_pendiente
  ON sesion_diagnostico (taller_id, iniciada_en DESC, id DESC)
  WHERE estado = 'pendiente';

-- Historial de un vehiculo, calculo de retencion (ultima atencion del
-- titular) y FK compuesta hacia vehiculo.
CREATE INDEX ix_sesion_diagnostico_vehiculo
  ON sesion_diagnostico (taller_id, vehiculo_id, iniciada_en DESC);

-- Sentido inverso de la N:M: "en que sesiones aparecio este DTC" y FK hacia
-- dtc_catalogo. La PK (sesion_id, dtc_id) solo sirve por sesion_id.
CREATE INDEX ix_falla_sesion_dtc
  ON falla_sesion (dtc_id);

-- Dashboard: fallas criticas. Parcial sobre la severidad que se cuenta.
CREATE INDEX ix_falla_sesion_critica
  ON falla_sesion (taller_id, sesion_id)
  WHERE severidad = 'critica';

-- ----------------------------------------------------------------------------
-- Auditoria
-- ----------------------------------------------------------------------------

-- Lectura de la bitacora del taller, mas reciente primero. Costo: se
-- actualiza en cada operacion auditada (es el indice mas "caro" del esquema).
CREATE INDEX ix_auditoria_operacion_taller_fecha
  ON auditoria_operacion (taller_id, ocurrido_en DESC, id DESC);

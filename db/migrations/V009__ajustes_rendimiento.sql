-- =============================================================================
-- V009 - Ajustes de indices tras medir con volumen (Fase 5).
-- Mediciones y planes: docs/evidencia/rendimiento.md y fase5_*.txt.
--
-- Hallazgo que motiva el cambio. Con RLS, PostgreSQL solo usa como condicion de
-- busqueda de un indice las comparaciones cuyo operador es LEAKPROOF (no puede
-- filtrar informacion por un mensaje de error antes de que se aplique la
-- politica). La igualdad de los tipos enumerados (enum_eq) NO lo es. Por eso,
-- para los roles de taller, "estado = 'cotizado'" nunca entra como Index Cond:
-- el indice (taller_id, estado, iniciada_en, id) se recorre entero para el
-- taller y el estado se aplica como filtro fila por fila. En el taller de
-- 150.000 sesiones de la medicion eso es descartar unas 149.000 filas para
-- encontrar 822 (experimento E0 de fase5_indices.txt).
--
-- Un indice PARCIAL no tiene ese problema: que la consulta implica el predicado
-- (estado = 'cotizado') se demuestra al planificar, no se evalua por fila.
-- =============================================================================

-- La columna estado de este indice no sirve como clave de busqueda bajo RLS y,
-- como indice por (taller_id, iniciada_en), duplica a
-- ix_sesion_diagnostico_historial.
DROP INDEX ix_sesion_diagnostico_estado;

-- Cola de sesiones cotizadas (esperan la decision del cliente): /history
-- filtrado por 'cotizado' y montos del dashboard. Parcial, igual que
-- ix_sesion_diagnostico_pendiente: los estados abiertos son una fraccion
-- pequena de la tabla y los que mas se consultan. Costo de escritura: solo las
-- filas que estan en ese estado.
CREATE INDEX ix_sesion_diagnostico_cotizado
  ON sesion_diagnostico (taller_id, iniciada_en DESC, id DESC)
  WHERE estado = 'cotizado';

-- /history filtrado por 'completado' o 'cancelado' usa
-- ix_sesion_diagnostico_historial con el estado como filtro: son los estados
-- mayoritarios (casi todas las filas recorridas califican), asi que un indice
-- propio no ahorraria lecturas.

-- ----------------------------------------------------------------------------
-- Indices de V006 que la medicion no justifico (fase5_indices.txt).
-- ----------------------------------------------------------------------------

-- E6: con unos 3.000 talleres y 30.000 usuarios, listar los usuarios de un
-- taller sigue por debajo del milisegundo sin este indice (el planificador
-- recurre a uq_usuario_id_taller). La tabla es pequena por naturaleza.
DROP INDEX ix_usuario_taller;

-- E7: con unas 37.000 solicitudes, la lista de un taller tarda lo mismo con el
-- indice que sin el; las funciones de supresion buscan por titular_id, que este
-- indice (encabezado por taller_id) no cubre. La tabla registra eventos poco
-- frecuentes.
DROP INDEX ix_solicitud_derecho_titular_taller_titular;

-- Se conservan porque el experimento mostro una diferencia de uno o dos ordenes
-- de magnitud con y sin el indice (E1 a E5): ix_falla_sesion_dtc e
-- ix_compatibilidad_repuesto_modelo (comprobacion de la FK al borrar del
-- catalogo), ix_vehiculo_taller_titular (supresion), ix_titular_bloqueado_hasta
-- (proceso de vencidos) e ix_consentimiento_titular_taller_titular
-- (q_consentimientos_titular).

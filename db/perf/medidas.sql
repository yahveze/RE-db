-- =============================================================================
-- Sentencias medidas. Lo incluye medir.sql DOS veces dentro de la misma
-- transaccion: la primera para calentar la cache (salida descartada y cambios
-- revertidos con un SAVEPOINT) y la segunda para medir.
-- Cada medida es EXPLAIN (ANALYZE, BUFFERS) de la sentencia PREPARADA real del
-- backend, con el rol y el contexto de un usuario del taller grande.
-- =============================================================================

-- ------------------------------------------------------------------ mecanico
RESET ROLE;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx(:'tv', :'u_mec', '10.0.0.9', 'perf') \gset ctx_

\qecho
\qecho '## M01 q_historial - primera pagina (21 filas, sin filtro)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_historial(21);

\qecho
\qecho '## M02 q_historial - pagina profunda por clave (cursor tras 75.000 sesiones)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_historial_siguiente(:'cur_ts', :'cur_id', 21);

\qecho
\qecho '## M03 comparacion: la misma pagina profunda con OFFSET 75000 (lo que la paginacion por clave evita)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.id_publico, s.estado, s.iniciada_en
FROM   sesion_diagnostico s
ORDER  BY s.iniciada_en DESC, s.id DESC
OFFSET 75000 LIMIT 21;

\qecho
\qecho '## M04 q_historial - filtrado por estado pendiente, primera pagina'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_historial_estado('pendiente', 21);

\qecho
\qecho '## M05 q_historial - filtrado por estado completado, pagina profunda'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_historial_estado_siguiente('completado', :'cur_ts', :'cur_id', 21);

\qecho
\qecho '## M06 q_historial_siguiente - la misma pagina profunda con PLAN GENERICO forzado'
SET LOCAL plan_cache_mode = force_generic_plan;
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_historial_siguiente(:'cur_ts', :'cur_id', 21);

\qecho
\qecho '## M06a ANTES: formulacion con cursor opcional (Fase 3), misma pagina, plan generico'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE perf_historial_opcional(NULL, :'cur_ts', :'cur_id', 21);
SET LOCAL plan_cache_mode = auto;

\qecho
\qecho '## M07 q_buscar_vehiculo_patente'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_buscar_vehiculo_patente(:'patente');

\qecho
\qecho '## M08 q_buscar_vehiculo_vin'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_buscar_vehiculo_vin(:'vin');

\qecho
\qecho '## M09 q_buscar_vehiculo_modelo (modelo + anio, 20 filas)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_buscar_vehiculo_modelo(:'modelo', :anio, 20);

\qecho
\qecho '## M10 q_sesion'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_sesion(:'ses_pend');

\qecho
\qecho '## M11 q_sesion_fallas'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_sesion_fallas(:'ses_pend');

\qecho
\qecho '## M12 q_matriz'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_matriz(:'ses_pend');

\qecho
\qecho '## M13 q_repuestos_por_dtc (con modelo y anio)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_repuestos_por_dtc(:'dtc', :'modelo', :anio);

\qecho
\qecho '## M14 q_cotizaciones_sesion'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_cotizaciones_sesion(:'ses_comp');

\qecho
\qecho '## M15 q_cotizacion_detalle'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_cotizacion_detalle(:'cot_comp');

\qecho
\qecho '## M16 q_historial_vehiculo'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_historial_vehiculo(:'veh', 20);

\qecho
\qecho '## M17 q_dashboard_resumen (ultimos 30 dias)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_dashboard_resumen(now() - interval '30 days');

\qecho
\qecho '## M17a ANTES: dashboard en un solo recorrido de las sesiones del taller (Fase 3)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE perf_dashboard_un_recorrido(now() - interval '30 days');

\qecho
\qecho '## M18 q_dashboard_dtc_frecuentes (ultimos 90 dias, 10 filas)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_dashboard_dtc_frecuentes(now() - interval '90 days', 10);

\qecho
\qecho '## M19 q_dtc_buscar (prefijo P10, 20 filas)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_dtc_buscar('P10', 20);

\qecho
\qecho '## M20 politica RLS con subconsulta: vehiculos visibles para el MECANICO (titular activo)'
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM vehiculo;

\qecho
\qecho '## M21 tx_crear_sesion (sesion + 2 fallas, con triggers y auditoria)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE tx_crear_sesion(:'veh', NULL, 123456, '[{"codigo": "P1000"}, {"codigo": "P1001"}]');

\qecho
\qecho '## M22 tx_crear_cotizacion (borrador nuevo)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE tx_crear_cotizacion(:'ses_libre', 'ffffffff-0000-4000-8000-000000000001');

\qecho
\qecho '## M23 tx_guardar_linea (snapshot de precio por trigger)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE tx_guardar_linea(:'cot_borr', :'rep', 2);

\qecho
\qecho '## M24 tx_cerrar_cotizacion (bloqueos, suma del detalle, vigente)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE tx_cerrar_cotizacion(:'cot_borr', NULL);

\qecho
\qecho '## M25 tx_cambiar_estado (pendiente -> cotizado)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE tx_cambiar_estado(:'ses_pend', 'cotizado', NULL);

-- ------------------------------------------------------------- administrador
RESET ROLE;
SET LOCAL ROLE taller_admin;
EXECUTE ctx(:'tv', :'u_adm', '10.0.0.2', 'perf') \gset ctx_

\qecho
\qecho '## M26 misma consulta que M20 para el ADMINISTRADOR (politica sin subconsulta)'
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM vehiculo;

\qecho
\qecho '## M27 q_auditoria - primera pagina (51 filas)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_auditoria(NULL, 51);

\qecho
\qecho '## M28 q_auditoria - pagina profunda por clave (cursor tras 500.000 registros)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_auditoria_siguiente(NULL, :'aud_ts', :aud_id, 51);

\qecho
\qecho '## M29 q_auditoria - filtrada por tabla'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_auditoria('cotizacion', 51);

\qecho
\qecho '## M30 q_usuarios'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_usuarios;

\qecho
\qecho '## M33 q_consentimientos_titular'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE q_consentimientos_titular(:'tit');

\qecho
\qecho '## M31 tx_solicitar_supresion (ultima atencion del titular, bloqueo o anonimizacion)'
EXPLAIN (ANALYZE, BUFFERS) EXECUTE tx_solicitar_supresion(:'tit');

-- -------------------------------------------------------------------- otros
RESET ROLE;
\qecho
\qecho '## M32 q_login (bcrypt de costo 10 dentro de la base)'
EXPLAIN (ANALYZE) EXECUTE q_login('mecanico1@volumen01.example', :'clave_demo');

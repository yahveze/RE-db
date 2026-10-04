-- =============================================================================
-- q07 - Dashboard del taller.                           roles: admin, mecanico, auditor
-- =============================================================================

-- GET /dashboard?since=
--   $1 inicio del periodo (la API envia, por ejemplo, el primer dia del mes)
-- Una fila siempre (ceros si no hay datos).
--   * Carga actual, sin periodo: sesiones_pendientes, sesiones_cotizadas,
--     monto_cotizado_abierto (total vigente de las sesiones en 'cotizado') y
--     fallas_criticas_abiertas (fallas criticas en sesiones no terminales).
--   * Periodo, por COHORTE: de las sesiones INICIADAS desde $1, cuantas hay
--     (sesiones_iniciadas_periodo) y cuantas de ellas estan hoy completadas o
--     canceladas, con el monto vigente de las completadas.
--
-- Forma de la consulta (medida en docs/evidencia/rendimiento.md):
--   * Los estados abiertos se leen de los indices PARCIALES
--     ix_sesion_diagnostico_pendiente e ix_sesion_diagnostico_cotizado. Cada
--     estado va como literal en su propia subconsulta: bajo RLS una igualdad de
--     enum no puede ser condicion de busqueda de un indice, pero si puede
--     demostrar el predicado de un indice parcial (ver V009).
--   * El periodo es UN recorrido por rango de ix_sesion_diagnostico_historial;
--     la cotizacion vigente solo se busca para las completadas (CASE).
--   * Los montos buscan la cotizacion vigente de cada sesion con una
--     subconsulta escalar (un acceso por uq_cotizacion_sesion_vigente). Escrito
--     como JOIN, el planificador sobreestima las sesiones del taller (no conoce
--     el valor de app.taller_id al planificar) y elige leer TODAS las
--     cotizaciones del taller para un hash join.
PREPARE q_dashboard_resumen (timestamptz) AS
SELECT (SELECT count(*) FROM sesion_diagnostico s WHERE s.estado = 'pendiente')   AS sesiones_pendientes,
       (SELECT count(*) FROM sesion_diagnostico s WHERE s.estado = 'cotizado')    AS sesiones_cotizadas,
       p.completadas                                                              AS sesiones_completadas_periodo,
       p.canceladas                                                               AS sesiones_canceladas_periodo,
       p.iniciadas                                                                AS sesiones_iniciadas_periodo,
       (SELECT COALESCE(sum((SELECT c.total FROM cotizacion c WHERE c.sesion_id = s.id AND c.vigente)), 0)::bigint
        FROM   sesion_diagnostico s
        WHERE  s.estado = 'cotizado')                                             AS monto_cotizado_abierto,
       p.monto_completado                                                         AS monto_completado_periodo,
       (SELECT count(*)
        FROM   sesion_diagnostico a
        JOIN   falla_sesion f ON f.sesion_id = a.id AND f.taller_id = a.taller_id
        WHERE  a.estado = 'pendiente' AND f.severidad = 'critica')
     + (SELECT count(*)
        FROM   sesion_diagnostico a
        JOIN   falla_sesion f ON f.sesion_id = a.id AND f.taller_id = a.taller_id
        WHERE  a.estado = 'cotizado' AND f.severidad = 'critica')                 AS fallas_criticas_abiertas,
       (SELECT tc.moneda FROM taller_configuracion tc)                            AS moneda
FROM  (SELECT count(*)                                         AS iniciadas,
              count(*) FILTER (WHERE s.estado = 'completado')  AS completadas,
              count(*) FILTER (WHERE s.estado = 'cancelado')   AS canceladas,
              COALESCE(sum(CASE WHEN s.estado = 'completado'
                                THEN (SELECT c.total FROM cotizacion c WHERE c.sesion_id = s.id AND c.vigente) END), 0)::bigint
                                                               AS monto_completado
       FROM   sesion_diagnostico s
       WHERE  s.iniciada_en >= $1) p;

-- GET /dashboard/top-dtc?since=&limit=
--   $1 inicio del periodo (por iniciada_en de la sesion), $2 limite
PREPARE q_dashboard_dtc_frecuentes (timestamptz, integer) AS
SELECT d.codigo,
       d.descripcion,
       count(*)                                         AS veces,
       count(*) FILTER (WHERE f.severidad = 'critica')  AS veces_critica
FROM   falla_sesion f
JOIN   sesion_diagnostico s ON s.id = f.sesion_id AND s.taller_id = f.taller_id
JOIN   dtc_catalogo d       ON d.id = f.dtc_id
WHERE  s.iniciada_en >= $1
GROUP  BY d.id, d.codigo, d.descripcion
ORDER  BY veces DESC, d.codigo
LIMIT  $2;

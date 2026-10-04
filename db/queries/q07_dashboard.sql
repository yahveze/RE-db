-- =============================================================================
-- q07 - Dashboard del taller.                           roles: admin, mecanico, auditor
-- =============================================================================

-- GET /dashboard?since=
--   $1 inicio del periodo (la API envia, por ejemplo, el primer dia del mes)
-- Una fila siempre (ceros si no hay datos).
--   * pendientes y cotizadas: carga de trabajo ACTUAL, sin periodo.
--   * completadas, canceladas e iniciadas: dentro del periodo.
--   * monto_cotizado_abierto: total vigente de las sesiones en 'cotizado'.
--   * fallas_criticas_abiertas: fallas criticas en sesiones no terminales
--     (ix_falla_sesion_critica).
PREPARE q_dashboard_resumen (timestamptz) AS
SELECT count(*) FILTER (WHERE s.estado = 'pendiente')                              AS sesiones_pendientes,
       count(*) FILTER (WHERE s.estado = 'cotizado')                               AS sesiones_cotizadas,
       count(*) FILTER (WHERE s.estado = 'completado' AND s.completada_en >= $1)   AS sesiones_completadas_periodo,
       count(*) FILTER (WHERE s.estado = 'cancelado'  AND s.cancelada_en  >= $1)   AS sesiones_canceladas_periodo,
       count(*) FILTER (WHERE s.iniciada_en >= $1)                                 AS sesiones_iniciadas_periodo,
       COALESCE(sum(c.total) FILTER (WHERE s.estado = 'cotizado'), 0)::bigint      AS monto_cotizado_abierto,
       COALESCE(sum(c.total) FILTER (WHERE s.estado = 'completado' AND s.completada_en >= $1), 0)::bigint
                                                                                   AS monto_completado_periodo,
       (SELECT count(*)
        FROM   falla_sesion f
        JOIN   sesion_diagnostico a ON a.id = f.sesion_id AND a.taller_id = f.taller_id
        WHERE  f.severidad = 'critica'
        AND    a.estado IN ('pendiente', 'cotizado'))                              AS fallas_criticas_abiertas,
       (SELECT tc.moneda FROM taller_configuracion tc)                             AS moneda
FROM   sesion_diagnostico s
LEFT   JOIN cotizacion c ON c.sesion_id = s.id AND c.vigente;

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

-- =============================================================================
-- Formulaciones ANTERIORES de dos consultas, conservadas solo para medir la
-- diferencia (docs/evidencia/rendimiento.md). El backend NO las usa: las
-- vigentes estan en db/queries/.
-- =============================================================================

-- q_historial de la Fase 3: una sola sentencia con estado y cursor opcionales.
PREPARE perf_historial_opcional (tipo_estado_atencion, timestamptz, uuid, integer) AS
SELECT s.id_publico, s.estado, s.iniciada_en, s.kilometraje, v.patente AS vehiculo_patente, u.nombre AS usuario_nombre,
       f.fallas, c.total AS cotizacion_total
FROM   sesion_diagnostico s
JOIN   usuario u         ON u.id = s.usuario_id
LEFT   JOIN vehiculo v   ON v.id = s.vehiculo_id
LEFT   JOIN cotizacion c ON c.sesion_id = s.id AND c.vigente
CROSS  JOIN LATERAL (SELECT count(*) AS fallas FROM falla_sesion x WHERE x.sesion_id = s.id) f
WHERE  ($1::tipo_estado_atencion IS NULL OR s.estado = $1)
AND    ($2::timestamptz IS NULL
        OR (s.iniciada_en, s.id) < ($2, (SELECT k.id FROM sesion_diagnostico k WHERE k.id_publico = $3)))
ORDER  BY s.iniciada_en DESC, s.id DESC
LIMIT  $4;

-- q_dashboard_resumen de la Fase 3: un solo recorrido de las sesiones del taller.
PREPARE perf_dashboard_un_recorrido (timestamptz) AS
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
        AND    a.estado IN ('pendiente', 'cotizado'))                              AS fallas_criticas_abiertas
FROM   sesion_diagnostico s
LEFT   JOIN cotizacion c ON c.sesion_id = s.id AND c.vigente;

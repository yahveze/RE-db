-- Genera el diccionario de datos en Markdown desde el catalogo del motor
-- (COMMENT ON de V004). Uso: bash db/scripts/diccionario.sh
\pset pager off
\pset tuples_only on
\pset format unaligned

WITH relaciones AS (
  SELECT c.oid, c.relname, c.relkind,
         obj_description(c.oid) AS comentario,
         CASE
           WHEN c.relname IN ('taller', 'taller_configuracion', 'usuario', 'usuario_credencial') THEN 1
           WHEN c.relname IN ('titular', 'consentimiento_titular', 'solicitud_derecho_titular') THEN 2
           WHEN c.relname IN ('marca_vehiculo', 'modelo_vehiculo', 'dtc_catalogo', 'componente_repuesto',
                              'dtc_componente', 'repuesto', 'compatibilidad_repuesto', 'v_dtc_repuesto') THEN 3
           WHEN c.relname IN ('vehiculo', 'dispositivo_diagnostico', 'sesion_diagnostico', 'falla_sesion',
                              'cotizacion', 'cotizacion_detalle') THEN 4
           ELSE 5
         END AS grupo
  FROM pg_class c
  WHERE c.relnamespace = 'public'::regnamespace
    AND c.relkind IN ('r', 'v')
    AND c.relname NOT LIKE 'pg\_%'
),
grupos (grupo, titulo) AS (
  VALUES (1, 'Multi-taller'), (2, 'Privacidad'), (3, 'Catalogos globales'), (4, 'Operacion'), (5, 'Seguridad')
),
lineas AS (
  -- Encabezado de grupo
  SELECT g.grupo, '' AS relname, 0 AS orden, 0 AS sub,
         E'\n## ' || g.titulo AS linea
  FROM grupos g
  UNION ALL
  -- Encabezado de tabla
  SELECT r.grupo, r.relname, 1, 0,
         E'\n### `' || r.relname || '`' || CASE WHEN r.relkind = 'v' THEN ' (vista)' ELSE '' END
         || E'\n\n' || r.comentario
         || E'\n\n| Columna | Tipo | Nulo | Valor por defecto | Descripcion |\n|---|---|---|---|---|'
  FROM relaciones r
  UNION ALL
  -- Columnas
  SELECT r.grupo, r.relname, 2, a.attnum,
         '| `' || a.attname || '` | ' || format_type(a.atttypid, a.atttypmod)
         || ' | ' || CASE WHEN a.attnotnull THEN 'no' ELSE 'si' END
         || ' | ' || COALESCE(
                CASE WHEN a.attidentity <> '' THEN 'identidad' END,
                '`' || replace(pg_get_expr(d.adbin, d.adrelid), '|', '\|') || '`',
                '')
         || ' | ' || replace(col_description(a.attrelid, a.attnum), '|', '\|') || ' |'
  FROM relaciones r
  JOIN pg_attribute a ON a.attrelid = r.oid AND a.attnum > 0 AND NOT a.attisdropped
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
)
SELECT linea FROM lineas ORDER BY grupo, relname, orden, sub;

\echo
\echo '## Tipos enumerados'
\echo
\echo '| Tipo | Valores | Descripcion |'
\echo '|---|---|---|'
SELECT '| `' || t.typname || '` | ' || string_agg(e.enumlabel, ', ' ORDER BY e.enumsortorder)
       || ' | ' || COALESCE(obj_description(t.oid, 'pg_type'), '') || ' |'
FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid
WHERE t.typnamespace = 'public'::regnamespace
GROUP BY t.typname, t.oid ORDER BY t.typname;

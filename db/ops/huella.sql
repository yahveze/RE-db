-- =============================================================================
-- Huella de los datos: una linea "tabla|filas|md5" por tabla del esquema public
-- y una linea "secuencia ...|ultimo valor" por secuencia. El md5 se calcula
-- sobre todas las filas en texto, ordenadas: dos bases con la misma huella
-- tienen los mismos datos. Se usa para comparar una base con su copia restaurada.
-- Ejecutar como superusuario (necesita ver sin RLS): psql -At -f /db/ops/huella.sql
-- Pensada para verificar respaldos del prototipo; con tablas de millones de
-- filas el string_agg es costoso.
-- =============================================================================
SELECT format(
         'SELECT %L, count(*), coalesce(md5(string_agg(t::text, chr(10) ORDER BY t::text)), ''-'') FROM %I t',
         c.relname, c.relname)
FROM   pg_class c
WHERE  c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
ORDER  BY c.relname
\gexec

SELECT 'secuencia ' || sequencename, coalesce(last_value::text, '-')
FROM   pg_sequences
WHERE  schemaname = 'public'
ORDER  BY sequencename;

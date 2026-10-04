-- =============================================================================
-- Purga de la auditoria por antiguedad (retencion). Unica via prevista para
-- borrar filas de auditoria_operacion.
--
-- Requiere la variable psql :'corte' (timestamptz): se eliminan las filas con
-- ocurrido_en ANTERIOR a ese instante. Debe ejecutarse como superusuario y
-- DENTRO de una transaccion (no abre ni cierra la suya): quien la incluye
-- decide el COMMIT tras comparar :purga_eliminadas con las filas archivadas.
-- Uso normal: bash db/scripts/purgar_auditoria.sh <anios>
--
-- Como salta la inmutabilidad. Los triggers trg_auditoria_operacion_inmutable_*
-- rechazan UPDATE, DELETE y TRUNCATE incluso al superusuario. Se usa
-- session_replication_role = replica, que desactiva los triggers comunes SOLO
-- para esta transaccion (SET LOCAL) y solo puede fijarlo un superusuario. A
-- diferencia de ALTER TABLE ... DISABLE TRIGGER, no toma ACCESS EXCLUSIVE sobre
-- la tabla (no detiene a quienes escriben auditoria) y no deja la tabla
-- desprotegida para las demas sesiones. Se restaura 'origin' antes de terminar
-- para que el resto de la transaccion vuelva a estar protegido.
-- =============================================================================
SET LOCAL session_replication_role = replica;

DELETE FROM auditoria_operacion WHERE ocurrido_en < :'corte'::timestamptz;
-- Filas eliminadas, para quien incluye este archivo (el SET siguiente pisa :ROW_COUNT).
\set purga_eliminadas :ROW_COUNT

SET LOCAL session_replication_role = origin;

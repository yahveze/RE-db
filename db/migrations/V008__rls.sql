-- =============================================================================
-- V008 - Row Level Security: QUE FILAS puede ver o modificar un rol.
-- Unico lugar donde se activa RLS (ENABLE y FORCE).
--
-- Contexto a prueba de fallos:
--     (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
--   * current_setting(..., true): si la variable no existe devuelve NULL en
--     vez de error.
--   * NULLIF(..., ''): tras un SET LOCAL la variable queda como cadena vacia
--     al terminar la transaccion; se trata igual que ausente.
--   * Sin contexto la comparacion es "taller_id = NULL", que nunca es
--     verdadera: no hay filas (falla cerrado).
--   * Envuelto en (SELECT ...): el planificador lo evalua UNA vez por consulta
--     (InitPlan) y no una vez por fila, y puede usar los indices que empiezan
--     por taller_id.
--
-- Sin politica aplicable = denegado. Cada politica declara a que rol aplica
-- (TO) y que operacion (FOR).
-- Nombres: pol_<tabla>_<rol>_<operacion>. <rol> = 'miembros' cuando la misma
-- politica aplica a los tres grupos (admin, mecanico y auditor).
--
-- FORCE: tambien el propietario (app_owner) queda sujeto a las politicas.
-- Alternativa descartada: no usar FORCE y dejar exento al propietario; un
-- error de despliegue que usara app_owner en ejecucion saltaria el aislamiento
-- sin que nada lo advirtiera. Con FORCE, las funciones que necesitan ver mas
-- alla del contexto pertenecen a un rol dedicado y acotado (app_funciones).
--
-- Las comprobaciones de integridad referencial (FK) siempre omiten RLS.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- taller: cada rol ve solo la fila de su taller
-- ----------------------------------------------------------------------------
ALTER TABLE taller ENABLE ROW LEVEL SECURITY;
ALTER TABLE taller FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_taller_miembros_select ON taller
  FOR SELECT TO taller_admin, taller_mecanico, taller_auditor
  USING (id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

-- ----------------------------------------------------------------------------
-- taller_configuracion
-- ----------------------------------------------------------------------------
ALTER TABLE taller_configuracion ENABLE ROW LEVEL SECURITY;
ALTER TABLE taller_configuracion FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_taller_configuracion_miembros_select ON taller_configuracion
  FOR SELECT TO taller_admin, taller_mecanico, taller_auditor
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_taller_configuracion_admin_update ON taller_configuracion
  FOR UPDATE TO taller_admin
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint))
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

-- ----------------------------------------------------------------------------
-- usuario
-- ----------------------------------------------------------------------------
ALTER TABLE usuario ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuario FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_usuario_miembros_select ON usuario
  FOR SELECT TO taller_admin, taller_mecanico, taller_auditor
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_usuario_admin_insert ON usuario
  FOR INSERT TO taller_admin
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_usuario_admin_update ON usuario
  FOR UPDATE TO taller_admin
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint))
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

-- ----------------------------------------------------------------------------
-- usuario_credencial: RLS activo y NINGUNA politica = denegado para todos
-- salvo app_funciones (BYPASSRLS). Segunda barrera tras la ausencia de GRANT.
-- ----------------------------------------------------------------------------
ALTER TABLE usuario_credencial ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuario_credencial FORCE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- titular: el mecanico solo ve y modifica titulares en estado 'activo'
-- ----------------------------------------------------------------------------
ALTER TABLE titular ENABLE ROW LEVEL SECURITY;
ALTER TABLE titular FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_titular_admin_select ON titular
  FOR SELECT TO taller_admin
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_titular_auditor_select ON titular
  FOR SELECT TO taller_auditor
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_titular_mecanico_select ON titular
  FOR SELECT TO taller_mecanico
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
         AND estado_tratamiento = 'activo');

CREATE POLICY pol_titular_admin_insert ON titular
  FOR INSERT TO taller_admin
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
              AND estado_tratamiento = 'activo');

CREATE POLICY pol_titular_mecanico_insert ON titular
  FOR INSERT TO taller_mecanico
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
              AND estado_tratamiento = 'activo');

CREATE POLICY pol_titular_admin_update ON titular
  FOR UPDATE TO taller_admin
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint))
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_titular_mecanico_update ON titular
  FOR UPDATE TO taller_mecanico
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
              AND estado_tratamiento = 'activo')
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
              AND estado_tratamiento = 'activo');

-- ----------------------------------------------------------------------------
-- consentimiento_titular
-- El mecanico solo opera sobre consentimientos de titulares que puede ver:
-- la subconsulta sobre titular esta sujeta a la politica del mecanico.
-- ----------------------------------------------------------------------------
ALTER TABLE consentimiento_titular ENABLE ROW LEVEL SECURITY;
ALTER TABLE consentimiento_titular FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_consentimiento_titular_admin_select ON consentimiento_titular
  FOR SELECT TO taller_admin
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_consentimiento_titular_auditor_select ON consentimiento_titular
  FOR SELECT TO taller_auditor
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_consentimiento_titular_mecanico_select ON consentimiento_titular
  FOR SELECT TO taller_mecanico
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
         AND EXISTS (SELECT 1 FROM titular t WHERE t.id = consentimiento_titular.titular_id));

CREATE POLICY pol_consentimiento_titular_admin_insert ON consentimiento_titular
  FOR INSERT TO taller_admin
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_consentimiento_titular_mecanico_insert ON consentimiento_titular
  FOR INSERT TO taller_mecanico
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
              AND EXISTS (SELECT 1 FROM titular t WHERE t.id = consentimiento_titular.titular_id));

CREATE POLICY pol_consentimiento_titular_admin_update ON consentimiento_titular
  FOR UPDATE TO taller_admin
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint))
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_consentimiento_titular_mecanico_update ON consentimiento_titular
  FOR UPDATE TO taller_mecanico
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
              AND EXISTS (SELECT 1 FROM titular t WHERE t.id = consentimiento_titular.titular_id))
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

-- ----------------------------------------------------------------------------
-- solicitud_derecho_titular: administrador gestiona, auditor lee
-- ----------------------------------------------------------------------------
ALTER TABLE solicitud_derecho_titular ENABLE ROW LEVEL SECURITY;
ALTER TABLE solicitud_derecho_titular FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_solicitud_derecho_titular_admin_select ON solicitud_derecho_titular
  FOR SELECT TO taller_admin
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_solicitud_derecho_titular_auditor_select ON solicitud_derecho_titular
  FOR SELECT TO taller_auditor
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_solicitud_derecho_titular_admin_insert ON solicitud_derecho_titular
  FOR INSERT TO taller_admin
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_solicitud_derecho_titular_admin_update ON solicitud_derecho_titular
  FOR UPDATE TO taller_admin
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint))
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

-- ----------------------------------------------------------------------------
-- vehiculo: el mecanico no ve vehiculos anonimizados ni de titulares que no
-- puede ver (bloqueados o anonimizados). La subconsulta sobre titular esta
-- sujeta a la politica del mecanico, que ya filtra por estado 'activo'.
-- ----------------------------------------------------------------------------
ALTER TABLE vehiculo ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehiculo FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_vehiculo_admin_select ON vehiculo
  FOR SELECT TO taller_admin
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_vehiculo_auditor_select ON vehiculo
  FOR SELECT TO taller_auditor
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_vehiculo_mecanico_select ON vehiculo
  FOR SELECT TO taller_mecanico
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
         AND anonimizado_en IS NULL
         AND (titular_id IS NULL
              OR EXISTS (SELECT 1 FROM titular t WHERE t.id = vehiculo.titular_id)));

CREATE POLICY pol_vehiculo_admin_insert ON vehiculo
  FOR INSERT TO taller_admin
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_vehiculo_mecanico_insert ON vehiculo
  FOR INSERT TO taller_mecanico
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
              AND anonimizado_en IS NULL
              AND (titular_id IS NULL
                   OR EXISTS (SELECT 1 FROM titular t WHERE t.id = vehiculo.titular_id)));

CREATE POLICY pol_vehiculo_admin_update ON vehiculo
  FOR UPDATE TO taller_admin
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint))
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_vehiculo_mecanico_update ON vehiculo
  FOR UPDATE TO taller_mecanico
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
              AND anonimizado_en IS NULL
              AND (titular_id IS NULL
                   OR EXISTS (SELECT 1 FROM titular t WHERE t.id = vehiculo.titular_id)))
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
              AND anonimizado_en IS NULL
              AND (titular_id IS NULL
                   OR EXISTS (SELECT 1 FROM titular t WHERE t.id = vehiculo.titular_id)));

-- ----------------------------------------------------------------------------
-- dispositivo_diagnostico
-- ----------------------------------------------------------------------------
ALTER TABLE dispositivo_diagnostico ENABLE ROW LEVEL SECURITY;
ALTER TABLE dispositivo_diagnostico FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_dispositivo_diagnostico_miembros_select ON dispositivo_diagnostico
  FOR SELECT TO taller_admin, taller_mecanico, taller_auditor
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_dispositivo_diagnostico_admin_insert ON dispositivo_diagnostico
  FOR INSERT TO taller_admin
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_dispositivo_diagnostico_admin_update ON dispositivo_diagnostico
  FOR UPDATE TO taller_admin
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint))
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

-- ----------------------------------------------------------------------------
-- sesion_diagnostico: la sesion queda a nombre del usuario que la crea
-- ----------------------------------------------------------------------------
ALTER TABLE sesion_diagnostico ENABLE ROW LEVEL SECURITY;
ALTER TABLE sesion_diagnostico FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_sesion_diagnostico_miembros_select ON sesion_diagnostico
  FOR SELECT TO taller_admin, taller_mecanico, taller_auditor
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_sesion_diagnostico_mecanico_insert ON sesion_diagnostico
  FOR INSERT TO taller_mecanico
  WITH CHECK (taller_id  = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
              AND usuario_id = (SELECT NULLIF(current_setting('app.usuario_id', true), '')::bigint));

CREATE POLICY pol_sesion_diagnostico_mecanico_update ON sesion_diagnostico
  FOR UPDATE TO taller_mecanico
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint))
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

-- ----------------------------------------------------------------------------
-- falla_sesion
-- ----------------------------------------------------------------------------
ALTER TABLE falla_sesion ENABLE ROW LEVEL SECURITY;
ALTER TABLE falla_sesion FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_falla_sesion_miembros_select ON falla_sesion
  FOR SELECT TO taller_admin, taller_mecanico, taller_auditor
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_falla_sesion_mecanico_insert ON falla_sesion
  FOR INSERT TO taller_mecanico
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_falla_sesion_mecanico_update ON falla_sesion
  FOR UPDATE TO taller_mecanico
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint))
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

-- ----------------------------------------------------------------------------
-- cotizacion
-- ----------------------------------------------------------------------------
ALTER TABLE cotizacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE cotizacion FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_cotizacion_miembros_select ON cotizacion
  FOR SELECT TO taller_admin, taller_mecanico, taller_auditor
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_cotizacion_mecanico_insert ON cotizacion
  FOR INSERT TO taller_mecanico
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_cotizacion_mecanico_update ON cotizacion
  FOR UPDATE TO taller_mecanico
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint))
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

-- ----------------------------------------------------------------------------
-- cotizacion_detalle
-- ----------------------------------------------------------------------------
ALTER TABLE cotizacion_detalle ENABLE ROW LEVEL SECURITY;
ALTER TABLE cotizacion_detalle FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_cotizacion_detalle_miembros_select ON cotizacion_detalle
  FOR SELECT TO taller_admin, taller_mecanico, taller_auditor
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_cotizacion_detalle_mecanico_insert ON cotizacion_detalle
  FOR INSERT TO taller_mecanico
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_cotizacion_detalle_mecanico_update ON cotizacion_detalle
  FOR UPDATE TO taller_mecanico
  USING      (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint))
  WITH CHECK (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_cotizacion_detalle_mecanico_delete ON cotizacion_detalle
  FOR DELETE TO taller_mecanico
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

-- ----------------------------------------------------------------------------
-- auditoria_operacion: solo la leen el administrador y el auditor de su taller.
-- Los registros con taller_id NULL (logins de emails inexistentes, catalogos)
-- no son visibles para ningun taller.
-- ----------------------------------------------------------------------------
ALTER TABLE auditoria_operacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE auditoria_operacion FORCE ROW LEVEL SECURITY;

CREATE POLICY pol_auditoria_operacion_admin_select ON auditoria_operacion
  FOR SELECT TO taller_admin
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

CREATE POLICY pol_auditoria_operacion_auditor_select ON auditoria_operacion
  FOR SELECT TO taller_auditor
  USING (taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint));

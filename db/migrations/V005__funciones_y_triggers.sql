-- =============================================================================
-- V005 - Funciones y triggers.
-- Orden: funciones primero, luego los triggers que las usan, los comentarios, y al final el
-- cambio de propietario de las funciones SECURITY DEFINER a app_funciones.
--
-- Codigos de error propios (SQLSTATE) para que la API los distinga:
--   RE001 transicion de estado invalida
--   RE002 falta una cotizacion vigente cerrada
--   RE003 la cotizacion esta cerrada (inmutable)
--   RE004 la sesion esta en estado terminal
--   RE005 la auditoria es inmutable
--   RE006 contexto o rol no autorizado
--   RE007 conflicto de version (control optimista)
--   RE008 cotizacion sin detalle
--   RE009 registro inexistente o no visible
--   RE010 repuesto no disponible
--   RE011 contrasena fuera de los limites permitidos
--   RE012 columna no modificable
--
-- Toda funcion fija SET search_path = pg_catalog, public: obligatorio en las
-- SECURITY DEFINER (evita que un objeto homonimo en otro esquema suplante a
-- uno real) y aplicado tambien a las demas por uniformidad.
-- =============================================================================

-- =============================================================================
-- 1. CONTEXTO DE LA PETICION
-- =============================================================================

-- Taller de la peticion. Sin contexto devuelve NULL (falla cerrado).
CREATE FUNCTION fn_contexto_taller_id() RETURNS bigint
LANGUAGE sql STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint
$$;

CREATE FUNCTION fn_contexto_usuario_id() RETURNS bigint
LANGUAGE sql STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT NULLIF(current_setting('app.usuario_id', true), '')::bigint
$$;

-- Rol efectivo de la peticion. Dentro de una funcion SECURITY DEFINER
-- current_user es el propietario de la funcion, por eso se lee el parametro
-- 'role' (el fijado con SET LOCAL ROLE). Si no hay, el rol de sesion.
CREATE FUNCTION fn_contexto_rol() RETURNS text
LANGUAGE sql STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
           WHEN COALESCE(current_setting('role', true), '') IN ('', 'none') THEN session_user::text
           ELSE current_setting('role', true)
         END
$$;

-- IP de origen. Un valor mal formado no debe impedir la operacion auditada.
CREATE FUNCTION fn_contexto_ip_origen() RETURNS inet
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, public
AS $$
BEGIN
  RETURN NULLIF(current_setting('app.ip_origen', true), '')::inet;
EXCEPTION WHEN invalid_text_representation THEN
  RETURN NULL;
END;
$$;

-- =============================================================================
-- 2. TRIGGERS GENERICOS: actualizado_en y version
-- =============================================================================

CREATE FUNCTION fn_trg_marcar_actualizado() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.actualizado_en := now();
  RETURN NEW;
END;
$$;

-- Control optimista: cada UPDATE incrementa version. La API actualiza con
-- WHERE id = $1 AND version = $2 y trata 0 filas como conflicto.
CREATE FUNCTION fn_trg_incrementar_version() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.version := OLD.version + 1;
  RETURN NEW;
END;
$$;

-- =============================================================================
-- 3. AUDITORIA
-- =============================================================================

-- Unico punto de escritura en auditoria_operacion. No tiene EXECUTE para los
-- roles de grupo: solo la llaman las funciones propiedad de app_funciones.
CREATE FUNCTION fn_registrar_auditoria(
  p_taller_id        bigint,
  p_usuario_id       bigint,
  p_operacion        tipo_operacion_auditoria,
  p_tabla            text,
  p_registro_id      bigint,
  p_datos_anteriores jsonb,
  p_datos_nuevos     jsonb,
  p_resultado        tipo_resultado_auditoria
) RETURNS void
LANGUAGE sql
SET search_path = pg_catalog, public
AS $$
  INSERT INTO auditoria_operacion (
    taller_id, usuario_id, rol, operacion, tabla, registro_id,
    datos_anteriores, datos_nuevos, ip_origen, resultado, request_id)
  VALUES (
    p_taller_id, p_usuario_id, fn_contexto_rol(), p_operacion, p_tabla, p_registro_id,
    p_datos_anteriores, p_datos_nuevos, fn_contexto_ip_origen(), p_resultado,
    NULLIF(current_setting('app.request_id', true), ''))
$$;

-- Trigger generico de auditoria. Los argumentos del trigger (TG_ARGV) son las
-- columnas sensibles que se EXCLUYEN de datos_anteriores y datos_nuevos.
-- SECURITY DEFINER: los roles normales no tienen INSERT en la auditoria.
-- Tolera contexto vacio (semillas, migraciones): taller y usuario quedan como
-- se puedan deducir de la fila, y el rol es el de sesion.
CREATE FUNCTION fn_trg_auditar() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_excluir    text[] := ARRAY[]::text[];
  v_anteriores jsonb;
  v_nuevos     jsonb;
  v_fila       jsonb;
  v_taller_id  bigint;
BEGIN
  FOR i IN 0 .. TG_NARGS - 1 LOOP
    v_excluir := v_excluir || TG_ARGV[i];
  END LOOP;

  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    v_anteriores := to_jsonb(OLD) - v_excluir;
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    v_nuevos := to_jsonb(NEW) - v_excluir;
  END IF;
  v_fila := COALESCE(v_nuevos, v_anteriores);

  IF TG_TABLE_NAME = 'taller' THEN
    v_taller_id := (v_fila ->> 'id')::bigint;
  ELSE
    v_taller_id := (v_fila ->> 'taller_id')::bigint;
  END IF;

  PERFORM fn_registrar_auditoria(
    COALESCE(v_taller_id, fn_contexto_taller_id()),
    fn_contexto_usuario_id(),
    TG_OP::tipo_operacion_auditoria,
    TG_TABLE_NAME::text,
    (v_fila ->> 'id')::bigint,
    v_anteriores,
    v_nuevos,
    'exito');
  RETURN NULL;
END;
$$;

-- Segunda capa de inmutabilidad (la primera es no otorgar privilegios):
-- rechaza UPDATE, DELETE y TRUNCATE incluso para el propietario.
CREATE FUNCTION fn_trg_auditoria_inmutable() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  RAISE EXCEPTION 'auditoria_operacion es de solo insercion: % no permitido', TG_OP
    USING ERRCODE = 'RE005';
END;
$$;

-- =============================================================================
-- 4. ESTADOS DE LA SESION
-- =============================================================================

-- BEFORE UPDATE OF estado: valida la transicion, exige cotizacion vigente
-- cerrada para 'cotizado' y 'completado', y fija el timestamp del estado.
CREATE FUNCTION fn_trg_sesion_validar_transicion() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.estado = OLD.estado THEN
    RETURN NEW;
  END IF;

  IF NOT (
       (OLD.estado = 'pendiente' AND NEW.estado IN ('cotizado', 'cancelado'))
    OR (OLD.estado = 'cotizado'  AND NEW.estado IN ('completado', 'cancelado'))
  ) THEN
    RAISE EXCEPTION 'transicion de estado invalida: % -> %', OLD.estado, NEW.estado
      USING ERRCODE = 'RE001';
  END IF;

  IF NEW.estado IN ('cotizado', 'completado') AND NOT EXISTS (
       SELECT 1
       FROM   cotizacion c
       WHERE  c.sesion_id = NEW.id
       AND    c.vigente
       AND    c.cerrada_en IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'el estado % exige una cotizacion vigente cerrada', NEW.estado
      USING ERRCODE = 'RE002';
  END IF;

  CASE NEW.estado
    WHEN 'cotizado'   THEN NEW.cotizada_en   := now();
    WHEN 'completado' THEN NEW.completada_en := now();
    WHEN 'cancelado'  THEN NEW.cancelada_en  := now();
  END CASE;

  RETURN NEW;
END;
$$;

-- Cambio de estado con bloqueo pesimista y orden de bloqueo FIJO:
-- sesion -> cotizacion (-> detalle). Si dos transacciones tomaran los bloqueos
-- en orden distinto podrian esperarse mutuamente (deadlock).
-- p_version_esperada (opcional) agrega control optimista.
CREATE FUNCTION fn_cambiar_estado_sesion(
  p_sesion_id         bigint,
  p_nuevo_estado      tipo_estado_atencion,
  p_version_esperada  integer DEFAULT NULL
) RETURNS sesion_diagnostico
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_sesion sesion_diagnostico;
BEGIN
  SELECT s.* INTO v_sesion
  FROM   sesion_diagnostico s
  WHERE  s.id = p_sesion_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'la sesion % no existe o no es visible', p_sesion_id
      USING ERRCODE = 'RE009';
  END IF;

  IF p_version_esperada IS NOT NULL AND v_sesion.version <> p_version_esperada THEN
    RAISE EXCEPTION 'conflicto de version en la sesion %: esperada %, actual %',
      p_sesion_id, p_version_esperada, v_sesion.version
      USING ERRCODE = 'RE007';
  END IF;

  PERFORM 1
  FROM   cotizacion c
  WHERE  c.sesion_id = p_sesion_id
  AND    c.vigente
  FOR UPDATE;

  UPDATE sesion_diagnostico s
  SET    estado = p_nuevo_estado
  WHERE  s.id = p_sesion_id
  RETURNING s.* INTO v_sesion;

  RETURN v_sesion;
END;
$$;

-- =============================================================================
-- 5. COTIZACION
-- =============================================================================

-- BEFORE INSERT: una cotizacion siempre nace como borrador.
-- FOR SHARE sobre la sesion: espera a un cambio de estado concurrente y lee
-- el estado ya confirmado (una sesion terminal no admite cotizaciones nuevas).
CREATE FUNCTION fn_trg_cotizacion_preparar() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_estado tipo_estado_atencion;
  v_moneda char(3);
BEGIN
  SELECT s.estado INTO v_estado
  FROM   sesion_diagnostico s
  WHERE  s.id = NEW.sesion_id
  AND    s.taller_id = NEW.taller_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'la sesion % no existe o no es visible', NEW.sesion_id
      USING ERRCODE = 'RE009';
  END IF;

  IF v_estado IN ('completado', 'cancelado') THEN
    RAISE EXCEPTION 'la sesion % esta en estado % y no admite cotizaciones nuevas', NEW.sesion_id, v_estado
      USING ERRCODE = 'RE004';
  END IF;

  SELECT tc.moneda INTO v_moneda
  FROM   taller_configuracion tc
  WHERE  tc.taller_id = NEW.taller_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'el taller % no tiene configuracion', NEW.taller_id
      USING ERRCODE = 'RE009';
  END IF;

  NEW.moneda          := v_moneda;
  NEW.numero_revision := (SELECT COALESCE(max(c.numero_revision), 0) + 1
                          FROM   cotizacion c
                          WHERE  c.sesion_id = NEW.sesion_id);
  NEW.vigente    := false;
  NEW.cerrada_en := NULL;
  NEW.total      := NULL;
  NEW.version    := 1;
  RETURN NEW;
END;
$$;

-- BEFORE UPDATE: inmutabilidad de la cotizacion cerrada y calculo del total.
--   * Cerrada: lo unico permitido es apagar 'vigente' (la reemplaza otra revision).
--   * Al cerrar: el total lo calcula el trigger desde el detalle; el valor que
--     envie el cliente se ignora. cerrada_en es siempre la hora del servidor.
CREATE FUNCTION fn_trg_cotizacion_validar_actualizacion() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_estado tipo_estado_atencion;
  v_lineas bigint;
  v_total  bigint;
BEGIN
  IF NEW.id                 IS DISTINCT FROM OLD.id
  OR NEW.id_publico         IS DISTINCT FROM OLD.id_publico
  OR NEW.taller_id          IS DISTINCT FROM OLD.taller_id
  OR NEW.sesion_id          IS DISTINCT FROM OLD.sesion_id
  OR NEW.numero_revision    IS DISTINCT FROM OLD.numero_revision
  OR NEW.moneda             IS DISTINCT FROM OLD.moneda
  OR NEW.clave_idempotencia IS DISTINCT FROM OLD.clave_idempotencia
  OR NEW.creado_en          IS DISTINCT FROM OLD.creado_en THEN
    RAISE EXCEPTION 'los datos de identidad de una cotizacion no se pueden modificar'
      USING ERRCODE = 'RE012';
  END IF;

  IF OLD.cerrada_en IS NOT NULL THEN
    IF NEW.cerrada_en IS DISTINCT FROM OLD.cerrada_en
    OR NEW.total      IS DISTINCT FROM OLD.total
    OR (NEW.vigente AND NOT OLD.vigente) THEN
      RAISE EXCEPTION 'la cotizacion % esta cerrada y es inmutable', OLD.id
        USING ERRCODE = 'RE003';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.cerrada_en IS NULL THEN
    NEW.total := NULL;
    RETURN NEW;
  END IF;

  -- Cierre.
  SELECT s.estado INTO v_estado
  FROM   sesion_diagnostico s
  WHERE  s.id = OLD.sesion_id
  FOR SHARE;

  IF v_estado IN ('completado', 'cancelado') THEN
    RAISE EXCEPTION 'la sesion % esta en estado % y su cotizacion no se puede cerrar', OLD.sesion_id, v_estado
      USING ERRCODE = 'RE004';
  END IF;

  SELECT count(*), COALESCE(sum(d.cantidad::bigint * d.precio_unitario), 0)
  INTO   v_lineas, v_total
  FROM   cotizacion_detalle d
  WHERE  d.cotizacion_id = OLD.id;

  IF v_lineas = 0 THEN
    RAISE EXCEPTION 'la cotizacion % no tiene detalle y no se puede cerrar', OLD.id
      USING ERRCODE = 'RE008';
  END IF;

  NEW.total      := v_total;
  NEW.cerrada_en := now();
  RETURN NEW;
END;
$$;

-- BEFORE INSERT/UPDATE/DELETE sobre el detalle.
--   * Rechaza todo cambio si la cabecera esta cerrada.
--   * FOR SHARE sobre la cabecera: si un cierre esta en curso (FOR UPDATE o el
--     propio UPDATE de cierre), espera y relee la fila ya cerrada. Sin este
--     bloqueo, en READ COMMITTED el trigger podria leer la cabecera "abierta",
--     esperar despues en la FK y completar la insercion tras el cierre.
--   * En INSERT llena el snapshot y calcula el precio: el cliente solo envia
--     repuesto_id y cantidad.
CREATE FUNCTION fn_trg_cotizacion_detalle_validar() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_cotizacion_id bigint;
  v_cerrada_en    timestamptz;
  v_repuesto      repuesto;
  v_margen        numeric(5,2);
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_cotizacion_id := OLD.cotizacion_id;
  ELSE
    v_cotizacion_id := NEW.cotizacion_id;
  END IF;

  SELECT c.cerrada_en INTO v_cerrada_en
  FROM   cotizacion c
  WHERE  c.id = v_cotizacion_id
  FOR SHARE;

  IF FOUND AND v_cerrada_en IS NOT NULL THEN
    RAISE EXCEPTION 'la cotizacion % esta cerrada: su detalle es inmutable', v_cotizacion_id
      USING ERRCODE = 'RE003';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.cotizacion_id              IS DISTINCT FROM OLD.cotizacion_id
    OR NEW.repuesto_id                IS DISTINCT FROM OLD.repuesto_id
    OR NEW.taller_id                  IS DISTINCT FROM OLD.taller_id
    OR NEW.nombre_snapshot            IS DISTINCT FROM OLD.nombre_snapshot
    OR NEW.marca_snapshot             IS DISTINCT FROM OLD.marca_snapshot
    OR NEW.perfil_snapshot            IS DISTINCT FROM OLD.perfil_snapshot
    OR NEW.precio_referencia_snapshot IS DISTINCT FROM OLD.precio_referencia_snapshot
    OR NEW.margen_pct_snapshot        IS DISTINCT FROM OLD.margen_pct_snapshot
    OR NEW.precio_unitario            IS DISTINCT FROM OLD.precio_unitario
    OR NEW.creado_en                  IS DISTINCT FROM OLD.creado_en THEN
      RAISE EXCEPTION 'en el detalle de una cotizacion solo se puede modificar la cantidad'
        USING ERRCODE = 'RE012';
    END IF;
    RETURN NEW;
  END IF;

  -- INSERT: snapshot.
  SELECT r.* INTO v_repuesto
  FROM   repuesto r
  WHERE  r.id = NEW.repuesto_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'el repuesto % no existe', NEW.repuesto_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF NOT v_repuesto.disponible THEN
    RAISE EXCEPTION 'el repuesto % no esta disponible', NEW.repuesto_id
      USING ERRCODE = 'RE010';
  END IF;

  SELECT tc.margen_pct INTO v_margen
  FROM   taller_configuracion tc
  WHERE  tc.taller_id = NEW.taller_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'el taller % no tiene configuracion', NEW.taller_id
      USING ERRCODE = 'RE009';
  END IF;

  NEW.nombre_snapshot            := v_repuesto.nombre;
  NEW.marca_snapshot             := v_repuesto.marca;
  NEW.perfil_snapshot            := v_repuesto.perfil;
  NEW.precio_referencia_snapshot := v_repuesto.precio_referencia;
  NEW.margen_pct_snapshot        := v_margen;
  NEW.precio_unitario            := ROUND(v_repuesto.precio_referencia * (1 + v_margen / 100));
  RETURN NEW;
END;
$$;

-- Crea una cotizacion (borrador) de forma idempotente: reintentar con la misma
-- clave devuelve la cotizacion existente en lugar de crear otra.
CREATE FUNCTION fn_crear_cotizacion(
  p_sesion_id          bigint,
  p_clave_idempotencia uuid
) RETURNS cotizacion
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_taller_id  bigint := fn_contexto_taller_id();
  v_cotizacion cotizacion;
BEGIN
  IF v_taller_id IS NULL THEN
    RAISE EXCEPTION 'no hay contexto de taller' USING ERRCODE = 'RE006';
  END IF;

  SELECT c.* INTO v_cotizacion
  FROM   cotizacion c
  WHERE  c.taller_id = v_taller_id
  AND    c.clave_idempotencia = p_clave_idempotencia;

  IF FOUND THEN
    RETURN v_cotizacion;
  END IF;

  INSERT INTO cotizacion AS c (taller_id, sesion_id, clave_idempotencia)
  VALUES (v_taller_id, p_sesion_id, p_clave_idempotencia)
  ON CONFLICT (taller_id, clave_idempotencia) DO NOTHING
  RETURNING c.* INTO v_cotizacion;

  IF NOT FOUND THEN
    -- Otra transaccion inserto la misma clave entre el SELECT y el INSERT.
    SELECT c.* INTO v_cotizacion
    FROM   cotizacion c
    WHERE  c.taller_id = v_taller_id
    AND    c.clave_idempotencia = p_clave_idempotencia;
  END IF;

  RETURN v_cotizacion;
END;
$$;

-- Cierra una cotizacion. Orden de bloqueo: sesion -> cotizacion.
-- El FOR UPDATE sobre la cabecera serializa las inserciones concurrentes de
-- detalle: tanto el trigger del detalle (FOR SHARE) como su FK (FOR KEY SHARE)
-- entran en conflicto con FOR UPDATE y deben esperar al COMMIT del cierre.
-- El total lo calcula el trigger de la cabecera. Cerrar una cotizacion ya
-- cerrada la devuelve sin cambios (idempotente).
CREATE FUNCTION fn_cerrar_cotizacion(
  p_cotizacion_id     bigint,
  p_version_esperada  integer DEFAULT NULL
) RETURNS cotizacion
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_sesion_id  bigint;
  v_cotizacion cotizacion;
BEGIN
  SELECT c.sesion_id INTO v_sesion_id
  FROM   cotizacion c
  WHERE  c.id = p_cotizacion_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'la cotizacion % no existe o no es visible', p_cotizacion_id
      USING ERRCODE = 'RE009';
  END IF;

  PERFORM 1 FROM sesion_diagnostico s WHERE s.id = v_sesion_id FOR UPDATE;

  SELECT c.* INTO v_cotizacion
  FROM   cotizacion c
  WHERE  c.id = p_cotizacion_id
  FOR UPDATE;

  IF v_cotizacion.cerrada_en IS NOT NULL THEN
    RETURN v_cotizacion;
  END IF;

  IF p_version_esperada IS NOT NULL AND v_cotizacion.version <> p_version_esperada THEN
    RAISE EXCEPTION 'conflicto de version en la cotizacion %: esperada %, actual %',
      p_cotizacion_id, p_version_esperada, v_cotizacion.version
      USING ERRCODE = 'RE007';
  END IF;

  -- Primero se apaga la vigente anterior: el indice unico parcial no es diferible.
  UPDATE cotizacion c
  SET    vigente = false
  WHERE  c.sesion_id = v_sesion_id
  AND    c.vigente;

  UPDATE cotizacion c
  SET    cerrada_en = now(),
         vigente    = true
  WHERE  c.id = p_cotizacion_id
  RETURNING c.* INTO v_cotizacion;

  RETURN v_cotizacion;
END;
$$;

-- =============================================================================
-- 6. AUTENTICACION (prototipo: crypt() dentro de la base)
-- =============================================================================

-- Autentica por email y contrasena. Se ejecuta ANTES de que exista contexto de
-- taller, por eso es SECURITY DEFINER y su propietario tiene BYPASSRLS.
--   * Nunca devuelve el hash.
--   * No lanza excepcion ante credenciales invalidas: devuelve autenticado =
--     false. Una excepcion revertiria el contador de intentos y la auditoria.
--   * No distingue el motivo del fallo hacia el llamador.
--   * Si el email no existe ejecuta igual un crypt() de costo equivalente,
--     para no delatar por tiempo de respuesta que emails existen.
--   * bcrypt solo considera los primeros 72 bytes de la contrasena.
CREATE FUNCTION fn_autenticar_usuario(
  p_email      text,
  p_contrasena text
) RETURNS TABLE (
  autenticado         boolean,
  usuario_id          bigint,
  usuario_id_publico  uuid,
  taller_id           bigint,
  taller_id_publico   uuid,
  rol                 tipo_rol_usuario,
  nombre              text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
#variable_conflict use_column
DECLARE
  c_max_intentos CONSTANT integer  := 5;
  c_bloqueo      CONSTANT interval := interval '15 minutes';
  v_email        text := lower(btrim(COALESCE(p_email, '')));
  v              record;
  v_bloquear     boolean;
BEGIN
  SELECT u.id          AS usuario_id,
         u.id_publico  AS usuario_id_publico,
         u.taller_id   AS taller_id,
         t.id_publico  AS taller_id_publico,
         u.rol         AS rol,
         u.nombre      AS nombre,
         u.activo      AS usuario_activo,
         t.activo      AS taller_activo,
         c.hash_contrasena,
         c.intentos_fallidos,
         c.bloqueado_hasta
  INTO   v
  FROM   usuario u
  JOIN   taller t             ON t.id = u.taller_id
  JOIN   usuario_credencial c ON c.usuario_id = u.id
  WHERE  u.email = v_email
  FOR UPDATE OF c;

  IF NOT FOUND THEN
    PERFORM crypt(COALESCE(p_contrasena, ''), gen_salt('bf', 10));
    PERFORM fn_registrar_auditoria(NULL, NULL, 'LOGIN_FALLIDO', NULL, NULL, NULL, NULL, 'fallo');
    RETURN QUERY SELECT false, NULL::bigint, NULL::uuid, NULL::bigint, NULL::uuid, NULL::tipo_rol_usuario, NULL::text;
    RETURN;
  END IF;

  IF NOT v.usuario_activo
  OR NOT v.taller_activo
  OR (v.bloqueado_hasta IS NOT NULL AND v.bloqueado_hasta > now()) THEN
    PERFORM crypt(COALESCE(p_contrasena, ''), gen_salt('bf', 10));
    PERFORM fn_registrar_auditoria(v.taller_id, v.usuario_id, 'LOGIN_FALLIDO', NULL, NULL, NULL, NULL, 'denegado');
    RETURN QUERY SELECT false, NULL::bigint, NULL::uuid, NULL::bigint, NULL::uuid, NULL::tipo_rol_usuario, NULL::text;
    RETURN;
  END IF;

  IF COALESCE(v.hash_contrasena = crypt(p_contrasena, v.hash_contrasena), false) THEN
    UPDATE usuario_credencial c
    SET    intentos_fallidos = 0,
           bloqueado_hasta   = NULL,
           ultimo_login_en   = now()
    WHERE  c.usuario_id = v.usuario_id;

    PERFORM fn_registrar_auditoria(v.taller_id, v.usuario_id, 'LOGIN', NULL, NULL, NULL, NULL, 'exito');
    RETURN QUERY SELECT true, v.usuario_id, v.usuario_id_publico, v.taller_id, v.taller_id_publico, v.rol, v.nombre;
    RETURN;
  END IF;

  v_bloquear := v.intentos_fallidos + 1 >= c_max_intentos;

  UPDATE usuario_credencial c
  SET    intentos_fallidos = CASE WHEN v_bloquear THEN 0 ELSE c.intentos_fallidos + 1 END,
         bloqueado_hasta   = CASE WHEN v_bloquear THEN now() + c_bloqueo ELSE NULL END
  WHERE  c.usuario_id = v.usuario_id;

  PERFORM fn_registrar_auditoria(v.taller_id, v.usuario_id, 'LOGIN_FALLIDO', NULL, NULL, NULL, NULL, 'fallo');
  RETURN QUERY SELECT false, NULL::bigint, NULL::uuid, NULL::bigint, NULL::uuid, NULL::tipo_rol_usuario, NULL::text;
END;
$$;

-- El administrador fija o restablece la contrasena de un usuario de SU taller.
-- Es la unica via para escribir en usuario_credencial desde un rol de grupo.
-- Valida explicitamente rol y taller porque, al ser SECURITY DEFINER con
-- BYPASSRLS, las politicas no la protegen.
CREATE FUNCTION fn_establecer_contrasena(
  p_usuario_id bigint,
  p_contrasena text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_taller_id bigint := fn_contexto_taller_id();
BEGIN
  IF fn_contexto_rol() <> 'taller_admin' OR v_taller_id IS NULL THEN
    RAISE EXCEPTION 'operacion reservada al administrador con contexto de taller'
      USING ERRCODE = 'RE006';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id = p_usuario_id AND u.taller_id = v_taller_id) THEN
    RAISE EXCEPTION 'el usuario % no existe o no es visible', p_usuario_id
      USING ERRCODE = 'RE009';
  END IF;

  -- 72 bytes es el limite de bcrypt: una contrasena mas larga se truncaria
  -- en silencio, por eso se rechaza.
  IF p_contrasena IS NULL OR char_length(p_contrasena) < 8 OR octet_length(p_contrasena) > 72 THEN
    RAISE EXCEPTION 'la contrasena debe tener entre 8 caracteres y 72 bytes'
      USING ERRCODE = 'RE011';
  END IF;

  INSERT INTO usuario_credencial AS c (usuario_id, hash_contrasena)
  VALUES (p_usuario_id, crypt(p_contrasena, gen_salt('bf', 10)))
  ON CONFLICT (usuario_id) DO UPDATE
    SET hash_contrasena   = EXCLUDED.hash_contrasena,
        intentos_fallidos = 0,
        bloqueado_hasta   = NULL;

  -- usuario_credencial no tiene trigger de auditoria (jamas debe copiarse un
  -- hash); se deja constancia del hecho, sin datos.
  PERFORM fn_registrar_auditoria(v_taller_id, fn_contexto_usuario_id(), 'UPDATE',
                                 'usuario_credencial', p_usuario_id, NULL, NULL, 'exito');
END;
$$;

-- =============================================================================
-- 7. PRIVACIDAD
-- =============================================================================

-- Anonimizacion irreversible de un titular y de sus vehiculos.
-- No tiene EXECUTE para los roles de grupo: la invocan
-- fn_solicitar_supresion_titular y fn_anonimizar_vencidos.
--   * titular: nombre, contacto e identificador HMAC a NULL.
--   * vehiculos: patente y VIN a NULL (marca, modelo, anio y motor se
--     conservan como dato tecnico).
--   * sesiones, fallas y cotizaciones no se tocan: la trazabilidad tecnica y
--     financiera queda sin relacion con la persona.
CREATE FUNCTION fn_anonimizar_titular(p_titular_id bigint) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_titular titular;
BEGIN
  SELECT t.* INTO v_titular
  FROM   titular t
  WHERE  t.id = p_titular_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'el titular % no existe', p_titular_id USING ERRCODE = 'RE009';
  END IF;

  IF v_titular.estado_tratamiento = 'anonimizado' THEN
    RETURN;
  END IF;

  UPDATE titular t
  SET    nombre             = NULL,
         telefono           = NULL,
         email              = NULL,
         identificador_hmac = NULL,
         estado_tratamiento = 'anonimizado',
         bloqueado_hasta    = NULL,
         anonimizado_en     = now()
  WHERE  t.id = p_titular_id;

  UPDATE vehiculo v
  SET    patente        = NULL,
         vin            = NULL,
         anonimizado_en = now()
  WHERE  v.titular_id = p_titular_id
  AND    v.taller_id  = v_titular.taller_id
  AND    v.anonimizado_en IS NULL;

  UPDATE consentimiento_titular c
  SET    revocado_en = now()
  WHERE  c.titular_id = p_titular_id
  AND    c.revocado_en IS NULL;

  UPDATE solicitud_derecho_titular s
  SET    estado      = 'resuelta',
         resuelta_en = now()
  WHERE  s.titular_id = p_titular_id
  AND    s.tipo = 'supresion'
  AND    s.estado IN ('recibida', 'en_proceso');
END;
$$;

-- Solicitud de supresion con retencion legal.
--   * Si la ultima atencion no cancelada del titular esta dentro del plazo
--     retencion_anios del taller: pasa a 'bloqueado' hasta que venza el plazo.
--   * Si no hay retencion pendiente: se anonimiza de inmediato.
-- Deja registrada la solicitud. Devuelve el estado resultante.
CREATE FUNCTION fn_solicitar_supresion_titular(p_titular_id bigint) RETURNS tipo_estado_tratamiento
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_taller_id       bigint := fn_contexto_taller_id();
  v_titular         titular;
  v_retencion_anios smallint;
  v_ultima_atencion timestamptz;
  v_limite          date;
BEGIN
  IF fn_contexto_rol() <> 'taller_admin' OR v_taller_id IS NULL THEN
    RAISE EXCEPTION 'operacion reservada al administrador con contexto de taller'
      USING ERRCODE = 'RE006';
  END IF;

  SELECT t.* INTO v_titular
  FROM   titular t
  WHERE  t.id = p_titular_id
  AND    t.taller_id = v_taller_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'el titular % no existe o no es visible', p_titular_id
      USING ERRCODE = 'RE009';
  END IF;

  IF v_titular.estado_tratamiento = 'anonimizado' THEN
    RETURN 'anonimizado';
  END IF;

  IF NOT EXISTS (
       SELECT 1
       FROM   solicitud_derecho_titular s
       WHERE  s.titular_id = p_titular_id
       AND    s.tipo = 'supresion'
       AND    s.estado IN ('recibida', 'en_proceso')
  ) THEN
    INSERT INTO solicitud_derecho_titular (taller_id, titular_id, tipo, estado, usuario_responsable_id)
    VALUES (v_taller_id, p_titular_id, 'supresion', 'en_proceso', fn_contexto_usuario_id());
  END IF;

  SELECT tc.retencion_anios INTO v_retencion_anios
  FROM   taller_configuracion tc
  WHERE  tc.taller_id = v_taller_id;

  SELECT max(s.iniciada_en) INTO v_ultima_atencion
  FROM   sesion_diagnostico s
  JOIN   vehiculo v ON v.id = s.vehiculo_id AND v.taller_id = s.taller_id
  WHERE  v.titular_id = p_titular_id
  AND    v.taller_id  = v_taller_id
  AND    s.estado <> 'cancelado';

  v_limite := (v_ultima_atencion + make_interval(years => COALESCE(v_retencion_anios, 0)))::date;

  IF v_limite IS NOT NULL AND v_limite > current_date THEN
    UPDATE titular t
    SET    estado_tratamiento = 'bloqueado',
           bloqueado_hasta    = v_limite
    WHERE  t.id = p_titular_id;
    RETURN 'bloqueado';
  END IF;

  PERFORM fn_anonimizar_titular(p_titular_id);
  RETURN 'anonimizado';
END;
$$;

-- Proceso periodico: anonimiza los titulares cuyo bloqueo vencio. Devuelve
-- cuantos proceso. Lo ejecuta un job externo como app_owner (la imagen
-- postgres:16 no trae pg_cron). SKIP LOCKED: dos ejecuciones simultaneas no
-- se bloquean entre si.
CREATE FUNCTION fn_anonimizar_vencidos() RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_id       bigint;
  v_cantidad integer := 0;
BEGIN
  FOR v_id IN
    SELECT t.id
    FROM   titular t
    WHERE  t.estado_tratamiento = 'bloqueado'
    AND    t.bloqueado_hasta <= current_date
    ORDER  BY t.id
    FOR UPDATE SKIP LOCKED
  LOOP
    PERFORM fn_anonimizar_titular(v_id);
    v_cantidad := v_cantidad + 1;
  END LOOP;
  RETURN v_cantidad;
END;
$$;

-- =============================================================================
-- 8. TRIGGERS
-- (los triggers BEFORE de una misma tabla se ejecutan en orden alfabetico de
--  nombre; los de este esquema son independientes entre si)
-- =============================================================================

-- actualizado_en
CREATE TRIGGER trg_taller_marcar_actualizado
  BEFORE UPDATE ON taller FOR EACH ROW EXECUTE FUNCTION fn_trg_marcar_actualizado();
CREATE TRIGGER trg_taller_configuracion_marcar_actualizado
  BEFORE UPDATE ON taller_configuracion FOR EACH ROW EXECUTE FUNCTION fn_trg_marcar_actualizado();
CREATE TRIGGER trg_usuario_marcar_actualizado
  BEFORE UPDATE ON usuario FOR EACH ROW EXECUTE FUNCTION fn_trg_marcar_actualizado();
CREATE TRIGGER trg_usuario_credencial_marcar_actualizado
  BEFORE UPDATE ON usuario_credencial FOR EACH ROW EXECUTE FUNCTION fn_trg_marcar_actualizado();
CREATE TRIGGER trg_titular_marcar_actualizado
  BEFORE UPDATE ON titular FOR EACH ROW EXECUTE FUNCTION fn_trg_marcar_actualizado();
CREATE TRIGGER trg_solicitud_derecho_titular_marcar_actualizado
  BEFORE UPDATE ON solicitud_derecho_titular FOR EACH ROW EXECUTE FUNCTION fn_trg_marcar_actualizado();
CREATE TRIGGER trg_repuesto_marcar_actualizado
  BEFORE UPDATE ON repuesto FOR EACH ROW EXECUTE FUNCTION fn_trg_marcar_actualizado();
CREATE TRIGGER trg_vehiculo_marcar_actualizado
  BEFORE UPDATE ON vehiculo FOR EACH ROW EXECUTE FUNCTION fn_trg_marcar_actualizado();
CREATE TRIGGER trg_dispositivo_diagnostico_marcar_actualizado
  BEFORE UPDATE ON dispositivo_diagnostico FOR EACH ROW EXECUTE FUNCTION fn_trg_marcar_actualizado();
CREATE TRIGGER trg_sesion_diagnostico_marcar_actualizado
  BEFORE UPDATE ON sesion_diagnostico FOR EACH ROW EXECUTE FUNCTION fn_trg_marcar_actualizado();
CREATE TRIGGER trg_cotizacion_marcar_actualizado
  BEFORE UPDATE ON cotizacion FOR EACH ROW EXECUTE FUNCTION fn_trg_marcar_actualizado();

-- version (control optimista)
CREATE TRIGGER trg_sesion_diagnostico_incrementar_version
  BEFORE UPDATE ON sesion_diagnostico FOR EACH ROW EXECUTE FUNCTION fn_trg_incrementar_version();
CREATE TRIGGER trg_cotizacion_incrementar_version
  BEFORE UPDATE ON cotizacion FOR EACH ROW EXECUTE FUNCTION fn_trg_incrementar_version();

-- estados
CREATE TRIGGER trg_sesion_diagnostico_validar_transicion
  BEFORE UPDATE OF estado ON sesion_diagnostico
  FOR EACH ROW EXECUTE FUNCTION fn_trg_sesion_validar_transicion();

-- cotizacion
CREATE TRIGGER trg_cotizacion_preparar
  BEFORE INSERT ON cotizacion FOR EACH ROW EXECUTE FUNCTION fn_trg_cotizacion_preparar();
CREATE TRIGGER trg_cotizacion_validar_actualizacion
  BEFORE UPDATE ON cotizacion FOR EACH ROW EXECUTE FUNCTION fn_trg_cotizacion_validar_actualizacion();
CREATE TRIGGER trg_cotizacion_detalle_validar
  BEFORE INSERT OR UPDATE OR DELETE ON cotizacion_detalle
  FOR EACH ROW EXECUTE FUNCTION fn_trg_cotizacion_detalle_validar();

-- auditoria: inmutabilidad
CREATE TRIGGER trg_auditoria_operacion_inmutable_fila
  BEFORE UPDATE OR DELETE ON auditoria_operacion
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditoria_inmutable();
CREATE TRIGGER trg_auditoria_operacion_inmutable_truncate
  BEFORE TRUNCATE ON auditoria_operacion
  FOR EACH STATEMENT EXECUTE FUNCTION fn_trg_auditoria_inmutable();

-- auditoria: captura. Los argumentos son las columnas EXCLUIDAS (datos
-- personales). usuario_credencial no tiene trigger de auditoria.
CREATE TRIGGER trg_taller_auditar
  AFTER INSERT OR UPDATE OR DELETE ON taller
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar();
CREATE TRIGGER trg_taller_configuracion_auditar
  AFTER INSERT OR UPDATE OR DELETE ON taller_configuracion
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar();
CREATE TRIGGER trg_usuario_auditar
  AFTER INSERT OR UPDATE OR DELETE ON usuario
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar('email', 'nombre');
CREATE TRIGGER trg_titular_auditar
  AFTER INSERT OR UPDATE OR DELETE ON titular
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar('nombre', 'telefono', 'email', 'identificador_hmac');
CREATE TRIGGER trg_consentimiento_titular_auditar
  AFTER INSERT OR UPDATE OR DELETE ON consentimiento_titular
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar();
CREATE TRIGGER trg_solicitud_derecho_titular_auditar
  AFTER INSERT OR UPDATE OR DELETE ON solicitud_derecho_titular
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar();
CREATE TRIGGER trg_vehiculo_auditar
  AFTER INSERT OR UPDATE OR DELETE ON vehiculo
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar('patente', 'vin');
CREATE TRIGGER trg_dispositivo_diagnostico_auditar
  AFTER INSERT OR UPDATE OR DELETE ON dispositivo_diagnostico
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar();
CREATE TRIGGER trg_sesion_diagnostico_auditar
  AFTER INSERT OR UPDATE OR DELETE ON sesion_diagnostico
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar();
CREATE TRIGGER trg_falla_sesion_auditar
  AFTER INSERT OR UPDATE OR DELETE ON falla_sesion
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar('freeze_frame');
CREATE TRIGGER trg_cotizacion_auditar
  AFTER INSERT OR UPDATE OR DELETE ON cotizacion
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar();
CREATE TRIGGER trg_cotizacion_detalle_auditar
  AFTER INSERT OR UPDATE OR DELETE ON cotizacion_detalle
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar();
-- Precio maestro: cambio critico que afecta a todos los talleres.
CREATE TRIGGER trg_repuesto_auditar
  AFTER INSERT OR UPDATE OR DELETE ON repuesto
  FOR EACH ROW EXECUTE FUNCTION fn_trg_auditar();

-- =============================================================================
-- 9. COMENTARIOS DE FUNCIONES (antes del cambio de propietario: COMMENT exige ser el dueno)
-- =============================================================================
COMMENT ON FUNCTION fn_contexto_taller_id() IS 'Taller de la peticion (app.taller_id). NULL si no hay contexto.';
COMMENT ON FUNCTION fn_contexto_usuario_id() IS 'Usuario de la peticion (app.usuario_id). NULL si no hay contexto.';
COMMENT ON FUNCTION fn_contexto_rol() IS 'Rol efectivo de la peticion: el de SET LOCAL ROLE o, si no hay, el de sesion.';
COMMENT ON FUNCTION fn_contexto_ip_origen() IS 'IP de origen (app.ip_origen). NULL si falta o esta mal formada.';
COMMENT ON FUNCTION fn_trg_marcar_actualizado() IS 'Trigger: mantiene actualizado_en.';
COMMENT ON FUNCTION fn_trg_incrementar_version() IS 'Trigger: incrementa version en cada UPDATE (control optimista).';
COMMENT ON FUNCTION fn_registrar_auditoria(bigint, bigint, tipo_operacion_auditoria, text, bigint, jsonb, jsonb, tipo_resultado_auditoria) IS 'Unico punto de escritura en auditoria_operacion.';
COMMENT ON FUNCTION fn_trg_auditar() IS 'Trigger generico de auditoria (SECURITY DEFINER). Sus argumentos son las columnas sensibles a excluir.';
COMMENT ON FUNCTION fn_trg_auditoria_inmutable() IS 'Trigger: rechaza UPDATE, DELETE y TRUNCATE sobre la auditoria.';
COMMENT ON FUNCTION fn_trg_sesion_validar_transicion() IS 'Trigger: valida las transiciones de estado de la sesion y fija sus timestamps.';
COMMENT ON FUNCTION fn_cambiar_estado_sesion(bigint, tipo_estado_atencion, integer) IS 'Cambia el estado de una sesion con bloqueo pesimista (sesion -> cotizacion) y version opcional.';
COMMENT ON FUNCTION fn_trg_cotizacion_preparar() IS 'Trigger: toda cotizacion nace como borrador; asigna revision y moneda.';
COMMENT ON FUNCTION fn_trg_cotizacion_validar_actualizacion() IS 'Trigger: inmutabilidad de la cotizacion cerrada y calculo del total al cerrar.';
COMMENT ON FUNCTION fn_trg_cotizacion_detalle_validar() IS 'Trigger: rechaza cambios en el detalle de una cotizacion cerrada y llena el snapshot de precios.';
COMMENT ON FUNCTION fn_crear_cotizacion(bigint, uuid) IS 'Crea un borrador de cotizacion de forma idempotente por clave_idempotencia.';
COMMENT ON FUNCTION fn_cerrar_cotizacion(bigint, integer) IS 'Cierra una cotizacion: congela total y cerrada_en, la marca vigente y apaga la anterior.';
COMMENT ON FUNCTION fn_autenticar_usuario(text, text) IS 'Login de prototipo con crypt() (SECURITY DEFINER). Nunca devuelve el hash; registra LOGIN y LOGIN_FALLIDO.';
COMMENT ON FUNCTION fn_establecer_contrasena(bigint, text) IS 'El administrador fija la contrasena de un usuario de su taller (SECURITY DEFINER).';
COMMENT ON FUNCTION fn_anonimizar_titular(bigint) IS 'Anonimizacion irreversible de un titular y sus vehiculos (SECURITY DEFINER, sin EXECUTE para roles de grupo).';
COMMENT ON FUNCTION fn_solicitar_supresion_titular(bigint) IS 'Supresion con retencion legal: bloquea o anonimiza segun el plazo del taller (SECURITY DEFINER).';
COMMENT ON FUNCTION fn_anonimizar_vencidos() IS 'Proceso periodico: anonimiza los titulares con bloqueo vencido (SECURITY DEFINER).';

-- =============================================================================
-- 10. PROPIETARIO DE LAS FUNCIONES SECURITY DEFINER
-- Va al final: CREATE TRIGGER exige que quien lo crea tenga EXECUTE sobre
-- la funcion, y app_owner lo tiene mientras es su propietario.
-- Requisitos resueltos en V000: app_owner es miembro de app_funciones (SET
-- TRUE) y app_funciones tiene CREATE en el esquema.
-- =============================================================================
ALTER FUNCTION fn_trg_auditar()                         OWNER TO app_funciones;
ALTER FUNCTION fn_autenticar_usuario(text, text)        OWNER TO app_funciones;
ALTER FUNCTION fn_establecer_contrasena(bigint, text)   OWNER TO app_funciones;
ALTER FUNCTION fn_anonimizar_titular(bigint)            OWNER TO app_funciones;
ALTER FUNCTION fn_solicitar_supresion_titular(bigint)   OWNER TO app_funciones;
ALTER FUNCTION fn_anonimizar_vencidos()                 OWNER TO app_funciones;

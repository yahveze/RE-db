-- =============================================================================
-- Flujo real de una atencion, para las semillas. No se ejecuta solo: lo incluye
-- 03_operacion.sql con \ir, dentro de una transaccion que ya fijo
--   SET LOCAL ROLE taller_mecanico, app.taller_id y app.usuario_id,
-- y que dejo en la variable 'semilla.atenciones' un arreglo JSON con una
-- entrada por atencion:
--
--   patente     vehiculo (visible para el mecanico)
--   mac         dispositivo; si falta, el ingreso es manual
--   km          kilometraje
--   hace        antiguedad de la sesion (interval), p. ej. "40 days"
--   fallas      [{codigo, severidad?, freeze_frame?}]  (severidad por defecto:
--               la sugerida por el catalogo)
--   revisiones  [[{repuesto, cantidad}]]  cotizaciones que se CIERRAN, en orden
--   borrador    [{repuesto, cantidad}]    cotizacion que queda abierta
--   final       pendiente | cotizado | completado | cancelado
--
-- Nada se inserta en estado final: cada atencion nace 'pendiente' y avanza con
-- fn_crear_cotizacion, fn_cerrar_cotizacion y fn_cambiar_estado_sesion, con los
-- privilegios y las politicas del mecanico. Solo iniciada_en se antedata (el
-- mecanico tiene INSERT sobre esa columna); los cierres llevan la hora de carga.
-- =============================================================================
DO $flujo$
DECLARE
  v_taller_id      bigint := fn_contexto_taller_id();
  v_usuario_id     bigint := fn_contexto_usuario_id();
  v_atencion       jsonb;
  v_lineas         jsonb;
  v_numero         bigint;
  v_final          tipo_estado_atencion;
  v_vehiculo_id    bigint;
  v_dispositivo_id bigint;
  v_sesion_id      bigint;
  v_cotizacion     cotizacion;
  v_filas          bigint;
BEGIN
  IF v_taller_id IS NULL OR v_usuario_id IS NULL THEN
    RAISE EXCEPTION 'flujo_atencion: falta el contexto de taller o de usuario';
  END IF;

  FOR v_atencion IN
    SELECT a.valor
    FROM   jsonb_array_elements(current_setting('semilla.atenciones')::jsonb) WITH ORDINALITY AS a (valor, orden)
    ORDER  BY a.orden
  LOOP
    v_final := (v_atencion ->> 'final')::tipo_estado_atencion;

    IF v_final IN ('cotizado', 'completado') AND jsonb_array_length(COALESCE(v_atencion -> 'revisiones', '[]')) = 0 THEN
      RAISE EXCEPTION 'flujo_atencion: % exige al menos una revision cerrada (patente %)',
        v_final, v_atencion ->> 'patente';
    END IF;

    SELECT v.id INTO STRICT v_vehiculo_id
    FROM   vehiculo v
    WHERE  v.patente = v_atencion ->> 'patente';

    v_dispositivo_id := NULL;
    IF v_atencion ? 'mac' THEN
      SELECT d.id INTO STRICT v_dispositivo_id
      FROM   dispositivo_diagnostico d
      WHERE  d.mac = (v_atencion ->> 'mac')::macaddr;
    END IF;

    -- 1. Sesion (nace 'pendiente') y sus fallas.
    INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, dispositivo_id,
                                    metodo_ingreso, kilometraje, iniciada_en)
    VALUES (v_taller_id, v_vehiculo_id, v_usuario_id, v_dispositivo_id,
            CASE WHEN v_dispositivo_id IS NULL THEN 'manual' ELSE 'obd_bluetooth' END::tipo_metodo_ingreso,
            (v_atencion ->> 'km')::integer,
            now() - (v_atencion ->> 'hace')::interval)
    RETURNING id INTO v_sesion_id;

    INSERT INTO falla_sesion (sesion_id, dtc_id, taller_id, severidad, freeze_frame)
    SELECT v_sesion_id, d.id, v_taller_id,
           COALESCE((f.valor ->> 'severidad')::tipo_severidad, d.severidad_sugerida),
           f.valor -> 'freeze_frame'
    FROM   jsonb_array_elements(v_atencion -> 'fallas') AS f (valor)
    JOIN   dtc_catalogo d ON d.codigo = f.valor ->> 'codigo';

    GET DIAGNOSTICS v_filas = ROW_COUNT;
    IF v_filas = 0 OR v_filas <> jsonb_array_length(v_atencion -> 'fallas') THEN
      RAISE EXCEPTION 'flujo_atencion: algun DTC no existe en el catalogo (patente %)', v_atencion ->> 'patente';
    END IF;

    -- 2. Revisiones cerradas. La primera lleva la sesion a 'cotizado'.
    FOR v_lineas, v_numero IN
      SELECT r.valor, r.orden
      FROM   jsonb_array_elements(COALESCE(v_atencion -> 'revisiones', '[]')) WITH ORDINALITY AS r (valor, orden)
      ORDER  BY r.orden
    LOOP
      v_cotizacion := fn_crear_cotizacion(
        v_sesion_id, md5(format('semilla:%s:%s:%s', v_taller_id, v_sesion_id, v_numero))::uuid);

      INSERT INTO cotizacion_detalle (cotizacion_id, repuesto_id, taller_id, cantidad)
      SELECT v_cotizacion.id, r.id, v_taller_id, (l.valor ->> 'cantidad')::integer
      FROM   jsonb_array_elements(v_lineas) AS l (valor)
      JOIN   repuesto r ON r.codigo_fabricante = l.valor ->> 'repuesto';

      GET DIAGNOSTICS v_filas = ROW_COUNT;
      IF v_filas <> jsonb_array_length(v_lineas) THEN
        RAISE EXCEPTION 'flujo_atencion: algun repuesto no existe (patente %, revision %)',
          v_atencion ->> 'patente', v_numero;
      END IF;

      v_cotizacion := fn_cerrar_cotizacion(v_cotizacion.id);

      IF v_numero = 1 THEN
        PERFORM fn_cambiar_estado_sesion(v_sesion_id, 'cotizado');
      END IF;
    END LOOP;

    -- 3. Borrador: cotizacion abierta, sin total.
    IF v_atencion ? 'borrador' THEN
      v_cotizacion := fn_crear_cotizacion(
        v_sesion_id, md5(format('semilla:%s:%s:borrador', v_taller_id, v_sesion_id))::uuid);

      INSERT INTO cotizacion_detalle (cotizacion_id, repuesto_id, taller_id, cantidad)
      SELECT v_cotizacion.id, r.id, v_taller_id, (l.valor ->> 'cantidad')::integer
      FROM   jsonb_array_elements(v_atencion -> 'borrador') AS l (valor)
      JOIN   repuesto r ON r.codigo_fabricante = l.valor ->> 'repuesto';

      GET DIAGNOSTICS v_filas = ROW_COUNT;
      IF v_filas <> jsonb_array_length(v_atencion -> 'borrador') THEN
        RAISE EXCEPTION 'flujo_atencion: algun repuesto del borrador no existe (patente %)', v_atencion ->> 'patente';
      END IF;
    END IF;

    -- 4. Estado terminal.
    IF v_final IN ('completado', 'cancelado') THEN
      PERFORM fn_cambiar_estado_sesion(v_sesion_id, v_final);
    END IF;
  END LOOP;
END;
$flujo$;

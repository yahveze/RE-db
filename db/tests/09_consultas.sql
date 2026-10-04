-- =============================================================================
-- 09 - Contrato de las consultas del frontend (docs/consultas.md).
-- El resultado de cada sentencia preparada se guarda con
--     CREATE TEMP TABLE x AS EXECUTE q_...(...)
-- y se compara con un calculo independiente. Las tablas temporales conservan el
-- orden de insercion (ctid), que es el orden que devolvio la consulta.
-- =============================================================================
\ir incluir/inicio.sql
\echo '### 09 Consultas'
\o /dev/null

\ir incluir/rol_plataforma.sql
-- Solo para esta prueba (se revierte con el ROLLBACK): los roles de taller no
-- tienen TEMPORARY sobre la base y lo necesitan para guardar los resultados.
GRANT TEMPORARY ON DATABASE :"DBNAME" TO taller_admin, taller_mecanico, taller_auditor;

SELECT s.id_publico AS ses_morning FROM sesion_diagnostico s JOIN vehiculo v ON v.id = s.vehiculo_id WHERE v.patente = 'DFGH21' \gset
SELECT s.id_publico AS ses_corolla FROM sesion_diagnostico s JOIN vehiculo v ON v.id = s.vehiculo_id WHERE v.patente = 'XK4521' \gset
SELECT s.id_publico AS ses_u0100 FROM sesion_diagnostico s JOIN vehiculo v ON v.id = s.vehiculo_id
WHERE  v.patente = 'GHJK34' ORDER BY s.iniciada_en DESC LIMIT 1 \gset
SELECT s.id AS ses_yaris_id, s.id_publico AS ses_yaris FROM sesion_diagnostico s JOIN vehiculo v ON v.id = s.vehiculo_id
WHERE  v.patente = 'GHJK34' ORDER BY s.iniciada_en LIMIT 1 \gset
SELECT s.id_publico AS ses_oculta FROM sesion_diagnostico s JOIN vehiculo v ON v.id = s.vehiculo_id
JOIN   titular t ON t.id = v.titular_id WHERE t.estado_tratamiento = 'bloqueado' \gset
SELECT v.id_publico AS veh_hilux FROM vehiculo v WHERE v.taller_id = :taller_1 AND v.patente = 'LPRS56' \gset
SELECT v.id_publico AS veh_morning FROM vehiculo v WHERE v.patente = 'DFGH21' \gset
SELECT mo.id AS modelo_morning_id FROM modelo_vehiculo mo WHERE mo.nombre = 'Morning' \gset
SELECT mo.id_publico AS modelo_hilux FROM modelo_vehiculo mo WHERE mo.nombre = 'Hilux' \gset
SELECT r.id AS rep_ngk_id FROM repuesto r WHERE r.codigo_fabricante = 'ILKAR7B11' \gset

-- ================================================================ historial
\ir incluir/rol_mecanico_1.sql
CREATE TEMP TABLE p1 AS EXECUTE q_historial(5);
SELECT iniciada_en AS c_ts, id_publico AS c_id FROM p1 ORDER BY ctid DESC LIMIT 1 \gset
CREATE TEMP TABLE p2 AS EXECUTE q_historial_siguiente(:'c_ts', :'c_id', 5);
SELECT iniciada_en AS c_ts, id_publico AS c_id FROM p2 ORDER BY ctid DESC LIMIT 1 \gset
CREATE TEMP TABLE p3 AS EXECUTE q_historial_siguiente(:'c_ts', :'c_id', 5);
SELECT iniciada_en AS c_ts, id_publico AS c_id FROM p3 ORDER BY ctid DESC LIMIT 1 \gset
CREATE TEMP TABLE p4 AS EXECUTE q_historial_siguiente(:'c_ts', :'c_id', 5);
CREATE TEMP TABLE paginas AS
SELECT 1 AS pagina, ctid AS pos, * FROM p1 UNION ALL SELECT 2, ctid, * FROM p2
UNION ALL SELECT 3, ctid, * FROM p3 UNION ALL SELECT 4, ctid, * FROM p4;

\set prueba 'q_historial: 12 sesiones en paginas de 5, 5, 2 y 0 filas'
SELECT (SELECT count(*) FROM p1) = 5 AND (SELECT count(*) FROM p2) = 5
   AND (SELECT count(*) FROM p3) = 2 AND (SELECT count(*) FROM p4) = 0 AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'q_historial: las paginas no repiten ni omiten sesiones'
SELECT count(*) = 12 AND count(DISTINCT id_publico) = 12
   AND (SELECT count(*) FROM sesion_diagnostico s WHERE s.id_publico NOT IN (SELECT id_publico FROM paginas)) = 0 AS ok
FROM   paginas \gset
\ir incluir/afirmar.sql

\set prueba 'q_historial: el orden concatenado de las paginas es iniciada_en DESC, id DESC'
SELECT (SELECT array_agg(id_publico ORDER BY pagina, pos) FROM paginas)
     = (SELECT array_agg(s.id_publico ORDER BY s.iniciada_en DESC, s.id DESC) FROM sesion_diagnostico s) AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'q_historial: fallas, severidad maxima y total vigente coinciden con las tablas'
SELECT bool_and(p.fallas = (SELECT count(*) FROM falla_sesion f WHERE f.sesion_id = s.id)
            AND p.severidad_maxima = (SELECT max(f.severidad) FROM falla_sesion f WHERE f.sesion_id = s.id)
            AND p.cotizacion_total IS NOT DISTINCT FROM (SELECT c.total FROM cotizacion c WHERE c.sesion_id = s.id AND c.vigente)) AS ok
FROM   paginas p JOIN sesion_diagnostico s ON s.id_publico = p.id_publico \gset
\ir incluir/afirmar.sql

\set prueba 'q_historial (mecanico): 2 sesiones con el vehiculo oculto llegan con sus columnas en NULL'
SELECT count(*) = 2 AND bool_and(vehiculo_patente IS NULL AND modelo_nombre IS NULL AND marca_nombre IS NULL) AS ok
FROM   paginas WHERE vehiculo_id_publico IS NULL \gset
\ir incluir/afirmar.sql

CREATE TEMP TABLE h_estado AS EXECUTE q_historial_estado('cotizado', 50);
\set prueba 'q_historial: el filtro de estado devuelve solo ese estado (3 cotizadas)'
SELECT count(*) = 3 AND bool_and(estado = 'cotizado') AS ok FROM h_estado \gset
\ir incluir/afirmar.sql

-- Paginacion con filtro de estado: las 4 completadas en paginas de 3 y 1.
CREATE TEMP TABLE c1 AS EXECUTE q_historial_estado('completado', 3);
SELECT iniciada_en AS c_ts, id_publico AS c_id FROM c1 ORDER BY ctid DESC LIMIT 1 \gset
CREATE TEMP TABLE c2 AS EXECUTE q_historial_estado_siguiente('completado', :'c_ts', :'c_id', 3);
\set prueba 'q_historial_estado y _siguiente: paginan un estado sin repetir ni omitir (4 completadas en 3 + 1)'
SELECT (SELECT count(*) FROM c1) = 3 AND (SELECT count(*) FROM c2) = 1
   AND (SELECT count(DISTINCT id_publico) FROM (SELECT * FROM c1 UNION ALL SELECT * FROM c2) x) = 4
   AND (SELECT bool_and(estado = 'completado') FROM (SELECT * FROM c1 UNION ALL SELECT * FROM c2) x)
   AND (SELECT max(iniciada_en) FROM c2) < (SELECT min(iniciada_en) FROM c1) AS ok \gset
\ir incluir/afirmar.sql

-- Empates: tres sesiones creadas en la misma transaccion comparten iniciada_en.
EXECUTE tx_crear_sesion(:'veh_morning', NULL, 200001, '[{"codigo": "P0300"}]') \gset e1_
EXECUTE tx_crear_sesion(:'veh_morning', NULL, 200002, '[{"codigo": "P0300"}]') \gset e2_
EXECUTE tx_crear_sesion(:'veh_morning', NULL, 200003, '[{"codigo": "P0300"}]') \gset e3_
CREATE TEMP TABLE e1 AS EXECUTE q_historial(1);
SELECT iniciada_en AS c_ts, id_publico AS c_id FROM e1 \gset
CREATE TEMP TABLE e2 AS EXECUTE q_historial_siguiente(:'c_ts', :'c_id', 1);
SELECT iniciada_en AS c_ts, id_publico AS c_id FROM e2 \gset
CREATE TEMP TABLE e3 AS EXECUTE q_historial_siguiente(:'c_ts', :'c_id', 1);
\set prueba 'q_historial: con iniciada_en repetido, el desempate por id no repite ni omite filas'
SELECT count(*) = 3 AND count(DISTINCT x.id_publico) = 3 AND count(DISTINCT x.iniciada_en) = 1
   AND array_agg(x.kilometraje ORDER BY x.n) = ARRAY[200003, 200002, 200001] AS ok
FROM  (SELECT 1 AS n, * FROM e1 UNION ALL SELECT 2, * FROM e2 UNION ALL SELECT 3, * FROM e3) x \gset
\ir incluir/afirmar.sql

CREATE TEMP TABLE hv AS EXECUTE q_historial_vehiculo(:'veh_hilux', 10);
\set prueba 'q_historial_vehiculo: las 2 sesiones de la Hilux, la mas reciente primero'
SELECT count(*) = 2 AND (SELECT array_agg(estado ORDER BY ctid) FROM hv) = ARRAY['cotizado', 'completado']::tipo_estado_atencion[] AS ok
FROM   hv \gset
\ir incluir/afirmar.sql

\ir incluir/rol_auditor_1.sql
CREATE TEMP TABLE h_aud AS EXECUTE q_historial(50);
\set prueba 'q_historial (auditor): ve todos los vehiculos; el anonimizado, sin patente'
SELECT count(*) FILTER (WHERE vehiculo_id_publico IS NULL) = 0
   AND count(*) FILTER (WHERE vehiculo_patente IS NULL) = 1 AS ok
FROM   h_aud \gset
\ir incluir/afirmar.sql

-- =================================================================== matriz
\ir incluir/rol_mecanico_1.sql
CREATE TEMP TABLE m AS EXECUTE q_matriz(:'ses_morning');

\set prueba 'q_matriz (Kia Morning 2015): 7 repuestos, ningun genuino, sin el repuesto no disponible'
SELECT count(*) = 7 AND count(*) FILTER (WHERE perfil = 'genuino') = 0
   AND count(*) FILTER (WHERE codigo_fabricante = 'GEN-INY-02') = 0 AS ok
FROM   m \gset
\ir incluir/afirmar.sql

\set prueba 'q_matriz: un componente de varios DTC aparece una vez, con todos sus codigos y la severidad mas alta'
SELECT bool_and(dtc_codigos = ARRAY['P0201', 'P0300'] AND severidad_maxima = 'alta') AND count(*) = 2 AS ok
FROM   m WHERE componente_nombre = 'Inyector de combustible' \gset
\ir incluir/afirmar.sql

\set prueba 'RN-45 q_matriz: precio_venta = ROUND(precio_referencia * (1 + margen / 100)) y moneda del taller'
SELECT bool_and(m.precio_venta = ROUND(r.precio_referencia * 1.30) AND m.moneda = 'CLP') AS ok
FROM   m JOIN repuesto r ON r.id_publico = m.id_publico \gset
\ir incluir/afirmar.sql

\set prueba 'RN-44 q_matriz: todo repuesto devuelto es compatible con el modelo y el anio del vehiculo'
SELECT bool_and(EXISTS (SELECT 1 FROM compatibilidad_repuesto k
                        WHERE k.repuesto_id = r.id AND k.modelo_vehiculo_id = :modelo_morning_id
                        AND 2015 BETWEEN k.anio_desde AND k.anio_hasta)) AS ok
FROM   m JOIN repuesto r ON r.id_publico = m.id_publico \gset
\ir incluir/afirmar.sql

\set prueba 'RN-44 q_matriz: no falta ningun repuesto disponible y compatible de los componentes de la sesion'
SELECT count(*) = (SELECT count(*) FROM m) AS ok
FROM   repuesto r
WHERE  r.disponible
AND    r.componente_id IN (SELECT dc.componente_id FROM dtc_componente dc JOIN dtc_catalogo d ON d.id = dc.dtc_id
                           WHERE d.codigo IN ('P0201', 'P0300'))
AND    EXISTS (SELECT 1 FROM compatibilidad_repuesto k WHERE k.repuesto_id = r.id
               AND k.modelo_vehiculo_id = :modelo_morning_id AND 2015 BETWEEN k.anio_desde AND k.anio_hasta) \gset
\ir incluir/afirmar.sql

\set prueba 'RN-43 q_matriz: orden por severidad, componente, perfil (genuino, oem, generico), precio e id'
SELECT (SELECT array_agg(id_publico ORDER BY ctid) FROM m)
     = (SELECT array_agg(m.id_publico ORDER BY m.severidad_maxima DESC, m.componente_nombre,
                         CASE m.perfil WHEN 'genuino' THEN 1 WHEN 'oem' THEN 2 ELSE 3 END, m.precio_venta, r.id)
        FROM m JOIN repuesto r ON r.id_publico = m.id_publico) AS ok \gset
\ir incluir/afirmar.sql

CREATE TEMP TABLE m_corolla AS EXECUTE q_matriz(:'ses_corolla');
\set prueba 'RN-44 q_matriz (Corolla 2006): el anio deja solo el generico'
SELECT count(*) = 1 AND bool_and(perfil = 'generico' AND codigo_fabricante = 'GEN-EGR-01') AS ok FROM m_corolla \gset
\ir incluir/afirmar.sql

\set esperado 0
\set prueba 'q_matriz: sesion cuyo unico DTC no tiene componente (U0100): cero filas, sin error'
EXECUTE q_matriz(:'ses_u0100');
\ir incluir/filas.sql
\set prueba 'q_matriz (mecanico): sesion con el vehiculo oculto: cero filas (T-38)'
EXECUTE q_matriz(:'ses_oculta');
\ir incluir/filas.sql

\ir incluir/rol_admin_1.sql
\set prueba 'q_matriz (admin): la misma sesion si tiene matriz, porque el admin ve el vehiculo'
EXECUTE q_matriz(:'ses_oculta');
SELECT :ROW_COUNT > 0 AS ok \gset
\ir incluir/afirmar.sql

-- Rangos solapados (T-29): no deben duplicar repuestos en la matriz.
\ir incluir/rol_plataforma.sql
INSERT INTO compatibilidad_repuesto (repuesto_id, modelo_vehiculo_id, anio_desde, anio_hasta)
VALUES (:rep_ngk_id, :modelo_morning_id, 2014, 2016);
\ir incluir/rol_mecanico_1.sql
CREATE TEMP TABLE m_solapado AS EXECUTE q_matriz(:'ses_morning');
\set prueba 'T-29 q_matriz: dos rangos de compatibilidad solapados no duplican el repuesto'
SELECT count(*) = 7 AND count(DISTINCT id_publico) = 7 AS ok FROM m_solapado \gset
\ir incluir/afirmar.sql

-- ---------------------------------------------------- catalogo por DTC
CREATE TEMP TABLE d1 AS EXECUTE q_repuestos_por_dtc('P0420', NULL, NULL);
CREATE TEMP TABLE d1_hilux AS EXECUTE q_repuestos_por_dtc('P0420', :'modelo_hilux', NULL);
CREATE TEMP TABLE d1_2016 AS EXECUTE q_repuestos_por_dtc('P0420', :'modelo_hilux', 2016);
CREATE TEMP TABLE d1_2019 AS EXECUTE q_repuestos_por_dtc('P0420', :'modelo_hilux', 2019);

\set prueba 'q_repuestos_por_dtc: sin vehiculo equivale a la vista v_dtc_repuesto (solo disponibles)'
SELECT (SELECT count(*) FROM d1)
     = (SELECT count(*) FROM v_dtc_repuesto x JOIN dtc_catalogo d ON d.id = x.dtc_id JOIN repuesto r ON r.id = x.repuesto_id
        WHERE d.codigo = 'P0420' AND r.disponible) AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'q_repuestos_por_dtc: rangos disjuntos; el catalizador Walker sirve a una Hilux 2019 y no a una 2016'
SELECT (SELECT count(*) FROM d1_2016 WHERE codigo_fabricante = '16468') = 0
   AND (SELECT count(*) FROM d1_2019 WHERE codigo_fabricante = '16468') = 1
   AND (SELECT count(*) FROM d1_hilux WHERE codigo_fabricante = '16468') = 1
   AND (SELECT count(*) FROM d1_2016 WHERE marca = 'Hyundai') = 0 AS ok \gset
\ir incluir/afirmar.sql

\set prueba 'v_dtc_repuesto: es exactamente dtc_componente x repuesto por componente'
SELECT (SELECT count(*) FROM v_dtc_repuesto)
     = (SELECT count(*) FROM dtc_componente dc JOIN repuesto r ON r.componente_id = dc.componente_id) AS ok \gset
\ir incluir/afirmar.sql

\ir incluir/rol_mecanico_2.sql
CREATE TEMP TABLE d2 AS EXECUTE q_repuestos_por_dtc('P0420', NULL, NULL);
\set prueba 'RN-45 el mismo catalogo con el margen del taller 2 (45,5 %): mismos repuestos, otros precios'
SELECT count(*) = (SELECT count(*) FROM d1)
   AND bool_and(d2.precio_venta = ROUND(r.precio_referencia * 1.455))
   AND bool_and(d2.precio_venta > d1.precio_venta) AS ok
FROM   d2 JOIN repuesto r ON r.id_publico = d2.id_publico JOIN d1 ON d1.id_publico = d2.id_publico \gset
\ir incluir/afirmar.sql

-- ============================================================ cotizaciones
\ir incluir/rol_mecanico_1.sql
CREATE TEMP TABLE cs AS EXECUTE q_cotizaciones_sesion(:'ses_yaris');
\set prueba 'q_cotizaciones_sesion: 2 revisiones, la mas reciente primero y unica vigente'
SELECT count(*) = 2 AND (SELECT array_agg(numero_revision ORDER BY ctid) FROM cs) = ARRAY[2, 1]
   AND bool_and(vigente = (numero_revision = 2)) AS ok FROM cs \gset
\ir incluir/afirmar.sql
\set prueba 'q_cotizaciones_sesion: en una cotizacion cerrada, total (congelado) = total_calculado (detalle)'
SELECT bool_and(total = total_calculado AND lineas = 2) AS ok FROM cs \gset
\ir incluir/afirmar.sql

CREATE TEMP TABLE cb AS EXECUTE q_cotizaciones_sesion(:'ses_morning');
\set prueba 'q_cotizaciones_sesion: un borrador no tiene total pero si total_calculado'
SELECT count(*) = 1 AND bool_and(total IS NULL AND cerrada_en IS NULL AND NOT vigente AND total_calculado > 0) AS ok FROM cb \gset
\ir incluir/afirmar.sql

SELECT id_publico AS cot_vigente FROM cs WHERE vigente \gset
CREATE TEMP TABLE cd AS EXECUTE q_cotizacion_detalle(:'cot_vigente');
\set prueba 'q_cotizacion_detalle: la suma de subtotales es el total de la cotizacion'
SELECT sum(subtotal) = (SELECT total FROM cs WHERE vigente) AND bool_and(subtotal = cantidad * precio_unitario) AS ok FROM cd \gset
\ir incluir/afirmar.sql

-- ================================================================ dashboard
CREATE TEMP TABLE db AS EXECUTE q_dashboard_resumen(now() - interval '30 days');
CREATE TEMP TABLE dt AS EXECUTE q_dashboard_dtc_frecuentes(now() - interval '90 days', 100);
\ir incluir/rol_plataforma.sql
\set prueba 'q_dashboard_resumen: una fila cuyos conteos coinciden con un calculo independiente'
SELECT (SELECT count(*) FROM db) = 1
   AND d.sesiones_pendientes = (SELECT count(*) FROM sesion_diagnostico WHERE taller_id = :taller_1 AND estado = 'pendiente')
   AND d.sesiones_cotizadas  = (SELECT count(*) FROM sesion_diagnostico WHERE taller_id = :taller_1 AND estado = 'cotizado')
   AND d.sesiones_completadas_periodo = (SELECT count(*) FROM sesion_diagnostico WHERE taller_id = :taller_1
                                         AND estado = 'completado' AND iniciada_en >= now() - interval '30 days')
   AND d.sesiones_canceladas_periodo  = (SELECT count(*) FROM sesion_diagnostico WHERE taller_id = :taller_1
                                         AND estado = 'cancelado' AND iniciada_en >= now() - interval '30 days')
   AND d.sesiones_iniciadas_periodo   = (SELECT count(*) FROM sesion_diagnostico WHERE taller_id = :taller_1
                                         AND iniciada_en >= now() - interval '30 days')
   AND d.moneda = 'CLP' AS ok
FROM   db d \gset
\ir incluir/afirmar.sql

\set prueba 'q_dashboard_resumen: montos y fallas criticas coinciden con un calculo independiente'
SELECT d.monto_cotizado_abierto = (SELECT COALESCE(sum(c.total), 0) FROM cotizacion c JOIN sesion_diagnostico s ON s.id = c.sesion_id
                                   WHERE c.taller_id = :taller_1 AND c.vigente AND s.estado = 'cotizado')
   AND d.monto_completado_periodo = (SELECT COALESCE(sum(c.total), 0) FROM cotizacion c JOIN sesion_diagnostico s ON s.id = c.sesion_id
                                     WHERE c.taller_id = :taller_1 AND c.vigente AND s.estado = 'completado'
                                     AND s.iniciada_en >= now() - interval '30 days')
   AND d.fallas_criticas_abiertas = (SELECT count(*) FROM falla_sesion f JOIN sesion_diagnostico s ON s.id = f.sesion_id
                                     WHERE f.taller_id = :taller_1 AND f.severidad = 'critica' AND s.estado IN ('pendiente', 'cotizado'))
   AND d.monto_cotizado_abierto > 0 AND d.fallas_criticas_abiertas > 0 AS ok
FROM   db d \gset
\ir incluir/afirmar.sql

\set prueba 'q_dashboard_dtc_frecuentes: suma todas las fallas del periodo y ordena por frecuencia y codigo'
SELECT sum(veces) = (SELECT count(*) FROM falla_sesion f JOIN sesion_diagnostico s ON s.id = f.sesion_id
                     WHERE f.taller_id = :taller_1 AND s.iniciada_en >= now() - interval '90 days')
   AND (SELECT array_agg(codigo ORDER BY ctid) FROM dt) = (SELECT array_agg(codigo ORDER BY veces DESC, codigo) FROM dt) AS ok
FROM   dt \gset
\ir incluir/afirmar.sql

RESET ROLE;
SET SESSION AUTHORIZATION app_backend_user;
SET LOCAL ROLE taller_mecanico;
EXECUTE ctx('', '', '', '') \gset ctx_
CREATE TEMP TABLE db0 AS EXECUTE q_dashboard_resumen(now() - interval '30 days');
\set prueba 'q_dashboard_resumen sin contexto: una fila con ceros, no un error'
SELECT count(*) = 1 AND bool_and(sesiones_pendientes = 0 AND sesiones_cotizadas = 0 AND monto_cotizado_abierto = 0
       AND fallas_criticas_abiertas = 0 AND moneda IS NULL) AS ok FROM db0 \gset
\ir incluir/afirmar.sql

-- ================================================= busqueda y otros contratos
\ir incluir/rol_mecanico_1.sql
CREATE TEMP TABLE b1 AS EXECUTE q_buscar_vehiculo_patente('LPRS56');
CREATE TEMP TABLE b2 AS EXECUTE q_buscar_vehiculo_modelo(:'modelo_hilux', 2021, 10);
CREATE TEMP TABLE b3 AS EXECUTE q_buscar_vehiculo_modelo(:'modelo_hilux', 2020, 10);
\set prueba 'q_buscar_vehiculo_patente: una fila con modelo, marca, titular y ultima sesion'
SELECT count(*) = 1 AND bool_and(modelo_nombre = 'Hilux' AND marca_nombre = 'Toyota' AND titular_nombre = 'Juana Pérez Soto'
       AND vin = '8AJFR22G5B4512345' AND ultima_sesion_en IS NOT NULL) AS ok FROM b1 \gset
\ir incluir/afirmar.sql
\set prueba 'q_buscar_vehiculo_modelo: filtra por modelo y anio'
SELECT (SELECT count(*) FROM b2) = 1 AND (SELECT count(*) FROM b3) = 0 AS ok \gset
\ir incluir/afirmar.sql
\set esperado 0
\set prueba 'q_buscar_vehiculo_patente (mecanico): la patente de un titular bloqueado no se encuentra'
EXECUTE q_buscar_vehiculo_patente('BCDF12');
\ir incluir/filas.sql

SELECT t.id_publico AS tit_juana FROM titular t WHERE t.nombre = 'Juana Pérez Soto' \gset
CREATE TEMP TABLE co AS EXECUTE q_consentimientos_titular(:'tit_juana');
\set prueba 'q_consentimientos_titular: activos y revocados, el mas reciente primero'
SELECT count(*) = 3 AND count(*) FILTER (WHERE revocado_en IS NULL) = 2
   AND (SELECT finalidad = 'marketing' AND revocado_en IS NOT NULL FROM co ORDER BY ctid LIMIT 1) AS ok
FROM   co \gset
\ir incluir/afirmar.sql
\ir incluir/rol_plataforma.sql
SELECT t.id_publico AS tit_bloq FROM titular t WHERE t.taller_id = :taller_1 AND t.estado_tratamiento = 'bloqueado' \gset
\ir incluir/rol_mecanico_1.sql
\set esperado 0
\set prueba 'q_consentimientos_titular (mecanico): un titular bloqueado no devuelve filas'
EXECUTE q_consentimientos_titular(:'tit_bloq');
\ir incluir/filas.sql
\ir incluir/rol_auditor_1.sql
\set esperado 2
\set prueba 'q_consentimientos_titular (auditor): si ve los del titular bloqueado'
EXECUTE q_consentimientos_titular(:'tit_bloq');
\ir incluir/filas.sql
\ir incluir/rol_mecanico_1.sql

CREATE TEMP TABLE sd AS EXECUTE q_sesion(:'ses_morning');
\set prueba 'q_sesion: devuelve version, dispositivo y el borrador abierto; sin cotizacion vigente'
SELECT count(*) = 1 AND bool_and(estado = 'pendiente' AND version = 1 AND dispositivo_mac = '00:1d:a5:68:98:8a'
       AND cotizacion_borrador_id_publico IS NOT NULL AND cotizacion_vigente_id_publico IS NULL) AS ok FROM sd \gset
\ir incluir/afirmar.sql

CREATE TEMP TABLE sf AS EXECUTE q_sesion_fallas(:'ses_morning');
\set prueba 'q_sesion_fallas: las mas graves primero'
SELECT (SELECT array_agg(codigo ORDER BY ctid) FROM sf) = ARRAY['P0201', 'P0300'] AS ok \gset
\ir incluir/afirmar.sql

CREATE TEMP TABLE dtc AS EXECUTE q_dtc_buscar('P03', 10);
\set prueba 'q_dtc_buscar: busca por prefijo y cuenta los componentes de cada codigo'
SELECT (SELECT array_agg(codigo ORDER BY ctid) FROM dtc) = ARRAY['P0300', 'P0301', 'P0302', 'P0335']
   AND (SELECT componentes FROM dtc WHERE codigo = 'P0300') = 3 AS ok \gset
\ir incluir/afirmar.sql

CREATE TEMP TABLE cfg AS EXECUTE q_configuracion;
\set prueba 'q_configuracion: una fila con el taller del contexto'
SELECT count(*) = 1 AND bool_and(nombre = 'Taller Mecánico Los Aromos' AND margen_pct = 30.00 AND moneda = 'CLP') AS ok FROM cfg \gset
\ir incluir/afirmar.sql

-- ================================================================ auditoria
\ir incluir/rol_admin_1.sql
CREATE TEMP TABLE a1 AS EXECUTE q_auditoria(NULL, 10);
SELECT ocurrido_en AS c_ts, id AS c_num FROM a1 ORDER BY ctid DESC LIMIT 1 \gset
CREATE TEMP TABLE a2 AS EXECUTE q_auditoria_siguiente(NULL, :'c_ts', :c_num, 10);
\set prueba 'q_auditoria: paginacion por clave sin solapes y en orden descendente'
SELECT (SELECT count(*) FROM a1) = 10 AND (SELECT count(*) FROM a2) = 10
   AND (SELECT count(*) FROM a1 JOIN a2 USING (id)) = 0
   AND (SELECT min(id) FROM a1) > (SELECT max(id) FROM a2)
   AND (SELECT array_agg(id ORDER BY ctid) FROM a1) = (SELECT array_agg(id ORDER BY ocurrido_en DESC, id DESC) FROM a1) AS ok \gset
\ir incluir/afirmar.sql

CREATE TEMP TABLE a3 AS EXECUTE q_auditoria('cotizacion', 100);
-- Las operaciones hechas por la plataforma (sin contexto) tambien figuran en la
-- bitacora del taller, sin usuario: el nombre solo se exige a los roles de taller.
\set prueba 'q_auditoria: el filtro por tabla devuelve solo esa tabla; las operaciones de roles de taller traen el usuario'
SELECT count(*) > 0 AND bool_and(tabla = 'cotizacion')
   AND bool_and(usuario_nombre IS NOT NULL) FILTER (WHERE rol LIKE 'taller\_%') AS ok FROM a3 \gset
\ir incluir/afirmar.sql

ROLLBACK;

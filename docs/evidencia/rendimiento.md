# Rendimiento

Análisis de la medición de la Fase 5. Todas las cifras salen de `fase5_resumen.txt`, `fase5_medidas.txt`
(planes completos) y `fase5_indices.txt` (experimentos), generados por `bash db/perf/run.sh`.

## 1. Cómo se midió

- **Base aparte.** `run.sh` crea `<base>_perf` como copia de la principal, le carga volumen, mide y la
  elimina. La base principal y la suite de pruebas no se tocan.
- **Volumen** (`db/perf/volumen.sql`): 22 talleres, 302.016 sesiones, 604.021 fallas, 338 mil cotizaciones,
  846 mil líneas, 60.411 vehículos, 37.757 titulares y 2 millones de registros de auditoría; catálogo de
  1.000 DTC, 9.042 repuestos y 225.297 compatibilidades. La base ocupa 1,2 GB.
- **Un taller grande y varios chicos.** Se mide el taller grande: 150.000 sesiones (la mitad del total),
  30.000 vehículos y 1.000.000 de registros de auditoría. Las sesiones cubren tres años; pendientes (1.095)
  y cotizadas (822) solo existen entre las de los últimos 20 días.
- **Con el rol real.** Cada medida es `EXPLAIN (ANALYZE, BUFFERS) EXECUTE <sentencia preparada>` con
  `app_backend_user`, `SET LOCAL ROLE` y contexto, es decir, con RLS activo.
- **Caché caliente.** Cada sentencia se ejecuta una vez sin registrar y se mide la segunda.
- **Entorno:** PostgreSQL 16.15 con la configuración por defecto del contenedor (`shared_buffers` 128 MB,
  `work_mem` 4 MB, `random_page_cost` 4), en un equipo de desarrollo con Docker Desktop.

**Qué valor tienen los tiempos.** Son de **una** ejecución en una máquina de desarrollo: sirven para
comparar órdenes de magnitud y formas de plan, no como cifras de capacidad. Lo que sí es estable es la
columna *bloques* (páginas leídas) y la forma del plan.

## 2. Resultados

| Medida | Sentencia | ms | Bloques |
|---|---|---:|---:|
| M01 | `q_historial`, primera página | 0,65 | 379 |
| M02 | `q_historial_siguiente`, tras 75.000 sesiones | 0,49 | 427 |
| M03 | la misma página con `OFFSET 75000` | 74,27 | 4.253 |
| M04 | `q_historial_estado('pendiente')` | 0,49 | 359 |
| M05 | `q_historial_estado_siguiente('completado')`, página profunda | 0,44 | 396 |
| M07–M09 | búsqueda de vehículo por patente, VIN, modelo + año | 0,07–0,11 | 18–32 |
| M10, M11 | `q_sesion`, `q_sesion_fallas` | 0,12 / 0,04 | 27 / 11 |
| M12 | `q_matriz` | 5,14 | 8.576 |
| M13 | `q_repuestos_por_dtc` con modelo y año | 1,48 | 3.033 |
| M14–M16 | cotizaciones de la sesión, detalle, historial del vehículo | 0,05–0,12 | 14–60 |
| M17 | `q_dashboard_resumen` (30 días) | 14,58 | 14.402 |
| M18 | `q_dashboard_dtc_frecuentes` (90 días) | 36,73 | 53.108 |
| M21–M25 | escrituras: crear sesión, cotización, línea, cerrar, cambiar estado | 0,47–1,33 | 30–81 |
| M27, M28 | `q_auditoria`, primera página y tras 500.000 registros | 0,08 / 0,09 | 16 / 7 |
| M31 | `tx_solicitar_supresion` | 1,77 | 148 |
| M32 | `q_login` | 42,08 | — |

Las operaciones del flujo diario (buscar un vehículo, abrir una sesión, armar y cerrar una cotización,
paginar el historial) quedan por debajo de 1,5 ms con 300 mil sesiones. Las tres cifras más altas tienen
explicación propia: el login (§6), y las dos del dashboard (§4 y §7).

## 3. Hallazgo 1: los parámetros opcionales anulaban la paginación por clave

La `q_historial` de la Fase 3 era una sola sentencia con estado y cursor opcionales
(`$2 IS NULL OR (iniciada_en, id) < …`). `docs/consultas.md` ya lo anotaba como riesgo; la medición lo
confirmó.

PostgreSQL planifica las primeras cinco ejecuciones de una sentencia preparada con los valores reales y
después puede adoptar un **plan genérico**, válido para cualquier valor. En ese plan no sabe si `$2` será
nulo, así que la condición no puede ser condición del índice: queda como filtro.

| | ms | Bloques | Plan |
|---|---:|---:|---|
| M06a formulación anterior, plan genérico | 42,12 | 75.874 | `Index Cond: (taller_id = …)` + `Filter`, 75.001 filas descartadas |
| M02 `q_historial_siguiente` | 0,49 | 427 | `Index Cond: (taller_id = …) AND (ROW(iniciada_en, id) < ROW(…))` |
| M06 `q_historial_siguiente`, plan genérico forzado | 0,34 | 396 | igual que M02 |
| M03 `OFFSET 75000` | 74,27 | 4.253 | recorre y descarta 75.000 filas |

Con el plan genérico, la formulación anterior se comportaba igual que un `OFFSET`: el costo crecía con la
profundidad de la página. **Corrección:** cuatro sentencias sin parámetros opcionales (`q_historial`,
`_siguiente`, `_estado`, `_estado_siguiente`) y lo mismo para la auditoría (`q_auditoria`,
`q_auditoria_siguiente`). M06 muestra que la nueva forma es correcta también en el plan genérico: ya no
depende de qué plan elija el servidor.

## 4. Hallazgo 2: bajo RLS, un enum no puede ser clave de búsqueda de un índice

`V006` creaba `ix_sesion_diagnostico_estado (taller_id, estado, iniciada_en DESC, id DESC)` para el
historial por estado y los conteos del dashboard. En los planes medidos el índice se usaba así:

```
Index Only Scan using ix_sesion_diagnostico_estado
  Index Cond: (taller_id = $0)
  Filter: (estado = 'cotizado')
  Rows Removed by Filter: 149178
```

`estado` no era condición del índice. La causa está en cómo PostgreSQL protege las políticas: una condición
escrita por el usuario solo puede evaluarse antes que la condición de seguridad (y por tanto usarse para
buscar en el índice) si su operador es **leakproof**, es decir, si está garantizado que no revela datos a
través de un error o un mensaje. El experimento E0 lo muestra:

| Operador | `leakproof` |
|---|---|
| `int8eq`, `uuid_eq`, `texteq`, `timestamptz_ge` | sí |
| `enum_eq` | **no** |

| E0: contar las sesiones cotizadas del taller | ms | Plan |
|---|---:|---|
| A) índice `(taller_id, estado, …)`, **sin** RLS | 0,17 | `Index Cond: (taller_id = 3) AND (estado = 'cotizado')` |
| B) el mismo índice, **con** RLS | 12,30 | `estado` como filtro: 149.178 filas descartadas para devolver 822 |
| C) índice **parcial** `WHERE estado = 'cotizado'`, con RLS | 0,19 | `Index Cond: (taller_id = $0)` sobre un índice de 822 filas |

El índice parcial funciona porque el planificador *demuestra* al planificar que la consulta implica el
predicado; no evalúa `estado` fila por fila.

**Corrección (`V009`):** se elimina `ix_sesion_diagnostico_estado` y se agrega
`ix_sesion_diagnostico_cotizado`, parcial, junto al `ix_sesion_diagnostico_pendiente` que ya existía. Para
`completado` y `cancelado` se usa `ix_sesion_diagnostico_historial` con el estado como filtro: son los
estados mayoritarios y casi todas las filas recorridas califican (M05: 0,44 ms). La prueba `ESQ-28` impide
que se vuelva a crear un índice de búsqueda con un enum como columna clave en una tabla con RLS.

Este hallazgo no se ve con las semillas (16 sesiones) ni probando como superusuario: solo aparece con
volumen **y** con el rol real.

**Efecto en el dashboard.** `q_dashboard_resumen` se reescribió para apoyarse en esos índices parciales:

| | ms | Qué hace |
|---|---:|---|
| M17a versión de la Fase 3 | 184,06 | un recorrido de las 150.000 sesiones del taller unido a sus 140.000 cotizaciones vigentes; el *hash* se vuelca a disco |
| M17 versión actual | 14,58 | pendientes y cotizadas desde los índices parciales; el período, un rango de `ix_sesion_diagnostico_historial` |

La reescritura cambió el significado de las cifras del período, que ahora son por cohorte de inicio
(tema T-49).

## 5. Hallazgo 3: el planificador no conoce el taller

El contexto llega por `current_setting('app.taller_id')`, que se resuelve al ejecutar. Al planificar,
PostgreSQL estima "un taller cualquiera": 302.016 sesiones entre 22 talleres, unas 14.000 filas. Para el
taller grande la realidad es 150.000 (M17a: `rows=14382` estimadas, `rows=150000` reales).

Consecuencias observadas:

- En el dashboard, escribir el monto cotizado como `JOIN` llevaba a un *hash join* que leía **todas** las
  cotizaciones del taller para sumar 822. Con una subconsulta escalar por sesión el acceso es directo.
- En la versión anterior del dashboard, el *hash* estimado para 14 mil filas recibió 150 mil y usó
  archivos temporales.

No tiene arreglo dentro del diseño (el valor no existe al planificar); se mitiga con la forma de las
consultas. Las reglas están en `docs/consultas.md` §3.6.

## 6. Costos que son deliberados

- **Login, 42 ms.** Es el costo de bcrypt con factor 10 dentro de la base: está para encarecer un ataque
  por fuerza bruta. Ocurre una vez por inicio de sesión. Trasladar el hash al backend es **[AVANZADA]**.
- **Política RLS del mecánico sobre `vehiculo`.** Contar los 30.000 vehículos del taller tarda 22,10 ms
  como mecánico (M20) y 2,98 ms como administrador (M26): la política del mecánico comprueba además que el
  titular esté activo, y resuelve esa subconsulta una vez por consulta (*hashed SubPlan* sobre los titulares
  del taller). En las consultas reales, que piden un vehículo o una página, el costo no se nota (M07: 0,08 ms).
- **Escrituras, alrededor de 1 ms.** Incluyen los triggers de validación, el *snapshot* de precios y el
  registro de auditoría (M21 a M25).

## 7. Índices: qué se queda y por qué

El contador `idx_scan` no basta para decidir: el planificador también sondea índices al estimar. Cada
índice dudoso se probó con la sentencia que debería usarlo, con el índice y sin él (`fase5_indices.txt`).

| Índice | Con | Sin | Decisión |
|---|---:|---:|---|
| `ix_sesion_diagnostico_estado` | — | — | **eliminado** (§4): su columna `estado` no sirve bajo RLS |
| `ix_sesion_diagnostico_cotizado` | 0,19 ms | 12,30 ms | **nuevo** (E0) |
| `ix_falla_sesion_dtc` | 0,19 ms | 29,02 ms | se queda: comprobación de la FK al borrar un DTC (E1) |
| `ix_compatibilidad_repuesto_modelo` | 0,14 ms | 8,69 ms | se queda: FK al borrar un modelo (E2) |
| `ix_vehiculo_taller_titular` | 0,03 ms | 5,61 ms | se queda: supresión de un titular (E3) |
| `ix_titular_bloqueado_hasta` | 0,32 ms | 3,02 ms | se queda: proceso de vencidos (E4) |
| `ix_consentimiento_titular_taller_titular` | 0,01 ms | 2,77 ms | se queda; no tenía ninguna consulta que lo usara y se agregó `q_consentimientos_titular` (E5, M33) |
| `ix_usuario_taller` | 0,05 ms | 0,47 ms | **eliminado**: aun con 30.000 usuarios la diferencia es irrelevante (E6) |
| `ix_solicitud_derecho_titular_taller_titular` | 37,40 ms | 39,49 ms | **eliminado**: no cambia el plan útil (E7) |

Usados directamente por las consultas medidas: `ix_sesion_diagnostico_historial`, `_pendiente`,
`_cotizado`, `_vehiculo`, `ix_vehiculo_taller_modelo_anio`, `ix_titular_taller`, `ix_falla_sesion_critica`,
`ix_auditoria_operacion_taller_fecha`. `ix_dtc_componente_componente` (40 kB) no se midió: se conserva por
la misma razón que `ix_falla_sesion_dtc`, sobre una tabla de 2.985 filas.

**Costo de los índices.** `cotizacion` tiene 111 MB de índices para 87 MB de datos: siete índices, de los
que seis son restricciones (PK, UNIQUE e índices únicos parciales). El más grande de todo el esquema es
`ix_auditoria_operacion_taller_fecha` (139 MB), que se actualiza en cada operación auditada; es el precio de
que el administrador pueda leer la bitácora de su taller en 0,08 ms.

## 8. Lo que queda sin optimizar

- **`q_dashboard_dtc_frecuentes`: 36,73 ms y 53.108 bloques** para 90 días (unas 12.300 sesiones y sus
  fallas, una búsqueda por sesión). Aceptable para un panel; si creciera, una vista materializada por
  taller y día sería el paso siguiente (**[AVANZADA]**).
- **`q_solicitudes_derecho` no tiene `LIMIT`.** Con 18.750 solicitudes en un taller tarda 37 a 39 ms (E7).
  El volumen real de esa tabla es de pocas filas; aun así incumple la regla 4 de `docs/consultas.md` §3.6
  (tema T-50).
- **`fk_vehiculo_modelo_vehiculo` sin índice propio.** Borrar un modelo del catálogo recorre los 60.411
  vehículos (unos milisegundos, visible en E2). Es una operación de plataforma, infrecuente: no se agrega un índice más
  a `vehiculo`, que ya tiene siete.

## 9. Lo que esta medición no cubre

- **Carga concurrente.** Se mide una sentencia a la vez; no hay prueba con decenas de conexiones ni se
  mide contención de bloqueos.
- **Caché fría y disco real.** Todo se mide con la caché caliente y sobre el almacenamiento de Docker
  Desktop.
- **Variabilidad.** Cada tiempo es de una ejecución. Durante el desarrollo, entre corridas completas los
  tiempos de las medidas más lentas cambiaron de forma apreciable mientras los bloques leídos se mantenían;
  esas corridas anteriores no se guardaron como evidencia, por eso no se citan cifras.
- **Crecimiento de la auditoría.** Con 2 millones de filas ocupa 573 MB, la mitad de la base. El
  particionado por fecha y la política de retención son **[AVANZADA]** y se tratan en la Fase 6.
- **Ajuste del servidor.** No se modificó ningún parámetro. El `/dev/shm` de 64 MB del contenedor impidió
  el `VACUUM` paralelo (se ejecuta con `PARALLEL 0`); es un límite del entorno Docker, no del esquema
  (tema T-51). **Resuelto en la Fase 6:** el contenedor tiene `shm_size: 256mb` y `db/perf/run.sh` volvió a
  usar el `VACUUM` paralelo sobre el mismo volumen (`docs/evidencia/fase6_perf.txt`). Las cifras de este
  documento son las de la corrida de la Fase 5 y no se regeneraron.

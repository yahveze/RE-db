# Consultas del frontend y su contrato

Todas las sentencias que el backend envía a la base están en `db/queries/` como `PREPARE` con parámetros
`$n`. El nombre de cada columna de salida **es** el campo JSON de la respuesta. La salida real de cada una
sobre las semillas está en `docs/evidencia/fase3_consultas.txt` (en adelante **[consultas §n]**).

Las rutas HTTP son orientativas: el alcance del proyecto es la base de datos (supuesto 1 de
`decisiones.md`). Lo que se fija aquí es qué recibe cada sentencia, qué devuelve y con qué rol.

## 1. Reglas comunes

| Regla | Detalle |
|---|---|
| Una petición = una transacción | `BEGIN; SET LOCAL ROLE <grupo>; EXECUTE ctx(...); ...; COMMIT;` |
| Rol | El backend elige una de tres sentencias literales (`SET LOCAL ROLE taller_admin` / `taller_mecanico` / `taller_auditor`) según el rol que devolvió el login. Nunca interpola texto del cliente. |
| Contexto | `ctx(taller_id, usuario_id, ip, request_id)` usa `set_config(..., true)`: muere con la transacción, compatible con un *pool* en modo transacción. |
| Sin filtro de taller en el SQL | Ninguna consulta escribe `WHERE taller_id = ...`: lo aplica RLS. Sin contexto devuelven **cero filas** [consultas §11]. |
| Identificadores | Entran y salen `id_publico` (UUID). Los `id` secuenciales no salen de la base, con dos excepciones declaradas: el login (para que el backend arme el contexto) y la auditoría (tema T-36). |
| Nombres | Columnas propias sin prefijo; las de otra tabla con el prefijo de su entidad (`vehiculo_patente`, `modelo_nombre`). |
| No encontrado | Un `id_publico` inexistente **o de otro taller** da cero filas → la API responde 404. No se distingue un caso del otro [consultas §10]. |
| Dinero | `BIGINT` en unidad mínima de la moneda, siempre acompañado de `moneda`. |
| Orden de perfiles | `CASE perfil WHEN 'genuino' THEN 1 WHEN 'oem' THEN 2 WHEN 'generico' THEN 3 END`, explícito en cada consulta. |

## 2. Sentencias de lectura

| Sentencia | Ruta orientativa | Roles | Parámetros | Filas |
|---|---|---|---|---|
| `q_login` | `POST /auth/login` | conexión, sin contexto | email, contraseña | 1 |
| `ctx` | — (interna) | los tres | taller_id, usuario_id, ip, request_id | 1 |
| `q_configuracion` | `GET /settings` | los tres | — | 1 |
| `q_marcas` | `GET /catalog/brands` | los tres | — | N |
| `q_modelos` | `GET /catalog/brands/{marca}/models` | los tres | marca (uuid) | N |
| `q_dtc_buscar` | `GET /catalog/dtc?q=` | los tres | prefijo, límite | N |
| `q_repuestos_por_dtc` | `GET /catalog/dtc/{codigo}/parts` | los tres | código, modelo (uuid, opc.), año (opc.) | N |
| `q_buscar_vehiculo_vin` | `GET /search?vin=` | admin, mecánico | VIN | 0–1 |
| `q_buscar_vehiculo_patente` | `GET /search?plate=` | admin, mecánico | patente | 0–1 |
| `q_buscar_vehiculo_modelo` | `GET /search?model=&year=` | admin, mecánico | modelo (uuid), año (opc.), límite | N |
| `q_historial` | `GET /history` | los tres | límite | N |
| `q_historial_siguiente` | `GET /history?cursor=` | los tres | cursor (fecha, uuid), límite | N |
| `q_historial_estado` | `GET /history?status=` | los tres | estado, límite | N |
| `q_historial_estado_siguiente` | `GET /history?status=&cursor=` | los tres | estado, cursor (fecha, uuid), límite | N |
| `q_historial_vehiculo` | `GET /vehicles/{id}/sessions` | los tres | vehículo (uuid), límite | N |
| `q_sesion` | `GET /sessions/{id}` | los tres | sesión (uuid) | 0–1 |
| `q_sesion_fallas` | `GET /sessions/{id}/faults` | los tres | sesión (uuid) | N |
| `q_matriz` | `GET /sessions/{id}/matrix` | los tres | sesión (uuid) | N |
| `q_cotizaciones_sesion` | `GET /sessions/{id}/quotes` | los tres | sesión (uuid) | N |
| `q_cotizacion_detalle` | `GET /quotes/{id}/lines` | los tres | cotización (uuid) | N |
| `q_dashboard_resumen` | `GET /dashboard` | los tres | inicio del período | 1 |
| `q_dashboard_dtc_frecuentes` | `GET /dashboard/top-dtc` | los tres | inicio del período, límite | N |
| `q_usuarios` | `GET /users` | admin, auditor | — | N |
| `q_dispositivos` | `GET /devices` | los tres | — | N |
| `q_consentimientos_titular` | `GET /holders/{id}/consents` | los tres | titular (uuid) | N |
| `q_solicitudes_derecho` | `GET /privacy/requests` | admin, auditor | — | N |
| `q_auditoria` | `GET /audit` | admin, auditor | tabla (opc.), límite | N |
| `q_auditoria_siguiente` | `GET /audit?cursor=` | admin, auditor | tabla (opc.), cursor (fecha, id), límite | N |

Son 28 sentencias de lectura; las columnas de salida de cada una están en su archivo, junto a la sentencia.
Las 15 de escritura (`tx_*`) se describen en `docs/transacciones.md`.

**Por qué el rol de la tabla no es una convención sino un hecho.** El rol que no figura no puede ejecutar la
sentencia aunque quiera: las búsquedas de vehículo devuelven `titular.nombre`, columna sobre la que el
auditor no tiene privilegio; `q_usuarios` devuelve `email`, que el mecánico no puede leer. Lo comprueba la
matriz rol × sentencia de `db/tests/04_rbac.sql`.

## 3. Consultas que merecen explicación

### 3.1 Login (`q_login`)

Devuelve siempre una fila. Con `autenticado = false` todas las demás columnas son `NULL` y no se distingue
el motivo (clave incorrecta, usuario inactivo, cuenta bloqueada o email inexistente) [consultas §1]. El
email se normaliza en la función (`lower(btrim(...))`). `usuario_id` y `taller_id` internos quedan en la
sesión del servidor del backend; al cliente solo viajan los `*_id_publico`.

### 3.2 Historial con paginación por clave (`q_historial` y variantes)

```sql
-- q_historial_estado_siguiente
WHERE  s.estado = $1
AND    (s.iniciada_en, s.id) < ($2, (SELECT k.id FROM sesion_diagnostico k WHERE k.id_publico = $3))
ORDER  BY s.iniciada_en DESC, s.id DESC
LIMIT  $4
```

- **Sin `OFFSET`.** El cursor es la última fila de la página anterior; el costo de una página profunda es el
  de la página 1, y no se repiten ni se saltan filas si entra una sesión nueva entre dos páginas.
- **Desempate único.** `iniciada_en` puede repetirse; `(iniciada_en, id)` no. El cliente recibe y devuelve
  `id_publico`; la subconsulta lo traduce al `id` interno.
- **Hay más páginas.** La API pide `límite + 1` y descarta la fila sobrante.
- **`LEFT JOIN` a `vehiculo`.** Para el mecánico, las sesiones de un titular bloqueado o anonimizado siguen
  en el historial con las columnas del vehículo en `NULL` [consultas §4, página 2]. El auditor sí ve el
  vehículo; el anonimizado aparece sin patente [consultas §8].
- **Cuatro sentencias, no una.** La primera versión era una sola sentencia con estado y cursor opcionales
  (`$1 IS NULL OR …`). Medida con volumen, en el plan genérico esas condiciones quedan como filtro y la
  página profunda lee todas las filas anteriores. Sin parámetros opcionales, la comparación de fila es
  siempre condición del índice (`docs/evidencia/rendimiento.md` §3). Las cuatro devuelven las mismas columnas.
- Índices: `ix_sesion_diagnostico_historial`; con estado `pendiente` o `cotizado`, los índices parciales
  `ix_sesion_diagnostico_pendiente` e `ix_sesion_diagnostico_cotizado`.

### 3.3 Matriz comparativa (`q_matriz`)

Una fila por (componente, repuesto) [consultas §5]:

1. **Fallas → componentes.** Un componente asociado a varios DTC de la sesión aparece una sola vez, con
   `dtc_codigos` (arreglo) y `severidad_maxima`. Ejemplo real: en la Kia Morning, el inyector responde a
   `{P0201,P0300}`.
2. **Compatibilidad (RN-44).** `EXISTS` sobre `compatibilidad_repuesto` con el modelo y el año del vehículo.
   Ejemplos reales: la Corolla 2006 solo recibe el genérico (genuinos desde 2010, OEM desde 2008); una
   Hilux 2016 no recibe el catalizador Walker, cuyos rangos son 2005–2015 y 2018–2024.
3. **Precio (RN-45).** `ROUND(precio_referencia * (1 + margen_pct / 100))::bigint` con el margen actual del
   taller. El mismo repuesto cuesta distinto en cada taller: el catalizador genuino sale 896 987 con margen
   30 % y 1 003 935 con 45,5 % [consultas §5 y §10]. `precio_referencia` no se devuelve.
4. **Orden (RN-43).** Severidad, componente, perfil genuino → OEM → genérico, precio, `id`.

Devuelve cero filas, sin error, si la sesión no es visible, si el vehículo está oculto para el rol, si
ningún DTC tiene componente (`U0100`) o si nada es compatible. Los repuestos con `disponible = false` no
aparecen.

`q_repuestos_por_dtc` es la variante de catálogo, sin sesión: usa la vista `v_dtc_repuesto` (decisión 9) y
aplica la compatibilidad solo si se indican modelo y año.

### 3.4 Cotizaciones

`q_cotizaciones_sesion` devuelve `total` (congelado al cerrar, `NULL` en un borrador) y `total_calculado`
(suma del detalle). En una cotización cerrada coinciden; en un borrador solo existe el segundo
[consultas §6]. `q_cotizacion_detalle` lee el *snapshot*, no el catálogo: tras cambiar el margen del taller
de 30 % a 35 %, la cotización cerrada conserva sus precios mientras la matriz ya muestra los nuevos
[transacciones TX-7].

### 3.5 Dashboard (`q_dashboard_resumen`)

Siempre una fila; sin contexto de taller devuelve ceros, no un error [consultas §11].

| Columna | Qué cuenta |
|---|---|
| `sesiones_pendientes`, `sesiones_cotizadas` | carga actual, sin período |
| `monto_cotizado_abierto` | suma del total vigente de las sesiones en `cotizado` |
| `fallas_criticas_abiertas` | fallas críticas en sesiones `pendiente` o `cotizado` |
| `sesiones_iniciadas_periodo` | sesiones con `iniciada_en >= $1` |
| `sesiones_completadas_periodo`, `sesiones_canceladas_periodo` | **de esas**, cuántas están hoy completadas o canceladas (cohorte) |
| `monto_completado_periodo` | total vigente de las completadas de esa cohorte |

El período es por cohorte de inicio, no por fecha de término: así las tres cifras salen de un solo
recorrido por rango de `ix_sesion_diagnostico_historial`. Contar por `completada_en` exigiría un índice más
sobre una tabla que ya tiene siete (tema T-49).

### 3.6 Reglas para escribir consultas bajo RLS

Salieron de medir con volumen (`docs/evidencia/rendimiento.md`); valen para cualquier sentencia nueva.

1. **Un enum no sirve como clave de búsqueda de un índice.** Bajo RLS solo las comparaciones *leakproof*
   pueden ser condición de índice, y la igualdad de enums no lo es. Para filtrar por `estado`, `severidad`
   o `estado_tratamiento` se usa un **índice parcial** y el valor se escribe como literal en la consulta
   (un parámetro no permite demostrar el predicado).
2. **Sin parámetros opcionales sobre columnas indexadas.** `$1 IS NULL OR col = $1` se degrada a filtro en
   el plan genérico. Si el parámetro decide qué índice usar, van dos sentencias.
3. **El planificador no conoce `app.taller_id`.** Estima cada taller como el promedio. En un taller grande
   subestima y puede elegir un *hash join* que lee tablas enteras: para "un valor por fila" (el total
   vigente de cada sesión) es más estable una subconsulta escalar que un `JOIN`.
4. **Toda lista lleva `LIMIT`** y, si puede crecer, paginación por clave.

## 4. Errores que la API debe traducir

La API decide por `SQLSTATE`, nunca por el texto: los mensajes de la base contienen ids internos
(por ejemplo `el repuesto 32 no esta disponible`) y no deben reenviarse al cliente.

| SQLSTATE | Significado | HTTP sugerido |
|---|---|---|
| `RE001` | transición de estado inválida | 409 |
| `RE002` | falta una cotización vigente cerrada | 409 |
| `RE003` | la cotización está cerrada | 409 |
| `RE004` | la sesión está en estado terminal | 409 |
| `RE006` | rol o contexto no autorizado | 403 |
| `RE007` | conflicto de versión (otro usuario modificó el registro) | 409 |
| `RE008` | cotización sin detalle | 422 |
| `RE009` | registro inexistente o no visible | 404 |
| `RE010` | repuesto no disponible | 422 |
| `RE011` | contraseña fuera de los límites | 422 |
| `23505` | duplicado (email, patente, VIN, MAC, segundo borrador) | 409 |
| `23514` | valor fuera de regla (formato de patente, cantidad, margen) | 422 |
| `23502` | dato obligatorio ausente (incluye un DTC que no está en el catálogo) | 422 |
| `42501` | el rol no tiene el privilegio | 403 |
| cero filas | el recurso no existe o es de otro taller | 404 |

## 5. Cómo reproducir

```bash
bash db/scripts/reset.sh && bash db/scripts/migrate.sh && bash db/scripts/seed.sh
bash db/scripts/evidencia_fase3.sh      # regenera docs/evidencia/fase3_*.txt
```

`evidencia_fase3.sh` termina con error si alguna consulta falla, si las transacciones producen un número de
errores distinto del esperado o si la demostración deja cambios en la base.

# 4. Normalización

## 4.1 Resultado en una frase

El modelo está en **BCNF**, con un conjunto **cerrado y declarado** de desviaciones deliberadas:
(1) `taller_id` propagado a las tablas hijas, (2) los *snapshots* y el precio calculado del detalle de
cotización, (3) el `total` congelado, y (4) tres atributos de estado derivables de sus fechas. Cada una
está protegida por una restricción que impide que el dato redundante se contradiga con su origen.

Afirmar "todo está en BCNF" sin matices sería falso: la sección 4.5 muestra exactamente qué forma normal
incumple cada desviación y por qué se acepta.

**Notación.** `X → Y`: X determina funcionalmente a Y. *Clave candidata*: conjunto mínimo de atributos que
determina toda la fila. *Atributo primo*: pertenece a alguna clave candidata.
- **1FN:** atributos atómicos, sin grupos repetidos.
- **2FN:** ningún atributo no primo depende de una *parte* de una clave candidata.
- **3FN:** ningún atributo no primo depende de otro atributo no clave (sin dependencias transitivas).
- **BCNF:** en toda DF no trivial `X → Y`, X es superclave.

## 4.2 Primera forma normal

- **Sin grupos repetidos.** Los DTC de una sesión no son un arreglo ni columnas `dtc1, dtc2…`: son filas de
  `falla_sesion`. Los repuestos de una cotización son filas de `cotizacion_detalle`. Los años compatibles
  son un rango `(anio_desde, anio_hasta)`, no una lista.
- **Atributos atómicos.** Marca y modelo son columnas y tablas separadas, no un texto "Toyota Hilux".
- **Sobre JSONB** (`falla_sesion.freeze_frame`, `auditoria_operacion.datos_*`): son documentos **opacos**
  para el modelo. Ninguna regla de negocio, FK ni consulta del frontend depende de su estructura interna,
  de modo que se comportan como un valor atómico. Si mañana se necesitara filtrar por "RPM del freeze
  frame", ese dato debería extraerse a una columna; mientras tanto, modelar cada parámetro del escáner
  como columna sería inventar requisitos.

## 4.3 Dependencias funcionales y claves candidatas

En todas las tablas con `id` e `id_publico`, ambos son claves candidatas (`id → todo`, `id_publico → todo`);
no se repite en cada fila. "Condicional" indica una clave que solo aplica cuando el atributo no es nulo
(índice único parcial).

| Tabla | Otras claves candidatas | Otras DF no triviales | Forma normal |
|---|---|---|---|
| `taller` | — | — | BCNF |
| `taller_configuracion` | `taller_id` (única) | — | BCNF |
| `usuario` | `email` | — | BCNF |
| `usuario_credencial` | `usuario_id` (única) | — | BCNF |
| `titular` | `(taller_id, identificador_hmac)` condicional | `{anonimizado_en, bloqueado_hasta} → estado_tratamiento` | desviación D4 |
| `consentimiento_titular` | `(titular_id, finalidad, otorgado_en)` | `titular_id → taller_id` | desviación D1 |
| `solicitud_derecho_titular` | — | `titular_id → taller_id` | desviación D1 |
| `marca_vehiculo` | `nombre` | — | BCNF |
| `modelo_vehiculo` | `(marca_vehiculo_id, nombre)` | — | BCNF |
| `dtc_catalogo` | `codigo` | — | BCNF |
| `componente_repuesto` | `nombre` | — | BCNF |
| `dtc_componente` | `(dtc_id, componente_id)` (única; toda la fila es clave) | — | BCNF |
| `repuesto` | `(componente_id, marca, codigo_fabricante)` | — | BCNF |
| `compatibilidad_repuesto` | `(repuesto_id, modelo_vehiculo_id, anio_desde)` (única) | clave `→ anio_hasta` | BCNF |
| `vehiculo` | `(taller_id, vin)` y `(taller_id, patente)` condicionales | `titular_id → taller_id` (solo si hay titular) | desviación D1 |
| `dispositivo_diagnostico` | `(taller_id, mac)` | — | BCNF |
| `sesion_diagnostico` | — | `vehiculo_id → taller_id`; `{cotizada_en, completada_en, cancelada_en} → estado` | D1 y D4 |
| `falla_sesion` | `(sesion_id, dtc_id)` (única) | `sesion_id → taller_id` | desviación D1 |
| `cotizacion` | `(sesion_id, numero_revision)`, `(taller_id, clave_idempotencia)` | `sesion_id → taller_id` | D1 y D3 |
| `cotizacion_detalle` | `(cotizacion_id, repuesto_id)` (única) | `cotizacion_id → taller_id`; `{precio_referencia_snapshot, margen_pct_snapshot} → precio_unitario` | D1 y D2 |
| `auditoria_operacion` | — | — | bitácora, ver 4.9 |

Comprobaciones que suelen preguntarse en una defensa:

- **`usuario`: ¿`email → taller_id` es transitiva?** No. `email` es clave candidata, así que es superclave:
  la DF cumple BCNF.
- **`repuesto`: ¿`marca → perfil`?** No. NGK puede ser `oem` para un vehículo y `genuino` para otro; el
  perfil es una propiedad del repuesto concreto, no de la marca.
- **`repuesto`: ¿`codigo_fabricante → todo`?** No. Dos fabricantes pueden usar el mismo número de parte;
  por eso la clave es la terna `(componente_id, marca, codigo_fabricante)`.
- **`vehiculo`: ¿`(modelo_vehiculo_id, anio, motor)` es clave?** No. Dos Hilux 2021 2.4 son vehículos
  distintos. Esa terna es una *descripción técnica*, no una identidad.
- **`dtc_catalogo`: ¿la primera letra del código determina el sistema (P = tren motriz)?** Sí, y por eso
  **no se guarda** una columna `sistema`: sería un atributo derivado de parte de `codigo`.
- **`falla_sesion.severidad` frente a `dtc_catalogo.severidad_sugerida`.** No es redundancia: una es la
  sugerencia del catálogo y la otra la observación del mecánico en esa sesión, y pueden diferir.
  `dtc_id → severidad` **no** se cumple.

## 4.4 La dependencia transitiva que sí se eliminó: marca y modelo

Diseño ingenuo: `vehiculo(id, …, marca, modelo, anio)`.

DF: `id → modelo` y `modelo → marca` ("Hilux" siempre es Toyota). Entonces `id → modelo → marca` es una
dependencia transitiva de un atributo no primo: **viola 3FN**.

Descomposición aplicada:
`marca_vehiculo(id, nombre)`, `modelo_vehiculo(id, marca_vehiculo_id, nombre)`,
`vehiculo(id, …, modelo_vehiculo_id, anio)`.

| Anomalía en el diseño ingenuo | Cómo se evita |
|---|---|
| **Actualización:** corregir "Toyta" obliga a tocar miles de vehículos; si se omite uno hay dos marcas | la marca vive en una sola fila |
| **Inserción:** no se puede registrar el modelo "Yaris" hasta que llegue el primer Yaris a un taller | `modelo_vehiculo` existe por sí mismo |
| **Eliminación:** si se anonimiza el único Golf GTI registrado se pierde el hecho "Golf GTI es Volkswagen" | el catálogo no depende de los vehículos |
| **Inconsistencia:** nada impide `marca = 'Ford', modelo = 'Hilux'` | la marca se obtiene del modelo; no hay dónde escribir la contradicción |

## 4.5 Desviaciones deliberadas

### D1 — `taller_id` propagado a las tablas hijas

**Qué incumple.** En `falla_sesion` la clave es `(sesion_id, dtc_id)` y `sesion_id → taller_id`: un
atributo no primo depende de *parte* de la clave → **viola 2FN**. Lo mismo ocurre en `cotizacion_detalle`
con `cotizacion_id → taller_id`. En `sesion_diagnostico`, `consentimiento_titular` y
`solicitud_derecho_titular` la DF `padre_id → taller_id` es transitiva → **viola 3FN**. En `cotizacion`,
`taller_id` es primo (forma parte de `(taller_id, clave_idempotencia)`), así que cumple 3FN pero
**viola BCNF** (`sesion_id` no es superclave).

`vehiculo` es un caso distinto: `titular_id` es anulable, por lo que un vehículo sin titular no tendría de
dónde derivar el taller. Ahí `taller_id` es un atributo propio, no redundante.

**Por qué se acepta.** Es la decisión 1 del proyecto, y tiene tres beneficios concretos:
1. **RLS simple y rápido:** cada política es `taller_id = <contexto>`, sin subconsultas hacia el padre.
2. **Índices que empiezan por `taller_id`**, alineados con el filtro que RLS agrega a toda consulta.
3. **Aislamiento verificable por el motor**, no por la aplicación.

**Por qué no produce anomalías.** La FK compuesta `(sesion_id, taller_id) → sesion_diagnostico (id, taller_id)`
obliga a que el `taller_id` del hijo sea **el mismo** del padre: el valor redundante no puede divergir.
Cambiar el `taller_id` de un padre con hijos lo rechaza la propia FK (`ON UPDATE NO ACTION`). La
redundancia existe, pero la inconsistencia es irrepresentable.

**Costo.** 8 bytes por fila en las hijas y un índice `UNIQUE (id, taller_id)` en seis tablas padre. Ese
índice es lógicamente redundante (`id` ya es único), pero PostgreSQL exige que las columnas referenciadas
por una FK tengan una restricción única exacta. El costo se acota a las tablas padre: las tablas hoja
(`falla_sesion`, `cotizacion_detalle`) no lo necesitan.

**Alternativa descartada:** PK `(taller_id, id)` en todas las tablas operativas. Elimina el índice extra,
pero convierte **todas** las FK en compuestas y complica la API, que identifica por `id_publico`.

### D2 — *Snapshot* y precio calculado en `cotizacion_detalle`

`nombre_snapshot`, `marca_snapshot`, `perfil_snapshot` y `precio_referencia_snapshot` copian datos de
`repuesto`; `margen_pct_snapshot` copia `taller_configuracion.margen_pct`.

**¿Es una violación?** En rigor, no: `repuesto_id → nombre_snapshot` **no se cumple**. El atributo
significa "el nombre que tenía el repuesto cuando se cotizó", y dos cotizaciones del mismo repuesto pueden
tener valores distintos. Es un **hecho histórico** propio de la línea, no una copia del catálogo actual.

**Lo que sí es redundante** es `precio_unitario`, función de dos atributos no clave:
`{precio_referencia_snapshot, margen_pct_snapshot} → precio_unitario` → **viola 3FN**. Se guarda para que el
monto cobrado no dependa de re-ejecutar una fórmula que podría cambiar (por ejemplo, la regla de redondeo),
y se protege con un `CHECK` que exige que coincida con la fórmula vigente al insertarlo.

**Anomalía que evita no normalizar:** si el detalle solo guardara `repuesto_id` y calculara el precio al
leer, subir un precio maestro **cambiaría cotizaciones ya entregadas al cliente**. Aquí la forma
normalizada es la incorrecta desde el punto de vista del negocio.

### D3 — `cotizacion.total` y `cotizacion.vigente`

`total = SUM(cantidad * precio_unitario)` es derivable del detalle. Se guarda **solo al cerrar**, cuando el
detalle se vuelve inmutable (trigger), así que no hay ventana en la que total y detalle puedan divergir.
Mientras la cotización está abierta, `total` es `NULL` y el total se calcula al vuelo.

`vigente` también es derivable (es la última revisión cerrada de la sesión). Se guarda porque permite
expresar "una sola vigente por sesión" como **índice único parcial**, que el motor garantiza incluso con
concurrencia; como dato derivado habría que confiar en que todas las consultas calculen el máximo igual.

### D4 — Estado y fechas

`sesion_diagnostico.estado` se deduce de `cotizada_en`, `completada_en` y `cancelada_en`;
`titular.estado_tratamiento` se deduce de `anonimizado_en` y `bloqueado_hasta`. Son DF entre atributos no
clave → **violan 3FN**.

Se conservan ambos porque cumplen funciones distintas: el estado es lo que filtra la app, lo que indexa
el historial y lo que leen las políticas RLS; las fechas responden "cuándo". Los `CHECK`
`ck_sesion_estado_timestamps`, `ck_titular_estado_bloqueado` y `ck_titular_estado_anonimizado` impiden
toda combinación contradictoria.

### Resumen de desviaciones

| Id | Dónde | Forma que incumple | Protección |
|---|---|---|---|
| D1 | `taller_id` en hijas | 2FN (hojas), 3FN o BCNF (resto) | FK compuesta |
| D2 | `precio_unitario` | 3FN | CHECK con la fórmula |
| D2 | columnas `*_snapshot` | ninguna (hecho histórico) | trigger que las llena; inmutables al cerrar |
| D3 | `total`, `vigente` | derivado entre tablas | se fija al cerrar; trigger de inmutabilidad; índice único parcial |
| D4 | `estado`, `estado_tratamiento` | 3FN | CHECK de coherencia |

## 4.6 `marca` como texto en `repuesto`

Extraer un atributo a su propia tabla es normalización **solo si existe una dependencia funcional que lo
exija**: algún atributo que dependa de la marca y no del repuesto (país, garantía, proveedor). En este
modelo no hay ninguno: de la marca solo se guarda el nombre.

Una tabla `marca_repuesto(id, nombre)` sustituiría un texto por un entero que apunta a ese mismo texto.
Eso es una **clave sustituta**, no una forma normal superior: `repuesto` ya está en BCNF con `marca` como
texto. Lo que una tabla así aportaría es *control de dominio* (evitar "Bosch" y "BOSCH"), un objetivo
legítimo pero distinto, que aquí se cubre porque solo `app_owner` escribe el catálogo.

**Cuándo cambiaría:** en cuanto aparezca un atributo propio de la marca. Migración: crear
`marca_repuesto`, poblarla con `SELECT DISTINCT marca`, agregar `marca_repuesto_id` y eliminar el texto.

Contraste con `marca_vehiculo`, que **sí** es tabla: allí existe la DF `modelo → marca` (sección 4.4).

## 4.7 `v_dtc_repuesto` como vista

El enunciado pide `dtc_repuesto` (N:M DTC ↔ repuesto). La regla del negocio es que un DTC apunta a
**componentes**, y cada repuesto pertenece a **un** componente:

- `dtc_componente(dtc_id, componente_id)` — relación N:M
- `repuesto.componente_id` — DF `repuesto_id → componente_id`

De ahí, "el repuesto R sirve para el DTC D" es verdadero **si y solo si** D está asociado al componente de
R. La relación DTC ↔ repuesto es por tanto el *join* de las otras dos: no contiene información nueva.

**Precisión terminológica.** El enunciado lo describe como la dependencia transitiva
`dtc → componente → repuesto`. En sentido estricto no son dependencias funcionales (un DTC tiene *varios*
componentes y un componente *varios* repuestos), sino una **relación derivable**. El defecto de guardarla
es el mismo que persigue la normalización —redundancia que genera anomalías—, y en una tabla universal
`(dtc_id, componente_id, repuesto_id)` con clave `(dtc_id, repuesto_id)` sí aparece una DF parcial,
`repuesto_id → componente_id`, que viola 2FN.

| Anomalía con tabla física `dtc_repuesto` | Con la vista |
|---|---|
| **Inserción:** dar de alta una bujía nueva obliga a insertar una fila por cada DTC de "bujía" (P0300, P0301, …); si se olvida una, la matriz queda incompleta para ese DTC | el repuesto aparece en todos sus DTC al instante |
| **Actualización:** mover un repuesto a otro componente exige borrar y reinsertar sus filas | basta el `UPDATE` de `componente_id` |
| **Eliminación:** desasociar un componente de un DTC obliga a borrar N filas coherentemente | basta borrar una fila de `dtc_componente` |
| **Inconsistencia:** puede existir `(P0420, bujía NGK)` aunque P0420 no esté asociado a bujías | irrepresentable |

**Cómo volver a tabla física si la rúbrica lo exige:**
1. `CREATE TABLE dtc_repuesto (dtc_id, repuesto_id, PRIMARY KEY (dtc_id, repuesto_id))` con sus dos FK.
2. Poblarla con `INSERT ... SELECT dtc_id, repuesto_id FROM v_dtc_repuesto`.
3. Mantenerla con triggers sobre `dtc_componente` y `repuesto`, o declarar que pasa a ser la fuente de
   verdad y eliminar `dtc_componente`.

La opción 3-b tendría sentido si el negocio necesitara **excepciones** ("para P0301 solo esta bujía, no
todas"): en ese caso la relación dejaría de ser derivable y la tabla física sería el modelo correcto.
Una vista materializada es el punto intermedio si el problema fuera solo de rendimiento.

## 4.8 Cuarta forma normal (por qué hay dos tablas de enlace y no una)

Los componentes que causan un DTC y los modelos compatibles con un repuesto son hechos **independientes**.
Una tabla única `(dtc_id, componente_id, repuesto_id, modelo_vehiculo_id)` obligaría a almacenar el
producto cartesiano de ambos (dependencias multivaluadas), y cada alta de compatibilidad se repetiría por
cada DTC. Por eso existen `dtc_componente` y `compatibilidad_repuesto` por separado.

## 4.9 `auditoria_operacion`: fuera del modelo normalizado, a propósito

Guarda `tabla` y `rol` como texto, y `taller_id`, `usuario_id`, `registro_id` como valores sin FK. Es una
**bitácora de hechos pasados**, no una entidad del dominio: debe poder registrar una fila de una tabla que
después se renombre o desaparezca, y no puede bloquear una operación por una FK. Normalizarla la haría
depender del esquema que audita.

## 4.10 Anomalías evitadas: resumen

| Tipo | Ejemplo en el proyecto | Qué lo evita |
|---|---|---|
| Inserción | registrar un modelo antes de que exista un vehículo de ese modelo | `modelo_vehiculo` independiente |
| Inserción | dar de alta un repuesto sin tener que asociarlo a cada DTC | `v_dtc_repuesto` derivada |
| Actualización | cambiar el margen del taller en un solo lugar | `taller_configuracion` (1 fila por taller) |
| Actualización | corregir la descripción de un DTC sin tocar las sesiones | `falla_sesion` solo guarda `dtc_id` |
| Actualización | subir un precio maestro sin alterar cotizaciones entregadas | *snapshot* (D2) |
| Eliminación | anonimizar un titular sin perder el historial técnico ni financiero | titular y vehículo separados de sesión y cotización |
| Eliminación | cancelar una sesión sin perder el DTC del catálogo | catálogo independiente |
| Inconsistencia | sesión del taller A con un vehículo del taller B | FK compuesta (D1) |

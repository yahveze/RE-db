# Decisiones de diseño — Repuestos Exactos

> Estado: **proyecto cerrado (Fases 0 a 7)**. Esquema en `db/migrations/` (V000–V010), semillas en
> `db/seeds/`, consultas y transacciones en `db/queries/`, suite de 518 pruebas en `db/tests/`, medición
> con volumen en `db/perf/` y operación en `db/scripts/` y `db/ops/` (respaldo y restauración probados),
> verificado sobre PostgreSQL 16.15. Dictamen final en `docs/dictamen.md`. Las secciones 5 a 11 registran
> lo que se verificó en cada fase, con las cifras de ese momento; el estado final es el de la sección 12.

Clasificación usada: **[OBLIGATORIA]** la exige el enunciado o la integridad del modelo ·
**[RECOMENDADA]** se implementa porque el costo es bajo y el beneficio defendible ·
**[AVANZADA]** solo se documenta.

---

## 1. Resumen ejecutivo

Base de datos PostgreSQL 16 para un sistema multi-taller que interpreta diagnósticos OBD-II y genera
matrices comparativas de repuestos. El diseño se apoya en cinco ideas:

1. **Aislamiento por segregación lógica.** `taller_id` en toda tabla operativa, FK compuestas
   `(padre_id, taller_id)` que hacen imposible una referencia cruzada entre talleres, y RLS con `FORCE`
   como segunda barrera. Agregar un taller es un `INSERT`.
2. **Catálogo global, operación local.** Marcas, modelos, DTC, componentes, repuestos y compatibilidad
   son comunes y de solo lectura para los talleres; cada taller solo aporta su `margen_pct`.
3. **Mínimo privilegio en tres capas.** El backend se conecta con un rol sin privilegios propios
   (`app_backend_user`) y asume por transacción un rol de grupo (`SET LOCAL ROLE`); RBAC decide qué
   operaciones, RLS decide qué filas; las credenciales y la auditoría solo se tocan desde funciones
   `SECURITY DEFINER` de un dueño dedicado.
4. **Dinero inmutable.** Precios en `BIGINT`, cotizaciones con *snapshot* de precio y margen, total
   congelado al cierre y cabecera/detalle inmutables después.
5. **Privacidad por diseño.** Sin RUT, titular con datos mínimos, supresión con bloqueo por retención
   y anonimización irreversible, y auditoría que nunca contiene datos personales.

Todo se valida ejecutándolo: el criterio de aceptación es que `make reset migrate seed test`
termine con código 0 sobre una base vacía, y toda cifra de la documentación sale de `docs/evidencia/`.

---

## 2. Decisiones abiertas (sección 4 del enunciado)

| # | Tema | Opciones | Default elegido | Impacto si cambia |
|---|------|----------|-----------------|-------------------|
| a | Unidad de durabilidad | kilómetros · meses · ambas | **Kilómetros** (`durabilidad_estimada_km INTEGER > 0`) **[OBLIGATORIA]**. El dato comparable con el `kilometraje` de la sesión es la distancia. | Meses: se renombra la columna. Ambas: se agrega `durabilidad_estimada_meses` anulable; no altera claves ni normalización. |
| b | `margen_pct`: tipo, default y rango | 0–100 · **0–200** · sin tope | `NUMERIC(5,2) NOT NULL DEFAULT 30.00`, `CHECK (margen_pct BETWEEN 0 AND 200)` **[RECOMENDADA]**. El 30 % es un valor de demostración, no un dato del negocio. | Cambiar rango o default es un `ALTER` de una línea. Si se necesitaran márgenes negativos (descuentos) cambia el CHECK y hay que revisar `precio_unitario >= 0`. Margen por componente o por perfil ya es "lista de precios" → **[AVANZADA]**. |
| c | Plazo de retención | fijo en código · **parámetro por taller** | `taller_configuracion.retencion_anios SMALLINT NOT NULL DEFAULT 6`, `CHECK (BETWEEN 0 AND 30)`. **Validar con asesoría legal**: el 6 es un supuesto prudente, no una afirmación jurídica. | Solo cambia el dato. La lógica de `fn_solicitar_supresion_titular` lee el parámetro. Con `0` toda supresión anonimiza de inmediato. |
| d | Columnas excluidas de la auditoría | lista mínima del enunciado · **lista ampliada** | Se excluyen de `datos_anteriores`/`datos_nuevos`: `titular.nombre`, `titular.telefono`, `titular.email`, `titular.identificador_hmac`; `vehiculo.patente`, `vehiculo.vin`; `usuario.email`, `usuario.nombre`; `falla_sesion.freeze_frame`. `usuario_credencial` no tiene trigger de auditoría. Ver nota (d). | Agregar o quitar una columna es cambiar un argumento del `CREATE TRIGGER` (`TG_ARGV`), sin tocar la función. |
| e | Sesión sin vehículo identificable | permitir `vehiculo_id NULL` · **exigir vehículo** | `sesion_diagnostico.vehiculo_id NOT NULL` **[OBLIGATORIA]**. El vehículo mínimo es patente + modelo + año; VIN opcional. Ver nota (e). | Permitir sesiones "anónimas" obliga a FK anulable, a que `/history` use `LEFT JOIN` y a que la matriz no pueda filtrar compatibilidad. |
| f | ¿Emite documentos tributarios? | solo cotizaciones · boletas/facturas | **Solo cotizaciones** (supuesto). La cotización no es un documento tributario; aun así se conserva la retención parametrizable por prudencia. **Validar.** | Si emitiera DTE: nuevas entidades (folio, tipo de documento, receptor con RUT), el "sin RUT" de la decisión 16 dejaría de ser sostenible para facturas, y la retención pasaría a ser obligación legal y no supuesto. |
| g | Borrado de padres en FK compuestas | `ON DELETE SET NULL (columna)` (PG 15+) · **`RESTRICT` + estado de baja** | **`RESTRICT`** **[RECOMENDADA]**: titular se anonimiza, dispositivo pasa a `baja`, usuario a `activo = false`. Ningún rol de ejecución tiene `DELETE` sobre ellos, así que `SET NULL` nunca se dispararía. | Si se quisiera borrado físico de dispositivos o titulares: `ON DELETE SET NULL (dispositivo_id)` / `(titular_id)`, que anula solo esa columna y conserva `taller_id` (`NOT NULL`). Depende de PostgreSQL ≥ 15. |

**Nota (d).** Se agregan tres columnas a la lista mínima: `usuario.nombre` (dato personal del trabajador,
misma razón que su email), y `falla_sesion.freeze_frame` (JSON libre que viene del escáner; no se puede
garantizar que nunca traiga un VIN). Lo que **sí** queda en auditoría son ids internos, estados, montos y
fechas: permiten reconstruir *qué pasó* sin reconstruir *a quién*.

**Nota (e).** El enunciado dice que sin VIN `(modelo_vehiculo_id, anio, motor)` identifican técnicamente
al vehículo. Propuesta: `modelo_vehiculo_id` y `anio` siempre `NOT NULL`; `motor` texto anulable con
`CHECK (anonimizado_en IS NOT NULL OR vin IS NOT NULL OR motor IS NOT NULL)`, es decir, **sin VIN el motor es obligatorio**.
Esa terna no es clave candidata (dos Hilux 2021 2.4 son vehículos distintos): la identidad dentro del
taller la da la patente.

---

## 3. Supuestos

1. **Alcance:** solo la base de datos. No hay backend ni PgBouncer desplegados; el patrón de petición
   se diseña para *transaction pooling* y se prueba con `psql`, no con PgBouncer real (ver T-12).
2. **Moneda:** todos los importes de un taller están en su moneda configurada; no hay conversión.
3. **Ley N° 21.719:** se trata como supuesto de diseño. Según la información de que dispongo, se publicó
   en diciembre de 2024 y entra en vigencia el 1 de diciembre de 2026. **Validar fecha y texto vigente.**
4. **Patente y VIN** se tratan como datos personales indirectos (supuesto prudente, **validar**).
5. **Catálogos:** los mantiene la plataforma (`app_owner`) por migración o carga; no hay pantalla de
   administración de catálogos.
6. **Patentes:** solo formatos de vehículos livianos (`AA1234`, `BBBB12`). Motos y remolques usan otros
   formatos y quedan fuera de alcance.
7. **Zona horaria:** el servidor corre en UTC (verificado); todo es `TIMESTAMPTZ` y la conversión a hora
   local es responsabilidad de la app.
8. **Un usuario = una persona = un rol.** Sin rol múltiple ni cambio de taller.
9. **Extensiones:** `pgcrypto` (`crypt`, `gen_salt`) y `pg_stat_statements`. `gen_random_uuid()` es del
   núcleo desde PostgreSQL 13 y no necesita extensión.

---

## 4. Temas para conversar

Cosas que el enunciado no resuelve o donde vi un problema. En cada una va mi propuesta; **si no dices
nada, aplico la propuesta.** Las marcadas ⚠ cambian el modelo o contradicen el texto literal.

### Entorno

**T-1 ⚠ `make` no está instalado en este equipo (Windows).**
El `Makefile` está escrito y cada objetivo delega en un script de `db/`, así que todo funciona con
`bash db/scripts/<x>.sh`, que es como lo verifiqué. Pero **no pude ejecutar `make` literalmente**.
Propuesta: instalarlo (`winget install ezwinports.make`) para poder dejar evidencia de `make all` en la
Fase 7. No lo instalé porque es un cambio fuera de la carpeta del proyecto.

**T-2 El repositorio Git estaba en la carpeta de usuario.**
La carpeta estaba dentro de un repositorio Git con raíz en `C:\Users\dazam` (sin commits, con todo el
perfil como "sin seguimiento"). Hice `git init` **dentro de la carpeta del proyecto** para que los commits
no toquen ese repositorio. Ese `.git` en la carpeta de usuario parece accidental; no lo toqué.

**T-3 Se usa el `psql` del contenedor, no el del equipo.**
El equipo tiene `psql` 18; el servidor es 16. Los scripts ejecutan `psql` dentro del contenedor
(`docker compose exec`) con `db/` montado en solo lectura, para que cliente y servidor coincidan y no
haya dependencias del host. El puerto `127.0.0.1:5433` queda para herramientas gráficas.

**T-4 La carpeta se llama `CE_RE`, no `repuestos-exactos-db`.**
No afecta: `docker-compose.yml` fija `name: repuestos-exactos-db` y el volumen `repuestos_exactos_pgdata`.

### Roles y propiedad

**T-5 Membresías para `ALTER FUNCTION ... OWNER TO app_funciones`** *(verificado, `docs/evidencia/fase0_experimentos.txt`)*.
PostgreSQL 16 exige dos cosas a quien cambia el dueño: poder hacer `SET ROLE` al nuevo dueño, y que el
nuevo dueño tenga `CREATE` en el esquema. Propuesta para `V000`:
`GRANT app_funciones TO app_owner WITH INHERIT FALSE, SET TRUE` y `GRANT CREATE ON SCHEMA public TO app_funciones`.
Trade-off: `app_owner` puede convertirse en un rol con `BYPASSRLS`; es aceptable porque `app_owner` ya es
dueño de las tablas y no se usa en ejecución. Alternativa descartada: hacer el `ALTER ... OWNER` como
superusuario fuera del `SET ROLE`, que rompe la regla "V001+ corre como `app_owner`".

**T-6 `BYPASSRLS` no es `GRANT`.** `app_funciones` salta las políticas pero igual necesita privilegios de
tabla. Recibirá `GRANT` explícitos y mínimos (por ejemplo `SELECT, UPDATE` en `usuario_credencial`,
`INSERT` en `auditoria_operacion`). Además, desde PostgreSQL 15 `PUBLIC` ya no tiene `CREATE` en `public`:
`V000` debe dar `CREATE, USAGE` a `app_owner`.

**T-7 ⚠ El enunciado pide que la auditoría registre `current_user`, pero dentro de una función `SECURITY DEFINER` eso siempre vale `app_funciones`** *(verificado)*.
Propuesta: la columna `rol` se llena con `current_setting('role')` (que conserva `taller_mecanico`) y, si
vale `none` (semillas, migraciones), con `session_user`.

### Cotizaciones

**T-8 ⚠ El `FOR UPDATE` del cierre no basta por sí solo para bloquear inserciones tardías de detalle.**
El enunciado explica que la FK del detalle toma `FOR KEY SHARE` sobre la cabecera y eso choca con el
`FOR UPDATE` del cierre: correcto. Pero la FK se comprueba **después** del trigger `BEFORE INSERT` que
verifica si la cabecera está cerrada. En `READ COMMITTED`, un `INSERT` concurrente puede leer la cabecera
"abierta", quedar esperando en la FK, y completarse tras el cierre → detalle agregado a una cotización
cerrada con el total ya congelado. Propuesta **[OBLIGATORIA]**: el trigger del detalle lee la cabecera con
`SELECT ... FOR KEY SHARE`, de modo que espera al cierre y relee la fila ya cerrada. Lo demostrará
`db/tests/concurrencia.sh`.

**T-9 ⚠ ¿Quién calcula los precios del detalle?**
Si el mecánico inserta `precio_referencia_snapshot`, `margen_pct_snapshot` y `precio_unitario`, podría
enviar cualquier valor. Propuesta **[RECOMENDADA]**: un trigger `BEFORE INSERT` en `cotizacion_detalle`
copia nombre, marca, perfil y precio desde `repuesto`, el margen desde `taller_configuracion`, y calcula
`precio_unitario`; el cliente solo envía `repuesto_id` y `cantidad`. Con privilegios por columna, el
mecánico solo puede actualizar `cantidad`.

**T-10 Semántica de `vigente` mientras la cotización está abierta.**
Interpretación: una revisión nueva nace con `vigente = false` (borrador); al cerrarla pasa a `vigente` y
se apaga la anterior. Propuestas **[RECOMENDADAS]**: `CHECK (NOT vigente OR cerrada_en IS NOT NULL)`
(solo una cerrada puede ser vigente), índice único parcial `(sesion_id) WHERE cerrada_en IS NULL` (un solo
borrador por sesión) y rechazar cotizaciones nuevas en sesiones `completado` o `cancelado`. El cierre **no**
cambia el estado de la sesión: son dos operaciones explícitas (`fn_cerrar_cotizacion` y `fn_cambiar_estado_sesion`).

**T-11 "Mecánico sin acceso a precios maestros" frente a "SELECT en catálogos".**
Para armar la matriz hay que leer `repuesto.precio_referencia`. Interpreto "sin acceso" como **sin escritura**.
Si el costo no debe ser visible para el mecánico, la alternativa es quitarle el `SELECT` de esa columna y
entregar la matriz mediante una función definidora que solo devuelva `precio_venta` (más complejo; no lo
propongo por defecto).

### Seguridad

**T-12 PgBouncer no forma parte del prototipo.** El patrón (`SET LOCAL`, `set_config(..., true)`) es
compatible con *transaction pooling* por construcción, pero no se prueba contra un PgBouncer real.
Agregar el servicio al `docker-compose.yml` es **[AVANZADA]**.

**T-13 Parámetros de log.** El enunciado fija el `command` del contenedor solo con `log_statement=none`.
Para que la contraseña no aparezca en mensajes de error haría falta además
`log_min_error_statement=panic` y `log_parameter_max_length_on_error=0`. Propuesta: respetar el `command`
pedido y documentar estos parámetros en `docs/seguridad.md`. Si prefieres que los agregue al compose, es una línea.

**T-14 Login.** (a) `fn_autenticar_usuario` debe **devolver** el fallo, no lanzar excepción: una excepción
revertiría el contador de intentos y el registro de auditoría. (b) Si el email no existe, se ejecuta igual
un `crypt()` contra un hash ficticio para no delatar por tiempo qué emails existen **[RECOMENDADA]**.
(c) Un `LOGIN_FALLIDO` de un email inexistente queda con `taller_id NULL`: ningún taller lo ve por RLS;
solo la plataforma. (d) El email intentado no se guarda en auditoría.

**T-15 Email único global.** Propuesta: `CHECK (email = lower(email))` más `UNIQUE (email)`, sin la extensión
`citext`. Efecto lateral declarado: al crear un usuario, el error de unicidad revela que ese email existe
en algún taller.

**T-16 Visibilidad del mecánico sobre vehículos bloqueados.** El estado de tratamiento vive en `titular`,
no en `vehiculo`. Propuesta: la política del mecánico sobre `vehiculo` exige `anonimizado_en IS NULL` y que
el titular, si existe, sea visible para él (subconsulta sobre `titular`, que ya filtra por su propia
política). Consecuencia: `/history` usa `LEFT JOIN` hacia `vehiculo`, y una sesión de un vehículo oculto se
muestra sin patente en lugar de desaparecer.

**T-17 Auditor y patente/VIN.** El enunciado solo excluye las columnas de identidad del **titular**. Lo
aplico literal: el auditor ve patente y VIN. Si se prefiere el criterio más prudente (son datos personales
indirectos), se quitan con el mismo mecanismo de privilegios por columna.

### Privacidad y operación

**T-18 Proceso periódico de anonimización.** La imagen `postgres:16` no trae `pg_cron`.
`fn_anonimizar_vencidos()` se implementa y se prueba, pero su programación (cron del sistema o del backend,
ejecutado como `app_owner`) solo se documenta. `pg_cron` es **[AVANZADA]**.

**T-19 `identificador_hmac`.** Propuesta: único por taller (`UNIQUE (taller_id, identificador_hmac)` parcial
donde no es nulo), para detectar al mismo titular sin guardar el RUT. Al anonimizar pasa a `NULL`.

**T-20 `auditoria_operacion.registro_id`.** Las tablas de enlace tienen PK compuesta. Propuesta:
`registro_id BIGINT` anulable; para `falla_sesion` queda `NULL` y la clave completa va en `datos_nuevos`.

**T-21 Control de migraciones aplicadas.** `migrate.sh` hoy aplica todos los archivos en orden sobre una
base vacía (es lo que exige el criterio de aceptación). Una tabla de control con versión y *checksum*, como
la de Flyway, lo haría re-ejecutable. Propuesta: **[AVANZADA]**, documentarlo en `docs/operacion.md` y no
agregar el objeto al prototipo.

**T-22 `id_publico` en catálogos.** La API devuelve repuestos, componentes, marcas y modelos, así que también
llevan `id_publico`. El DTC se expone por su `codigo`, que ya es público y único.

---

## 5. Verificación de la Fase 0

Evidencia en `docs/evidencia/fase0_entorno.txt` y `docs/evidencia/fase0_experimentos.txt`.

| Comprobación | Resultado |
|---|---|
| `docker compose up -d --wait` | contenedor `repuestos_exactos_db` sano, puerto `127.0.0.1:5433` |
| `SELECT version()` | PostgreSQL 16.15 |
| Parámetros | `shared_preload_libraries=pg_stat_statements`, `password_encryption=scram-sha-256`, `log_statement=none`, `read committed`, UTC |
| Secretos vía `psql -v` | `clave_backend` y `clave_demo` definidas (no se imprime el valor) |
| `reset` → `migrate` → `seed` → `test` | código 0 (sin migraciones, semillas ni pruebas todavía) |
| `ON_ERROR_STOP` | un error detiene la ejecución con código 1 |

**No verificado:** la ejecución literal de `make` (T-1) y `make perf` (`db/perf/run.sh` se crea en la Fase 5).

---

## 6. Resolución de temas y novedades de la Fase 1

### 6.1 Temas de la Fase 0

| Tema | Resolución |
|---|---|
| T-7, T-8, T-9, T-11, T-17 | **Aprobados explícitamente** por el usuario, con la propuesta indicada en cada uno |
| Columnas enmascaradas adicionales (decisión abierta d) | **Aprobadas** |
| T-2, T-3, T-4 (desviaciones de entorno) | **Aceptadas** |
| T-1 (`make`) | Sin instalar: se sigue verificando con los scripts. Queda pendiente para la evidencia de `make all` en la Fase 7 |
| T-5, T-6, T-10, T-12 a T-16, T-18 a T-22 | Sin objeción: se aplica la propuesta |

### 6.2 Temas nuevos surgidos al modelar

Mismo criterio: si no dices nada, aplico la propuesta. ⚠ marca lo que conviene que leas antes de la Fase 2.

**T-23 ⚠ "Normalizada hasta BCNF" necesita un matiz para la defensa.**
Al escribir las dependencias funcionales tabla por tabla, el `taller_id` propagado (decisión 1) resulta ser
una violación formal: de **2FN** en `falla_sesion` y `cotizacion_detalle` (depende de parte de la clave),
de 3FN en `sesion_diagnostico`, `consentimiento_titular` y `solicitud_derecho_titular`, y de BCNF en
`cotizacion`. Además `precio_unitario`, `estado` y `estado_tratamiento` son atributos derivables (3FN).
No reabro la decisión: `docs/modelo/04_normalizacion.md` §4.5 declara cada desviación, la forma que
incumple y la restricción que impide la inconsistencia. Lo señalo porque la formulación defendible es
"BCNF con desviaciones deliberadas y protegidas", no "todo en BCNF".

**T-24 `cotizacion_detalle` con PK compuesta `(cotizacion_id, repuesto_id)`.**
Es una tabla de enlace cotización ↔ repuesto, así que sigue la convención de PK natural: un repuesto aparece
una vez por cotización y la repetición se expresa con `cantidad`. Alternativa: `id` propio, si se quisieran
dos líneas del mismo repuesto (por ejemplo, con precios distintos), lo que hoy no es un requisito.

**T-25 Valores de enums y de `canal` que el enunciado no lista.**
`tipo_finalidad_tratamiento`: `prestacion_servicio`, `contacto_seguimiento`, `marketing`.
`tipo_estado_solicitud`: `recibida`, `en_proceso`, `resuelta`, `rechazada`.
`consentimiento_titular.canal`: texto con CHECK en `presencial`, `app`, `web`, `telefono`.
Son propuestas mínimas; cambiarlas no altera la estructura.

**T-26 CHECK con la fórmula del precio unitario** *(verificado, `fase1_experimentos.txt` E5)*.
`precio_unitario = ROUND(precio_referencia_snapshot * (1 + margen_pct_snapshot / 100))` como CHECK de
`cotizacion_detalle`, además del trigger que lo calcula. Consecuencia: si algún día cambia la regla de
redondeo, hay que reemplazar el CHECK (el nuevo como `NOT VALID` para no invalidar las filas históricas).

**T-27 La sesión queda a nombre de quien la crea (RN-25).**
La política RLS de inserción exige `usuario_id = app.usuario_id`. El enunciado dice "usuario mecánico" pero
una FK no puede exigir un rol; con esto, más el hecho de que solo `taller_mecanico` tiene `INSERT`, la regla
queda cubierta sin trigger.

**T-28 Columnas que no agregué por no inventar requisitos.**
`solicitud_derecho_titular` no tiene campo de observaciones (texto libre con riesgo de datos personales que
acabarían en la auditoría); `cotizacion` no tiene "creada por" (lo registra la auditoría);
`sesion_diagnostico` no tiene `creado_en` (es `iniciada_en`). Si necesitas alguna, dímelo.

**T-29 Rangos de compatibilidad solapados.**
La PK `(repuesto_id, modelo_vehiculo_id, anio_desde)` admite rangos disjuntos pero no impide solapados
(2015–2020 y 2018–2022). Impedirlo requiere `EXCLUDE` con `btree_gist` → **[AVANZADA]**. La matriz usa
`EXISTS`, así que un solapamiento no duplica resultados.

**T-30 Normalización a mayúsculas de la patente.**
Los CHECK rechazan minúsculas *(verificado, E7)* en lugar de convertirlas: la API normaliza y la BD
garantiza. Alternativa: un trigger que aplique `upper()`, que oculta errores del cliente; no lo propongo.

### 6.3 Verificación de la Fase 1

La fase es documental, pero las afirmaciones estructurales del modelo lógico se comprobaron en el motor
(`docs/evidencia/fase1_experimentos.txt`, transacción con `ROLLBACK`):

| Afirmación | Resultado |
|---|---|
| La FK compuesta exige `UNIQUE (id, taller_id)` en el padre | sin ella: `there is no unique constraint matching given keys` |
| Una referencia cruzada entre talleres es imposible | rechazada por la FK |
| `MATCH SIMPLE`: con la columna anulable en `NULL` la FK no se evalúa | inserción aceptada |
| No se puede cambiar el `taller_id` de un padre con hijos | rechazado por la FK |
| CHECK de la fórmula de precio | acepta el valor calculado, rechaza uno manipulado |
| Una vigente y un borrador por sesión; vigente solo si cerrada; total solo si cerrada | las cuatro violaciones rechazadas |
| `macaddr` normaliza y valida; regex de patente, VIN y DTC | casos válidos e inválidos según lo esperado |

**No verificado:** los diagramas Mermaid no se renderizaron (no hay herramienta instalada para hacerlo);
la sintaxis se revisó a mano. Conviene abrir `docs/modelo/02_modelo_conceptual.md` en un visor.

---

## 7. Fase 2: lo que cambió al implementar

### 7.1 Ajustes respecto de lo planificado

Ninguno reabre una decisión tomada; son correcciones que solo aparecieron al ejecutar.

| # | Ajuste | Motivo |
|---|---|---|
| 1 | El trigger del detalle bloquea la cabecera con **`FOR SHARE`**, no `FOR KEY SHARE` (refina T-8) | Un cierre hecho con `UPDATE` directo toma `FOR NO KEY UPDATE`, que **no** entra en conflicto con `FOR KEY SHARE`. `FOR SHARE` cubre tanto el cierre por función (`FOR UPDATE`) como el directo. |
| 2 | `migrate.sh` ejecuta cada archivo con `--single-transaction` | La primera ejecución de `V005` falló a mitad y dejó la migración aplicada a medias. Ahora un fallo no deja nada. |
| 3 | En `V005`, los `COMMENT ON FUNCTION` van **antes** del cambio de propietario | `COMMENT` exige ser el dueño; tras `OWNER TO app_funciones`, `app_owner` ya no lo es. |
| 4 | Los índices únicos parciales están en `V003`, no en `V006` | Son reglas de integridad (una vigente, un borrador, VIN y patente por taller), no optimizaciones. |
| 5 | Los `GRANT EXECUTE` de las funciones definidoras se hacen con `SET ROLE app_funciones` dentro de `V007` | Solo el dueño de una función puede otorgar privilegios sobre ella. |
| 6 | `usuario_credencial` tiene RLS activo y **ninguna** política | Segunda barrera además de la ausencia de `GRANT`. |
| 7 | `REVOKE` a `PUBLIC` sobre las vistas de `pg_stat_statements` | La extensión las crea legibles por todos. |
| 8 | Códigos `SQLSTATE` propios `RE001`–`RE012` | Para que la API distinga los errores de negocio sin analizar textos. |
| 9 | Nombre de política `pol_<tabla>_miembros_<operacion>` | Cuando una política aplica a los tres grupos; evita triplicar políticas idénticas. |

### 7.2 Objetos que el enunciado no pedía

| Objeto | Por qué fue necesario |
|---|---|
| `fn_establecer_contrasena` | Ningún rol puede escribir en `usuario_credencial`; sin esta función el administrador podría crear usuarios pero no darles contraseña. |
| `fn_crear_cotizacion` | Encapsula el `INSERT ... ON CONFLICT` de la idempotencia. |
| `fn_registrar_auditoria`, `fn_contexto_*` | Punto único de escritura en la auditoría y de lectura del contexto. |
| `fn_trg_cotizacion_preparar` | Garantiza que toda cotización nace como borrador (revisión, moneda, `vigente = false`). |

### 7.3 Reglas que quedaron fijadas en el código

- **Cierre de cotización:** `cerrada_en` es siempre la hora del servidor; no se puede cerrar sin detalle
  (`RE008`) ni si la sesión está en estado terminal (`RE004`); cerrar una ya cerrada la devuelve sin cambios.
- **Login:** 5 intentos fallidos consecutivos bloquean la cuenta 15 minutos (constantes de la función).
- **Contraseñas:** entre 8 caracteres y 72 bytes.
- **Retención:** cuentan las sesiones **no canceladas** de los vehículos del titular.
- **Repuesto no disponible:** no se puede agregar a una cotización (`RE010`).

### 7.4 Temas nuevos

Si no dices nada, queda como está.

**T-31 El mecánico puede "apagar" la cotización vigente sin cerrar otra.**
Necesita `UPDATE (vigente)` para que `fn_cerrar_cotizacion` funcione con sus privilegios, y el trigger
permite `vigente: true → false` en una cotización cerrada. Un `UPDATE` directo dejaría una sesión
`cotizado` sin cotización vigente; no corrompe nada (no podrá pasar a `completado` hasta cerrar otra
revisión), pero es un estado raro. Alternativa: hacer `fn_cerrar_cotizacion` `SECURITY DEFINER` y quitar
el privilegio, a costa de una función privilegiada más. No lo propongo.

**T-32 El administrador no puede cambiar el estado de una sesión.**
Siguiendo el enunciado, solo el mecánico escribe en sesiones y cotizaciones; el administrador las lee. Si
un administrador debe poder cancelar atenciones, es un `GRANT` y una política más.

**T-33 Cambio de contraseña por el propio usuario: no implementado.**
Solo el administrador fija contraseñas. El autoservicio exigiría verificar la contraseña actual →
**[AVANZADA]**, junto con el paso del hash al backend.

**T-34 Efecto sobre las semillas (Fase 3).**
Como `cerrada_en` y los timestamps de estado son siempre la hora del servidor, los datos de demostración
tendrán `iniciada_en` en el pasado pero fechas de cierre del momento de la carga. Es el precio de no
permitir que nadie —ni el superusuario— antedate un cierre. Las semillas recorrerán el flujo real
(crear, cotizar, cerrar, cambiar estado) en lugar de insertar estados finales a mano.

### 7.5 Verificación de la Fase 2

| Comprobación | Resultado | Evidencia |
|---|---|---|
| `reset` + `migrate` (V000–V008) sobre base vacía | 9 migraciones, código 0 | salida de la ejecución |
| Objetos | 21 tablas, 1 vista, 14 enums, 21 funciones, 32 triggers, 49 políticas | `esquema.txt` |
| Propietario de todos los objetos = `app_owner` (funciones definidoras = `app_funciones`) | 0 excepciones | `esquema.txt` §5, §13 |
| Tablas y columnas sin comentario, columnas `SERIAL`, tiempos sin zona, tablas con `taller_id` sin RLS forzado | 0 en todas | `esquema.txt` §13 |
| Funciones `SECURITY DEFINER` sin `search_path` | 0 | `esquema.txt` §5 |
| Privilegios de tabla de `app_backend_user` y `PUBLIC` | 0 | `esquema.txt` §7 |
| Flujo completo con `app_backend_user` (sin `BYPASSRLS`) | 25 errores, todos esperados | `fase2_humo.txt` |
| Secretos en archivos versionados | ninguno | búsqueda de los valores de `.env` |

**Riesgos que la ejecución no cubrió:**
- **Concurrencia real.** La prueba de humo es una sola sesión. El razonamiento sobre `FOR SHARE`, el orden
  de bloqueos y la idempotencia concurrente se demuestra en `db/tests/concurrencia.sh` (Fase 4).
- **PgBouncer.** No forma parte del prototipo.
- **Dependencias de versión:** `GRANT ... WITH INHERIT FALSE, SET TRUE` (PostgreSQL 16+), vistas
  `security_invoker` (15+). Probado solo en 16.15.
- **Rendimiento de las políticas con subconsulta** (`vehiculo`, `consentimiento_titular`) y utilidad real
  de cada índice: se miden en la Fase 5.
- La prueba de humo **no** es la suite formal: no imprime PASS/FAIL ni corta la ejecución. Eso es la Fase 4.

---

## 8. Fase 3: semillas, consultas y transacciones

### 8.1 Qué se construyó

| Entregable | Dónde | Detalle |
|---|---|---|
| Semillas | `db/seeds/01`–`04`, `99_resumen.sql`, `incluir/flujo_atencion.sql` | catálogos, 2 talleres, usuarios, operación y derechos del titular |
| Consultas de lectura | `db/queries/q01`–`q08` | 23 sentencias `PREPARE`; contrato en `docs/consultas.md` |
| Sentencias de escritura | `db/queries/t01`–`t03` | 15 sentencias `PREPARE`; `docs/transacciones.md` |
| Demostraciones | `db/queries/demo_consultas.sql`, `demo_transacciones.sql` | ejecutadas con `app_backend_user`; no modifican la base |
| Evidencia | `db/scripts/evidencia_fase3.sh` → `docs/evidencia/fase3_*.txt` | falla si aparece un error no esperado |

### 8.2 Decisiones de implementación

Ninguna reabre una decisión tomada.

| # | Decisión | Motivo |
|---|---|---|
| 1 | Las semillas operativas se cargan **asumiendo el rol de taller** (`SET LOCAL ROLE` + contexto) dentro de la sesión de superusuario | Pasan por los `GRANT`, las políticas RLS y los triggers reales; la auditoría queda con `taller_mecanico` / `taller_admin` y no con `postgres`. Solo los catálogos y el alta del taller con su primer administrador se hacen como plataforma. |
| 2 | Las atenciones de las semillas recorren el flujo real (`incluir/flujo_atencion.sql`) | Consecuencia de T-34: ninguna fila se inserta en estado final. Solo `iniciada_en` se antedata. |
| 3 | Las semillas se enlazan por clave natural y **no son re-ejecutables**; `seed.sh` se niega a cargar sobre una base con datos | `make all` siempre parte de `reset`. Evita una carga a medias. |
| 4 | `99_resumen.sql` verifica la carga y aborta si falla | Comprueba que toda línea cotizada sea compatible con el vehículo y responda a un DTC de la sesión, que todo usuario tenga credencial y que la auditoría no contenga columnas enmascaradas. |
| 5 | Toda consulta es un `PREPARE` con parámetros `$n` | Es el texto exacto que enviará el backend; las pruebas (Fase 4) y la medición (Fase 5) ejecutan las mismas sentencias, no copias. |
| 6 | Las consultas **no** filtran por `taller_id` | El aislamiento es de RLS; duplicar el filtro distorsiona las estimaciones del planificador y no agrega protección. Sin contexto devuelven cero filas. |
| 7 | Los padres se resuelven por `id_publico` dentro de la sentencia de escritura | Un `id_publico` de otro taller no se encuentra: cero filas, sin revelar si existe. `taller_id` y `usuario_id` nunca vienen del cliente. |
| 8 | Crear sesión con sus fallas es **una** sentencia (CTE con dos `INSERT`) | Atómica aunque el backend olvide abrir la transacción. |
| 9 | Nivel `READ COMMITTED` + bloqueos explícitos, no `SERIALIZABLE` | Las reglas multi-fila ya están cubiertas por `FOR UPDATE`/`FOR SHARE` e índices únicos; se evitan reintentos por fallo de serialización. |

### 8.3 Temas nuevos

Si no dices nada, queda como está. ⚠ marca lo que conviene leer.

**T-35 ⚠ La base no impide una sesión sin fallas.**
El dominio dice que una sesión sin DTC no tiene sentido (§1.7 del modelo), pero ninguna restricción lo
exige: `tx_crear_sesion` con un arreglo vacío crearía la sesión y devolvería `fallas_registradas = 0`
(deducido de la sentencia; no se ejecutó ese caso). Propuesta: lo valida la API, que rechaza el arreglo
vacío antes de llamar. Alternativa en la base: un *constraint trigger* diferido sobre `sesion_diagnostico`;
no lo propongo porque complica la carga de datos.

**T-36 ⚠ La auditoría es la única respuesta con ids internos.**
`q_auditoria` devuelve `id`, `registro_id` y los JSON `datos_*`, que contienen `id` y `taller_id`
secuenciales. Es inherente a una bitácora forense y solo la leen el administrador y el auditor del taller.
Para cumplir "la API nunca expone ids secuenciales" también aquí habría que traducir cada JSON tabla por
tabla; propongo declararlo como excepción.

**T-37 Una línea de cotización puede ser de un repuesto que la matriz no ofreció.**
La matriz filtra por compatibilidad y por DTC; `cotizacion_detalle` solo exige que el repuesto exista y
esté disponible. Propuesta: no restringir (el mecánico puede agregar un repuesto por criterio propio); las
semillas sí lo verifican.

**T-38 Para el mecánico, la matriz de una sesión con vehículo oculto queda vacía.**
Si el titular fue bloqueado o anonimizado, el mecánico no ve el vehículo y la matriz no puede filtrar por
modelo y año: devuelve cero filas en lugar de una matriz sin filtro. Coherente con T-16.

**T-39 Los mensajes de error de la base contienen ids internos.**
Por ejemplo `el repuesto 32 no esta disponible`. La API debe decidir por `SQLSTATE` y redactar su propio
mensaje (`docs/consultas.md` §4).

**T-40 `identificador_hmac` en las semillas.**
Se simula con `hmac()` de `pgcrypto` y la clave de demostración sobre identificadores ficticios, para no
escribir ningún secreto. En producción lo calcula el backend con una clave propia que la base no conoce.

**T-41 La prueba de humo de la Fase 2 exige una base sin semillas.**
Inserta sus propios datos mínimos (por ejemplo la marca `Toyota`), que chocan con los de las semillas. Queda
como registro histórico; la suite de la Fase 4 se escribe sobre las semillas.

**T-42 Las rutas HTTP son orientativas.**
El repositorio no contiene una especificación de la API; `docs/consultas.md` fija parámetros, columnas y
roles de cada sentencia, que es lo que compete a la base. Si existe un contrato de rutas del frontend,
conviene contrastarlo.

### 8.4 Verificación de la Fase 3

| Comprobación | Resultado | Evidencia |
|---|---|---|
| `reset` → `migrate` → `seed` → `test` sobre base vacía | código 0 (9 migraciones, 5 archivos de semillas; aún sin pruebas) | salida de la ejecución |
| Catálogos | 6 marcas, 11 modelos, 12 DTC, 10 componentes, 42 repuestos (19 genuinos, 12 OEM, 11 genéricos; 1 no disponible), 297 compatibilidades | `fase3_semillas.txt` |
| Operación | 2 talleres, 8 usuarios, 7 titulares, 11 vehículos, 16 sesiones en los cuatro estados, 14 cotizaciones (10 vigentes, 3 borradores) | `fase3_semillas.txt` |
| Privacidad en las semillas | 1 titular bloqueado y 1 anonimizado (sin nombre); auditoría sin columnas enmascaradas | `fase3_semillas.txt` y verificación de `99_resumen.sql` |
| Las 38 sentencias se preparan con `app_backend_user`; las de lectura se ejecutan sin errores | 0 errores | `fase3_consultas.txt` |
| Aislamiento en lectura y escritura con ids públicos de otro taller | cero filas en todas | `fase3_consultas.txt` §10, `fase3_transacciones.txt` TX-10 |
| Transacciones con sus errores de negocio | 18 errores, todos esperados | `fase3_transacciones.txt` |
| La demostración de transacciones no deja cambios | conteos idénticos antes y después | `fase3_transacciones.txt`, sección final |
| Secretos en archivos versionados y en la evidencia | ninguno | búsqueda de los valores de `.env` |

**Riesgos que la ejecución no cubrió:**
- **Concurrencia real.** Las demostraciones usan una sola conexión (Fase 4, `db/tests/concurrencia.sh`).
- **Planes de ejecución.** Ninguna consulta se midió: con 16 sesiones cualquier plan es instantáneo. Que
  `q_historial` use sus índices con los parámetros opcionales, y el costo de `q_matriz` y del dashboard con
  volumen, se mide en la Fase 5.
- **Roles por sentencia.** La tabla de roles de `docs/consultas.md` se deduce de los `GRANT`; cada sentencia
  se ejecutó con un rol permitido y solo hay un caso denegado (TX-9a). La matriz completa rol × sentencia es
  de la suite de la Fase 4.
- **Sentencias de escritura no ejercitadas** por la demostración: `tx_cambiar_activo_usuario` y
  `tx_registrar_dispositivo` (solo se comprobó que se preparan).
- **`make`** sigue sin instalarse (T-1): se verificó con los scripts.

---

## 9. Fase 4: pruebas

Detalle en `docs/pruebas.md`. Ninguna migración cambió en esta fase: la suite no encontró defectos en el
esquema. Los fallos que aparecieron al escribirla eran de las propias pruebas (un conteo mal calculado, una
expectativa de `SQLSTATE` equivocada, una aserción que dependía del orden de ejecución); se corrigió la
prueba explicando por qué, sin relajar lo que comprueba.

### 9.1 Qué se construyó

| Entregable | Dónde |
|---|---|
| 9 archivos SQL, 456 pruebas | `db/tests/01`–`09_*.sql` |
| Aserciones y cambio de rol | `db/tests/incluir/` |
| Concurrencia, 12 pruebas con dos conexiones reales | `db/tests/concurrencia.sh` |
| Control negativo de la concurrencia | `db/tests/control_negativo.sh` |
| Ejecutor | `db/tests/run_all.sh` (`make test`) |
| Evidencia | `db/scripts/evidencia_fase4.sh` → `docs/evidencia/fase4_*.txt` |

### 9.2 Temas nuevos

Si no dices nada, queda como está. ⚠ marca lo que conviene leer.

**T-43 ⚠ El contenedor acepta conexiones locales sin contraseña.**
La prueba de concurrencia se conecta como `app_backend_user` por el socket Unix del contenedor, y funciona
sin clave porque la imagen `postgres:16` deja `local all all trust` en `pg_hba.conf`. Es una propiedad del
entorno de desarrollo (quien entra al contenedor ya es administrador), no del diseño: por TCP sí se exige
SCRAM. Lo dejo anotado para `docs/operacion.md` (Fase 6): en producción `pg_hba.conf` debe exigir
`scram-sha-256` también en `local`.

**T-44 Un trigger `BEFORE` se ejecuta antes que el `WITH CHECK` de RLS.**
Insertar una línea de detalle con el `taller_id` de otro taller se rechaza con `RE009` (el trigger no
encuentra la configuración de ese taller) y no con `42501`. El rechazo es el mismo; cambia el código. Lo
dejo así: forzar el `42501` exigiría que el trigger no leyera nada antes de la política.

**T-45 Las operaciones de la plataforma aparecen en la bitácora del taller, sin usuario.**
Un cambio hecho como superusuario sobre filas de un taller queda auditado con el `taller_id` de la fila y el
rol de sesión, y el administrador de ese taller lo ve con `usuario_nombre` vacío. Me parece el
comportamiento correcto (el taller ve que la plataforma tocó sus datos); lo señalo porque la API debe
mostrar "plataforma" en lugar de un nombre vacío.

**T-46 La prueba de concurrencia confirma transacciones y deja auditoría.**
Es inevitable (dos conexiones solo se ven tras un `COMMIT`). Crea y borra sus propios datos, pero sus
registros de auditoría permanecen: tras `make test` la bitácora del taller 1 tiene más filas que tras
`make seed`. Ninguna prueba depende de conteos absolutos de la auditoría, y `make all` parte de `reset`.

**T-47 Los roles de taller no tienen `TEMPORARY` sobre la base.**
Es consecuencia del `REVOKE ALL ON DATABASE ... FROM PUBLIC` de `V000` y es lo deseable. `09_consultas.sql`
lo otorga dentro de su transacción y el `ROLLBACK` lo revierte.

**T-48 Las pruebas contienen contraseñas literales de usar y tirar.**
Por ejemplo `Clave-Restablecida-9`, fijada y descartada dentro de una transacción con `ROLLBACK`. No son
secretos de ningún entorno; las claves reales siguen llegando solo por `psql -v`.

### 9.3 Verificación de la Fase 4

| Comprobación | Resultado | Evidencia |
|---|---|---|
| `reset` → `migrate` → `seed` → `test` sobre base vacía | código 0; 468 PASS, 0 FAIL | `fase4_pruebas.txt` |
| Repetir la suite sobre la misma base | código 0; 468 PASS | ejecución repetida |
| Errores SQL frente a pruebas de error, por archivo | coinciden en los 9 archivos (193 en total) | `fase4_pruebas.txt` |
| Concurrencia | 10 escenarios: B esperó a A en todos; sin interbloqueos | `fase4_pruebas.txt` |
| Control negativo de CON-01 | sin `FOR SHARE` la prueba falla; restaurado, pasa | `fase4_control_negativo.txt` |
| La base tras la suite | mismos conteos que tras las semillas, salvo la auditoría (T-46) | consulta tras la ejecución |
| Secretos en archivos versionados y en la evidencia | ninguno | búsqueda de los valores de `.env` |

**Riesgos que la ejecución no cubrió:** los de `docs/pruebas.md` §6 (rendimiento, PgBouncer, canal de
tiempo del login, concurrencia de la anonimización, controles negativos del resto de la suite).

---

## 10. Fase 5: rendimiento

Análisis completo en `docs/evidencia/rendimiento.md`. A diferencia de la Fase 4, esta sí cambió el esquema
y las consultas: la medición con volumen y con el rol real encontró tres problemas que ni las semillas ni
la suite podían mostrar.

### 10.1 Qué se construyó

| Entregable | Dónde |
|---|---|
| Carga de volumen (302 mil sesiones, 2 millones de registros de auditoría) | `db/perf/volumen.sql` |
| Medición con `EXPLAIN (ANALYZE, BUFFERS)` de las sentencias preparadas | `db/perf/medir.sql`, `medidas.sql`, `anteriores.sql` |
| Experimentos de índices, con y sin cada uno | `db/perf/experimentos_indices.sql` |
| Ejecutor (`make perf`): crea `<base>_perf`, mide y la elimina | `db/perf/run.sh` |
| Ajuste de índices | `db/migrations/V009__ajustes_rendimiento.sql` |
| Evidencia | `docs/evidencia/fase5_resumen.txt`, `fase5_medidas.txt`, `fase5_indices.txt`, `rendimiento.md` |

### 10.2 Qué cambió y por qué

| # | Cambio | Motivo medido |
|---|---|---|
| 1 | `q_historial` pasa a ser cuatro sentencias y `q_auditoria` dos, sin parámetros opcionales en el cursor | En el plan genérico la condición opcional quedaba como filtro: la página tras 75.000 sesiones leía 75.874 bloques (42 ms) en lugar de 427 (0,5 ms) |
| 2 | `V009`: se elimina `ix_sesion_diagnostico_estado` y se crea `ix_sesion_diagnostico_cotizado` (parcial) | Bajo RLS la igualdad de un enum no es *leakproof* y no puede ser condición de búsqueda de un índice: 12,3 ms con el índice original frente a 0,19 ms con el parcial |
| 3 | `q_dashboard_resumen` reescrita sobre los índices parciales y un rango del historial | 184 ms → 14,6 ms. Las cifras del período pasan a ser por cohorte de inicio (T-49) |
| 4 | `V009`: se eliminan `ix_usuario_taller` e `ix_solicitud_derecho_titular_taller_titular` | El experimento con y sin el índice no mostró una diferencia que los justifique |
| 5 | Nueva sentencia `q_consentimientos_titular` | `ix_consentimiento_titular_taller_titular` era útil (0,01 frente a 2,8 ms) pero ninguna consulta lo usaba; faltaba la lectura de consentimientos |
| 6 | Pruebas `ESQ-28` y `ESQ-29`, y pruebas de las sentencias nuevas (484 en total) | Resguardo contra la regresión del punto 2 |

Los índices de `V006` que `V006` mismo dejaba "a confirmar en la Fase 5" quedaron resueltos: de 16, se
eliminaron 3, se agregó 1 y el resto tiene su medición.

### 10.3 Temas nuevos

Si no dices nada, queda como está. ⚠ marca lo que conviene leer.

**T-49 ⚠ Las cifras del período del dashboard cambiaron de significado.**
Antes: sesiones *completadas dentro* del período (por `completada_en`). Ahora: de las sesiones *iniciadas*
en el período, cuántas están completadas (cohorte). Lo cambié porque la forma anterior obliga a recorrer
todas las sesiones del taller o a agregar un índice por `completada_en` y otro por `cancelada_en` a una
tabla con siete. Si el negocio necesita "completadas este mes" en sentido estricto, la alternativa es ese
par de índices parciales; dímelo y lo mido.

**T-50 `q_solicitudes_derecho` no pagina.**
Devuelve todas las solicitudes del taller. Con el volumen real (pocas por taller) no importa; con 18.750
tarda unos 38 ms. Propuesta: dejarla así en el prototipo y anotarlo como deuda.

**T-51 ⚠ El contenedor tiene 64 MB de memoria compartida (`/dev/shm`).**
Es el valor por defecto de Docker. El `VACUUM` paralelo de la base de volumen falló con
`could not resize shared memory segment` y hubo que usar `PARALLEL 0`. Las consultas paralelas grandes
pueden fallar igual. Se corrige con `shm_size` en `docker-compose.yml`; no lo toqué porque el enunciado fija
el `command` del servicio y prefiero que lo decidas tú. Va a `docs/operacion.md` (Fase 6).

**T-52 `make perf` tarda unos 6 minutos y necesita 1,2 GB libres.**
Casi todo es la carga del volumen (unos 5 minutos). Se puede reducir con `PERF_SESIONES_GRANDE`,
`PERF_AUDITORIA`, etc. No forma parte de `make all`.

**T-53 El planificador estima cada taller como el promedio.**
Consecuencia de pasar el taller por `current_setting`: no hay estadísticas por valor. No tiene arreglo
dentro del diseño; se mitiga con la forma de las consultas (`docs/consultas.md` §3.6). Lo señalo porque es
la respuesta a "¿qué pasa si un taller es mucho más grande que los demás?".

**T-54 El comentario de cabecera de `V006` quedó parcialmente superado.**
Describe índices que `V009` eliminó. No lo edité: las migraciones ya aplicadas no se reescriben; `V009`
explica cada cambio.

### 10.4 Verificación de la Fase 5

| Comprobación | Resultado | Evidencia |
|---|---|---|
| `reset` → `migrate` (V000–V009) → `seed` → `test` | código 0; 484 PASS, 0 FAIL | `fase4_pruebas.txt` |
| Suite repetida sobre la misma base | 484 PASS | ejecución repetida |
| `make perf` (`bash db/perf/run.sh`) | código 0; 35 medidas y 8 experimentos sin errores | `fase5_*.txt` |
| Paginación profunda | 0,49 ms y 427 bloques, igual que la primera página (0,65 ms, 379) | `fase5_resumen.txt` M01, M02 |
| La corrección no depende del plan elegido | plan genérico forzado: 0,34 ms, 396 bloques | M06 |
| Dashboard | 14,6 ms frente a 184 ms de la versión anterior | M17, M17a |
| Enum bajo RLS | filtro (12,3 ms) frente a índice parcial (0,19 ms) | `fase5_indices.txt` E0 |
| Consultas y transacciones de la Fase 3 tras los cambios | sin errores; 18 errores esperados | `fase3_*.txt` regenerados |
| La base principal tras `make perf` | intacta (la medición usa `<base>_perf`) | suite en verde después de medir |

**Riesgos que la ejecución no cubrió:** los de `docs/evidencia/rendimiento.md` §9 (carga concurrente, caché
fría, variabilidad entre corridas, crecimiento de la auditoría, ajuste del servidor).

---

## 11. Fase 6: operación

Detalle en `docs/operacion.md`. Ninguna migración cambió: el esquema es el de la Fase 5. Cambiaron el
entorno (`docker-compose.yml`), los scripts y la suite.

### 11.1 Resolución de los temas pendientes

| Tema | Resolución |
|---|---|
| T-49 (cifras del dashboard por cohorte de inicio) | **Aprobado** por el usuario: queda como está |
| T-51 (`/dev/shm` de 64 MB) | **Aprobado**: `shm_size: 256mb`. `db/perf/run.sh` volvió al `VACUUM` paralelo |
| T-43 (`trust` en el socket local) | **Aprobado**: `pg_hba.conf` exige `scram-sha-256` en todas sus reglas, mediante `POSTGRES_INITDB_ARGS` |
| T-13 (parámetros del log) | Aplicados en el `command` del compose, **además** de los tres que fija el enunciado (ver T-55) |
| T-18 (programación de `fn_anonimizar_vencidos`) | `db/scripts/anonimizar_vencidos.sh`, ejecutado; la tarea programada solo se documenta |
| T-21 (control de migraciones) | Sin cambios: **[AVANZADA]**, documentado en `docs/operacion.md` §9 |

### 11.2 Qué se construyó

| Entregable | Dónde |
|---|---|
| Respaldo, verificación no destructiva y restauración | `db/scripts/respaldar.sh`, `verificar_respaldo.sh`, `restaurar.sh` |
| Prueba de recuperación ante pérdida total | `db/scripts/prueba_restauracion.sh`, `db/ops/huella.sql` |
| Observabilidad y mantenimiento | `db/scripts/estado.sh`, `db/ops/observabilidad.sql`, `db/scripts/mantenimiento.sh` |
| Retención de la auditoría | `db/scripts/purgar_auditoria.sh`, `db/ops/purgar_auditoria.sql` |
| Proceso periódico de privacidad | `db/scripts/anonimizar_vencidos.sh` |
| 30 pruebas de operación (514 en total) | `db/tests/10_operacion.sql`, `db/tests/operacion.sh` |
| Evidencia | `db/scripts/evidencia_fase6.sh` → `docs/evidencia/fase6_*.txt` |

### 11.3 Hallazgos de la ejecución

| # | Hallazgo | Qué se hizo |
|---|---|---|
| 1 | Una sentencia que falla se copiaba entera al log, con sus literales (`fase6_antes.txt` §A4) | `log_min_error_statement=panic`; `OPE-24` |
| 2 | `pg_stat_statements` guardaba en claro el `CREATE ROLE ... PASSWORD` de `V000` y un `EXPLAIN` del login con la clave de demostración (`fase6_antes.txt` §A5): normaliza las constantes de las consultas, no las de las sentencias de utilidad | `migrate.sh`, `seed.sh`, `restaurar.sh` y `perf/run.sh` vacían las estadísticas al terminar; `OPE-07` |
| 3 | El log de sentencias lentas registra los literales (`OPE-26`), y las migraciones y semillas envían las claves como literal | `log_min_duration_statement` queda apagado (`OPE-03`); las consultas lentas se buscan en `pg_stat_statements` |
| 4 | Dentro del contenedor cualquiera se conectaba como superusuario sin clave (`fase6_antes.txt` §A2) | T-43; los scripts se autentican con `PGPASSWORD` tomado del entorno del contenedor |
| 5 | Tras restaurar, `pg_dump` lista en otro orden los roles de 8 políticas (`TO a, b, c` se guarda como OID y el clúster restaurado crea los roles en otro orden) | No es un defecto: la comparación de esquemas normaliza ese orden |
| 6 | Una supresión solicitada después del respaldo desaparece al restaurar (`fase6_respaldo.txt`, pasos 3 y 6) | `restaurar.sh` ejecuta `fn_anonimizar_vencidos()`; lo demás debe reaplicarse a mano (T-57) |

### 11.4 Temas nuevos

Si no dices nada, queda como está. ⚠ marca lo que conviene leer.

**T-55 ⚠ El `command` del contenedor tiene más parámetros que los tres del enunciado.**
T-13 proponía respetar el `command` y solo documentar los parámetros del log. Al ejecutar el experimento,
la fuga resultó real (hallazgo 1), y como ya estabas autorizando cambios al compose para T-43 y T-51,
agregué cinco parámetros `-c` a continuación de los tres originales, que no se tocaron. Si el `command`
debe quedar literalmente como en el enunciado, se quitan esas líneas y habría que retirar las pruebas que
los vigilan (`OPE-02`, `OPE-04`, `OPE-24`) y dejar la sección como recomendación.

**T-56 ⚠ `pg_hba` se configura con `POSTGRES_INITDB_ARGS`, no con un archivo propio.**
Así no se toca el `command` y el archivo lo genera `initdb`. El costo: solo se aplica al **crear** el
volumen. Quien tenga un volumen anterior a esta fase debe hacer `reset`: con el `pg_hba` antiguo fallarían
`OPE-01`, `OPE-20` y `OPE-21` (deducido; no se ejecutó la suite nueva sobre un volumen antiguo). La alternativa es
versionar un `pg_hba.conf` y montarlo con `-c hba_file=...`; la dejo para producción, donde además lleva
`hostssl` y la red del backend (`docs/operacion.md` §4).

**T-57 ⚠ Restaurar un respaldo revive datos suprimidos.**
Es inherente a cualquier respaldo. Lo que la base puede hacer sola está hecho (anonimizar los bloqueos
vencidos tras restaurar). Reaplicar las solicitudes posteriores al respaldo exige que su registro exista
**fuera** de la base: es un requisito para el backend o para el procedimiento del responsable, y un
argumento para conservar los respaldos poco tiempo. **Validar legalmente** el plazo.

**T-58 ⚠ El plazo de retención de la auditoría no está definido.**
`purgar_auditoria.sh` no tiene valor por defecto y rechaza un plazo menor que la mayor `retencion_anios` de
un taller. Es un criterio de diseño mío, no una regla del enunciado ni una afirmación jurídica. Si prefieres
un parámetro de plataforma con valor por defecto, dímelo.

**T-59 La purga salta la inmutabilidad con `session_replication_role`.**
Solo puede hacerlo un superusuario y solo dura la transacción. No agrega ningún objeto al esquema. La
alternativa (una función definidora de purga) dejaría un camino de borrado permanente; no la propongo.

**T-60 La evidencia de la Fase 5 no se regeneró.**
`db/perf/run.sh` se volvió a ejecutar completo para validar los cambios (autenticación y `VACUUM`
paralelo), pero su salida quedó en `fase6_perf.txt` y los `fase5_*.txt` se conservaron: son los que cita
`rendimiento.md` y los tiempos varían entre corridas.

**T-61 Los respaldos no se cifran ni se copian fuera del equipo.**
Quedan en `backups/` (ignorada por Git). Contienen datos personales y hashes bcrypt. Cifrado, copia externa
y programación están documentados como pendientes de producción (`docs/operacion.md` §2).

**T-62 `make` sigue sin instalarse (T-1).**
Los objetivos nuevos del `Makefile` (`backup`, `verify-backup`, `restore`, `restore-test`, `status`) se
verificaron ejecutando el script en que delega cada uno, no con `make`.

### 11.5 Verificación de la Fase 6

| Comprobación | Resultado | Evidencia |
|---|---|---|
| `reset` → `migrate` (V000–V009) → `seed` → `test` con el compose nuevo | código 0; 514 PASS, 0 FAIL | `fase4_pruebas.txt` |
| Control negativo de CON-01 con la autenticación nueva | detecta el defecto; restaurado, pasa | `fase4_control_negativo.txt` |
| Respaldo → eliminación del volumen → restauración | datos idénticos (md5 de las 21 tablas y secuencias) y esquema idéntico | `fase6_respaldo.txt` §1–§6 |
| Suite sobre la base restaurada | código 0; 514 PASS | `fase6_respaldo.txt` §7 |
| Verificación no destructiva en base temporal | respaldo nuevo: idéntico; respaldo anterior a la suite: lista lo que cambió | `fase6_respaldo.txt` §8, §9 |
| `pg_hba.conf` | 7 reglas, todas `scram-sha-256`; sin clave la conexión local se rechaza | `fase6_operacion.txt` §1; `OPE-20` a `OPE-23` |
| Log tras la corrida completa | 206 líneas `ERROR`, 0 líneas `STATEMENT`, 0 apariciones de las claves de `.env` | `fase6_operacion.txt` §4, §5 |
| `pg_stat_statements` | 0 sentencias con claves | `fase6_operacion.txt` §5; `OPE-07` |
| Memoria compartida y `VACUUM` paralelo con volumen | 256 MB; `db/perf/run.sh` completo con código 0 | `fase6_operacion.txt` §3; `fase6_perf.txt` |
| Purga de auditoría | prueba en transacción y con el script real; simulación y rechazo de plazo corto | `OPE-09` a `OPE-17`, `OPE-29` a `OPE-31`; `fase6_operacion.txt` §7 |
| Consultas y transacciones de la Fase 3 con la autenticación nueva | sin errores; 18 errores esperados | `fase3_*.txt` regenerados |
| Secretos en archivos versionados y en la evidencia | ninguno | búsqueda de los valores de `.env` |

**Riesgos que la ejecución no cubrió:** los de `docs/operacion.md` §10 (recuperación a un punto en el
tiempo, cifrado y copia externa de respaldos, TLS, tiempos con volumen, programación real de las tareas) y
todo lo marcado **[NO EJECUTADO]** en ese documento. `make` sigue sin instalarse (T-1, T-62).

---

## 12. Fase 7: cierre

Dictamen completo en `docs/dictamen.md`. A diferencia de lo previsto, el cierre **sí cambió el esquema**:
la revisión final encontró un defecto en la configuración de las funciones y se corrigió con una migración
nueva (`V010`). Ninguna decisión tomada se reabrió.

### 12.1 Resolución de los temas pendientes

| Tema | Resolución |
|---|---|
| T-55 (parámetros del log en el `command` del compose) | **Aprobado** por el usuario: se mantienen los cinco parámetros agregados y las pruebas que los vigilan |
| T-58 (purga de la auditoría condicionada a `retencion_anios`) | **Aprobado**: sin plazo por defecto; se rechaza un plazo menor que la mayor retención de un taller. El plazo sigue siendo una decisión legal a validar |
| T-60 (cifras de rendimiento de la Fase 5) | **Aprobado**: se conservan `fase5_*.txt` y `fase6_perf.txt`; la medición no se repitió en esta fase |
| T-56, T-57, T-59, T-61 | Sin objeción: quedan como están |
| T-1, T-62 (`make`) | **Sigue sin instalarse.** La evidencia de cierre ejecuta las recetas del `Makefile` tal como están escritas (T-67) |

### 12.2 Qué se construyó

| Entregable | Dónde |
|---|---|
| Dictamen final | `docs/dictamen.md` |
| Comprobaciones de catálogo y experimentos del dictamen | `db/tests/humo/fase7_dictamen.sql` |
| Corrección del `search_path` de las 21 funciones | `db/migrations/V010__search_path_pg_temp.sql` |
| 4 pruebas nuevas (518 en total) | `ESQ-30`, `ESQ-31` en `01_esquema.sql`; sombra de `pg_temp` en `07_auditoria.sql` |
| Evidencia | `db/scripts/evidencia_fase7.sh` → `docs/evidencia/fase7_cierre.txt`, `fase7_dictamen.txt`; `fase7_antes.txt` (captura única) |
| README final y revisión de coherencia entre documentos | `README.md`; lista de correcciones en `docs/dictamen.md` §7 |

### 12.3 Hallazgos de la ejecución

| # | Hallazgo | Qué se hizo |
|---|---|---|
| 1 | Con `search_path = pg_catalog, public`, `pg_temp` se busca primero para tablas: con el privilegio `TEMPORARY`, una tabla temporal `auditoria_operacion` recibía los registros de auditoría en lugar de la real (`fase7_antes.txt` B5) | `V010`: `pg_temp` explícito y al final en las 21 funciones; `ESQ-30`, `ESQ-31` y dos pruebas en `07_auditoria.sql` |
| 2 | Una sesión `completado` admite cambios de kilometraje y de fallas (B1) | No se corrigió: regla de negocio (T-63) |
| 3 | El mecánico puede fijar `iniciada_en`, de la que depende la retención (B2) | No se corrigió: afecta a las semillas (T-64) |
| 4 | `app_backend_user` no tiene tiempos de espera ni límite de conexiones (A6) | No se corrigió: los valores dependen del backend (T-65) |
| 5 | El administrador puede poner la retención en 0 antes de suprimir, y dejar al taller sin administrador (B3, B4) | No se corrigió: coherente con el modelo (T-66) |
| 6 | La primera versión de la consulta de claves foráneas sin índice del dictamen daba por cubierta `vehiculo.modelo_vehiculo_id` con un índice encabezado por `taller_id` | Se corrigió la consulta: son 11, todas deliberadas o medidas (`docs/dictamen.md` §3) |

### 12.4 Temas nuevos

Si no dices nada, quedan como están. ⚠ marca lo que conviene leer.

**T-63 ⚠ Una sesión en estado terminal sigue admitiendo cambios en su diagnóstico.**
El trigger protege el estado, no el resto: como mecánico, sobre una sesión completada se aceptan un cambio
de kilometraje, una falla nueva y un cambio de severidad (`fase7_dictamen.txt` B1). Quedan auditados.
Propuesta: un trigger en `falla_sesion` y `sesion_diagnostico` que rechace con `RE004` cuando la sesión es
terminal. No lo apliqué porque el enunciado no lo fija y puede ser legítimo corregir un DTC mal digitado
después de entregar el vehículo.

**T-64 ⚠ El cliente puede fijar `iniciada_en`, `otorgado_en` y `recibida_en`.**
El privilegio de columna existe porque las semillas antedatan atenciones con el rol del taller (T-34). Una
sesión con fecha de 2099 se acepta (B2), y de esa fecha depende el plazo de retención del titular.
Propuesta para producción: quitar esas columnas de los `GRANT INSERT` y cargar lo histórico como
plataforma. Obliga a reescribir las semillas; por eso no lo apliqué.

**T-65 ⚠ El rol de conexión no tiene tiempos de espera.**
`statement_timeout`, `lock_timeout` e `idle_in_transaction_session_timeout` valen 0 y `app_backend_user` no
tiene `CONNECTION LIMIT` (A6). Una transacción abandonada con un `FOR UPDATE` deja esperando sin plazo a
quien toque esa sesión. Propuesta: `ALTER ROLE app_backend_user SET ...` en una migración, con valores
acordados con el backend (por encima de los 4 segundos de la prueba de concurrencia).

**T-66 El administrador es el único control de la retención y de su propia cuenta.**
Con `retencion_anios = 0` la supresión anonimiza de inmediato aunque haya una atención reciente (B3), y un
administrador puede desactivarse y dejar al taller sin ninguno (B4). Es coherente con que el taller sea el
responsable de sus datos. Si la retención es una obligación legal, el mínimo debería fijarlo la
plataforma: **validar legalmente**.

**T-67 `make all` se evidenció sin `make`.**
`evidencia_fase7.sh` lee del `Makefile` las dependencias de `all` y la receta de cada objetivo, y las
ejecuta literalmente. Prueba que las recetas funcionan en ese orden; no prueba el programa `make`. Con
`make` instalado, el mismo script ejecuta `make all`.

**T-68 Otorgar `TEMPORARY` a un rol de taller pasa a ser una decisión a revisar.**
Con `V010` ya no permite evadir la auditoría, pero `ESQ-31` falla si alguien lo otorga: es deliberado.
`09_consultas.sql` lo sigue otorgando dentro de su transacción (T-47).

**T-69 La evidencia de las fases 3, 4 y 6 se regeneró sobre el esquema final.**
Sus archivos muestran ahora 518 pruebas y las cifras de esta corrida; `docs/operacion.md` y
`docs/pruebas.md` se actualizaron con ellas. Las tablas de verificación de las secciones 9 a 11 de este
documento conservan las cifras de su fase.

### 12.5 Verificación de la Fase 7

| Comprobación | Resultado | Evidencia |
|---|---|---|
| `reset` → `migrate` (V000–V010) → `seed` → `test`, con las recetas del `Makefile` | código 0; 518 PASS, 0 FAIL | `fase7_cierre.txt` §2 |
| Suite repetida sobre la misma base | 518 PASS | `fase7_cierre.txt` §4 |
| Objetos del esquema | 21 tablas, 1 vista, 14 enums, 21 funciones (6 definidoras), 32 triggers, 49 políticas, 68 índices | `fase7_cierre.txt` §3 |
| Sombra de `pg_temp`, antes y después de `V010` | antes: 1 registro desviado, 0 en la auditoría real; después: 0 y 1 | `fase7_antes.txt` y `fase7_dictamen.txt`, B5 |
| El guion del dictamen no deja cambios | kilometraje, fallas y privilegios intactos | `fase7_dictamen.txt` C |
| Respaldo → eliminación del volumen → restauración, con el esquema final | datos y esquema idénticos; 518 PASS sobre la base restaurada | `fase6_respaldo.txt` |
| Control negativo de CON-01 | detecta el defecto; restaurada la función (con su `search_path` de `V010`), pasa | `fase4_control_negativo.txt` |
| Consultas y transacciones de la Fase 3 | sin errores; 18 errores esperados | `fase3_*.txt` regenerados |
| Secretos en archivos versionados y en la evidencia | ninguno | `fase7_cierre.txt` §5 |

**Riesgos que la ejecución no cubrió:** los de `docs/dictamen.md` §8 (`make` literal, medición de
rendimiento no repetida, suplantación de `usuario` ante el login solo deducida, diagramas sin renderizar,
ausencia de un revisor independiente) y todo lo que cada documento declara en su sección "lo que no cubre".

### 12.6 Resolución final

Decisiones del usuario al recibir el cierre. Con ellas el desarrollo de la base de datos queda concluido.

| Tema | Resolución |
|---|---|
| `V010` y las 4 pruebas de `pg_temp` | **Aprobadas**: se mantienen |
| T-63 (sesión terminal modificable) | **Resuelto**: la base no cambia; impedir cambios sobre una sesión `completado` o `cancelado` es validación de la API |
| T-64 (fechas fijadas por el cliente) | **Resuelto**: la base no cambia; la API no acepta `iniciada_en`, `otorgado_en` ni `recibida_en` del cliente (las sentencias `tx_*` ya no las envían) |
| T-65 (tiempos de espera del rol de conexión) | **Resuelto**: configuración de producción (`ALTER ROLE app_backend_user SET ...` y `CONNECTION LIMIT`), con valores acordados con el backend |
| T-66 (retención y cuenta del administrador) | **Resuelto**: validación de la API (plazo mínimo de retención; no desactivar al último administrador) |

**Lo que esta resolución implica.** La base sigue aceptando esas operaciones si alguien ejecuta SQL directo
con un rol de taller (`fase7_dictamen.txt` B1 a B4): la protección pasa a depender del backend, que el
modelo ya trata como componente de confianza (`docs/seguridad.md` §13). Es una excepción declarada al
principio de que las reglas se sostienen "aunque se use SQL directo", limitada a estos cuatro puntos.

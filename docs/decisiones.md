# Decisiones de diseño — Repuestos Exactos (Fase 0)

> Estado: **Fase 0 cerrada, esperando revisión.** Nada de este documento está implementado en SQL todavía;
> las migraciones se escriben en la Fase 2. Lo único ejecutado es el entorno (ver sección 5).

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

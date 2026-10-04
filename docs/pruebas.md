# Pruebas

La suite se ejecuta con `bash db/tests/run_all.sh` (o `make test`) sobre una base migrada y con semillas.
Resultado real en `docs/evidencia/fase4_pruebas.txt`: **518 pruebas, 0 fallos**, código de salida 0, tanto
tras `reset → migrate → seed` como al repetirla sobre la misma base.

## 1. Qué se prueba

| Archivo | Pruebas | Qué demuestra |
|---|---:|---|
| `01_esquema.sql` | 31 | Invariantes leídos del catálogo: sin `SERIAL`, sin `TIMESTAMP` sin zona, todo comentado, RLS activo y forzado en las 14 tablas que lo requieren, funciones definidoras con `search_path` y dueño `app_funciones`, atributos y membresías de los roles, `PUBLIC` y `app_backend_user` sin privilegios, ningún CHECK con `now()` ni subconsulta, las 10 FK entre tablas de taller compuestas con `taller_id`, convención de nombres, ningún índice de búsqueda con un enum como clave en tablas con RLS (Fase 5), y `pg_temp` explícito al final del `search_path` de las 21 funciones junto con la ausencia de `TEMPORARY` en los roles de la aplicación (Fase 7, `V010`) |
| `02_restricciones.sql` | 63 | Cada CHECK, UNIQUE, FK y NOT NULL de las reglas RN-01 a RN-65, probados como plataforma para que quien rechace sea la restricción y no un privilegio |
| `03_estados_y_cotizaciones.sql` | 42 | Máquina de estados (RN-30 a RN-34) y cotizaciones (RN-50 a RN-59) con el rol del mecánico y las sentencias `tx_*`: transiciones, idempotencia, *snapshot*, cierre, inmutabilidad, control optimista |
| `04_rbac.sql` | 137 | Matriz rol × sentencia: 78 operaciones denegadas (`42501`) y 59 permitidas, para la conexión sin rol, el mecánico, el administrador y el auditor |
| `05_aislamiento_rls.sql` | 75 | Aislamiento entre talleres en lectura y escritura, FK compuestas, contexto ausente o inválido, `FORCE` sobre el propietario, visibilidad del mecánico sobre titulares bloqueados |
| `06_autenticacion.sql` | 33 | Login, normalización del email, respuesta uniforme ante fallos, contador y bloqueo, hashes bcrypt, límites de la contraseña |
| `07_auditoria.sql` | 26 | Solo inserción (también para el superusuario), contexto registrado, columnas enmascaradas, operaciones fallidas, y una tabla temporal homónima que no logra desviar los registros (Fase 7, `V010`) |
| `08_privacidad.sql` | 24 | Bloqueo por retención, anonimización inmediata y por vencimiento, irreversibilidad, conservación de la trazabilidad técnica |
| `09_consultas.sql` | 45 | Contrato de las consultas del frontend: paginación por clave, matriz, precios por taller, dashboard |
| `10_operacion.sql` | 17 | Configuración que la operación da por supuesta (Fase 6): `pg_hba.conf` sin `trust`, parámetros del log, `pg_stat_statements` ilegible para la aplicación y sin claves, y la purga de la auditoría por retención: borra solo lo anterior al corte, la inmutabilidad vuelve a regir en la misma transacción y ningún rol de la aplicación puede usar ese camino |
| `concurrencia.sh` | 12 | Diez escenarios con dos conexiones reales, ausencia de interbloqueos |
| `operacion.sh` | 13 | Con conexiones reales y leyendo el log del servidor: el socket local exige clave, una sentencia fallida no deja su texto en el log, los parámetros no se registran, memoria compartida y rotación del log del contenedor, la purga real (archiva, elimina, deja rastro) y ausencia de las claves de `.env` en el log |

## 2. Cómo está construida

- **Sobre las semillas y sin dejar rastro.** Cada archivo `.sql` abre una transacción y termina en
  `ROLLBACK`. La suite se puede repetir sin `reset`.
- **Con el rol real.** Los archivos `incluir/rol_*.sql` reproducen la petición del backend:
  `SET SESSION AUTHORIZATION app_backend_user; SET LOCAL ROLE <grupo>; EXECUTE ctx(...)`. Las comprobaciones
  que necesitan ver sin RLS (por ejemplo, leer `usuario_credencial`) las hace la plataforma.
- **Las mismas sentencias que el backend.** Se incluye `db/queries/preparar.sql` y se ejecutan los
  `PREPARE` reales, no copias.
- **Una línea por prueba:** `PASS | …` o `FAIL | …`. Tres formas de afirmar (`db/tests/incluir/`):

| Archivo | Afirma | Uso |
|---|---|---|
| `afirmar.sql` | una consulta dejó `:ok` en verdadero | valores y estados |
| `error.sql` | la sentencia anterior falló con el `SQLSTATE` esperado (marca `[E]`) | reglas que rechazan |
| `exito.sql` / `filas.sql` | terminó sin error / afectó N filas | permisos efectivos, RLS que filtra a 0 filas |

- **Un error no esperado no pasa inadvertido.** Como los errores esperados no deben abortar el archivo, se
  corre con `ON_ERROR_STOP off`. Para compensarlo, `run_all.sh` exige que en cada archivo el número de
  líneas `ERROR:` sea igual al de pruebas `[E]`; si sobra un error, el archivo se marca como fallido. Además
  `:ok` vuelve a `f` tras cada afirmación: si la consulta que debía fijarlo falla, la prueba es `FAIL`.
- **Resultados de sentencias preparadas.** `09_consultas.sql` los guarda con
  `CREATE TEMP TABLE x AS EXECUTE q_…` y los compara con un cálculo independiente hecho sin RLS. El orden
  devuelto se recupera con `ctid`. Para eso otorga `TEMPORARY` a los roles de taller **dentro de la
  transacción de la prueba**; el `ROLLBACK` lo revierte.

## 3. Resultados que conviene poder explicar

**RBAC y RLS son barreras distintas.** En `04` todas las operaciones usan ids del propio taller y se
rechazan con `42501`: lo que se niega es la operación. En `05` las operaciones están permitidas para el rol
pero apuntan a otro taller: el resultado es *cero filas* (`UPDATE 0`), no un error, y al final se comprueba
que el taller atacado no cambió. Las sentencias con `id_publico` ajeno también devuelven cero filas, sin
revelar si el recurso existe.

**Lo que RLS no cubre lo cubren las FK compuestas.** Una sesión del taller 2 sobre un vehículo del taller 1
supera la política (su `taller_id` es el propio) y la rechaza la FK `(vehiculo_id, taller_id)` con `23503`.

**Un trigger `BEFORE` se ejecuta antes que el `WITH CHECK` de la política.** Insertar una línea de detalle
con el `taller_id` de otro taller no termina en `42501` sino en `RE009`: el trigger no encuentra la
configuración de ese taller y aborta antes de que la política llegue a evaluarse. El resultado es el mismo
(rechazo) y la API lo traduce a 404.

**Falla cerrado.** Sin `app.taller_id`: cero filas en todas las tablas y ningún `INSERT` posible. Con un
taller inexistente: cero filas. Con un valor no numérico (`1 OR 1=1`): error de conversión `22P02`, la
consulta no devuelve datos. `SET LOCAL ROLE` fuera de una transacción no tiene efecto y la consulta
siguiente se deniega. El propietario `app_owner`, por `FORCE`, no ve ninguna fila.

**El login no distingue motivos.** Clave incorrecta, email inexistente, usuario inactivo, taller inactivo,
cuenta bloqueada y usuario sin credencial devuelven la misma fila. El quinto fallo consecutivo bloquea
15 minutos; durante el bloqueo ni la clave correcta autentica; restablecer la contraseña lo levanta.

**La auditoría comparte la transacción de la operación.** Una operación rechazada no deja registro; una
confirmada lo deja con el rol del grupo (nunca `app_funciones`), usuario, IP y `request_id`. El valor
personal enviado en la prueba (nombre, teléfono, email, patente, VIN, HMAC, e incluso un VIN dentro de
`freeze_frame`) no aparece en ningún registro.

## 4. Concurrencia

`db/tests/concurrencia.sh` usa dos conexiones reales de `app_backend_user` por escenario. La sesión A opera
y retiene su transacción 4 segundos; la sesión B lanza la operación en conflicto 1,5 segundos después. De B
se verifica que **esperó** (su sentencia tardó más de 1 segundo), el `SQLSTATE` final y el estado que quedó
en la base.

| Id | A | B (llega después) | Resultado comprobado |
|---|---|---|---|
| CON-01 | cierra la cotización | agrega una línea | B espera y recibe `RE003`; el total no incluye la línea (T-8) |
| CON-02 | agrega una línea (sin confirmar) | cierra la cotización | B espera; el total incluye la línea de A |
| CON-03 | crea cotización con clave K | crea con la misma K | B espera y recibe la misma cotización; hay una sola |
| CON-04 | crea un borrador | crea otro con otra clave | B espera y recibe `23505`; un solo borrador |
| CON-05 | completa la sesión | la cancela | B espera y recibe `RE001`; queda `completado` |
| CON-06 | completa la sesión | la completa con la versión leída antes | B espera y recibe `RE007`; un solo cambio |
| CON-07 | cierra la cotización | cierra la misma | B espera y la recibe ya cerrada; `version` no cambia |
| CON-08 | cambia la cantidad de una línea | cambia la misma línea | se serializan; una línea, la cantidad de B |
| CON-09 | cancela la sesión | cierra su borrador | B espera y recibe `RE004`; sin interbloqueo |
| CON-10 | login fallido | login fallido del mismo usuario | B espera; el contador queda en 2 |
| CON-11 | — | — | ningún escenario produjo `40P01` |
| CON-12 | — | — | ninguna sesión A falló |

**Control negativo** (`db/tests/control_negativo.sh`, evidencia en `fase4_control_negativo.txt`). Para
comprobar que CON-01 puede fallar, se quita temporalmente el `FOR SHARE` del trigger del detalle. Con el
defecto, la línea de B **se inserta en la cotización ya cerrada** (`SQLSTATE 00000`, estado final
incorrecto) y la prueba lo marca `FAIL`. Restaurada la función, vuelve a `PASS`. Esto demuestra a la vez
que el defecto descrito en T-8 es real y que la prueba lo detecta.

A diferencia del resto de la suite, estos escenarios hacen `COMMIT`. Sus datos se crean al empezar y se
borran al terminar; quedan únicamente sus registros de auditoría, que no se pueden borrar.

## 5. Operación

Las pruebas `OPE-*` (Fase 6) comprueban el entorno, no el esquema: fallan si alguien devuelve `trust` a
`pg_hba.conf`, relaja un parámetro del log o deja una clave en `pg_stat_statements`.

- **El "antes" es el control negativo.** `docs/evidencia/fase6_antes.txt` registra el mismo experimento con
  la configuración anterior: la conexión local sin clave se aceptaba y la sentencia fallida aparecía en el
  log con su literal. Con la configuración nueva, `OPE-20`, `OPE-21` y `OPE-24` muestran lo contrario.
- **`OPE-26` afirma un riesgo, no una protección.** Activa el log de duración solo en su sesión y comprueba
  que un valor escrito como literal **sí** queda en el log. Es la razón por la que `OPE-03` exige que ese
  log esté apagado, y por la que el backend debe usar parámetros (`OPE-25`: con parámetros no queda).
- **`operacion.sh` confirma transacciones**, como `concurrencia.sh`: crea tres registros de auditoría de 40
  años de antigüedad, ejecuta la purga real con un plazo de 30 años y deja el registro de esa purga.

## 6. Lo que la suite no cubre

- **Rendimiento y planes de ejecución** (Fase 5).
- **PgBouncer real.** El patrón de petición se prueba con `psql`; el *pool* no forma parte del prototipo.
- **El canal de tiempo del login.** Se comprueba que la respuesta es idéntica; no se mide que tarde lo mismo
  con un email existente que con uno inexistente.
- **Concurrencia de `fn_anonimizar_vencidos`** (`SKIP LOCKED` con dos ejecuciones a la vez) y carga con más
  de dos conexiones.
- **Niveles de aislamiento distintos de `READ COMMITTED`.**
- **Controles negativos del resto de la suite.** Solo se hizo para CON-01. Las demás pruebas se vieron
  fallar durante su escritura por errores de la propia prueba, no por mutaciones deliberadas del esquema.
- **Respaldo y restauración.** No forman parte de `make test` porque la prueba elimina el volumen. Se
  prueban aparte con `bash db/scripts/prueba_restauracion.sh` (`docs/operacion.md` §3, evidencia en
  `fase6_respaldo.txt`), que termina ejecutando esta misma suite sobre la base restaurada.

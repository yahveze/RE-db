# Operación

Cómo se respalda, se restaura, se vigila y se mantiene la base. Como en el resto del proyecto, lo que este
documento afirma sobre el comportamiento del motor sale de una ejecución real:

| Evidencia | Contenido |
|---|---|
| `docs/evidencia/fase6_antes.txt` | el estado **anterior** a esta fase (captura única): `trust`, 64 MB, fugas al log |
| `docs/evidencia/fase6_respaldo.txt` | respaldo → pérdida del volumen → restauración → comparación → suite |
| `docs/evidencia/fase6_operacion.txt` | `pg_hba`, parámetros, contenedor, log, secretos, proceso periódico, purga, mantenimiento |
| `docs/evidencia/fase6_observabilidad.txt` | salida de `db/scripts/estado.sh` |
| `docs/evidencia/fase6_perf.txt` | medición de rendimiento con `VACUUM` paralelo (T-51) |

Se regenera con `bash db/scripts/evidencia_fase6.sh` (**elimina el volumen**: ver §3). Lo marcado
**[NO EJECUTADO]** es una recomendación para producción que el prototipo no puede probar.

## 1. Qué cambió en el entorno

`docker-compose.yml` conserva los tres parámetros que fija el enunciado y agrega:

| Cambio | Tema | Motivo | Prueba |
|---|---|---|---|
| `shm_size: 256mb` | T-51 | con los 64 MB por defecto de Docker fallaba el `VACUUM` paralelo | `OPE-27` |
| `POSTGRES_INITDB_ARGS: --auth-local=scram-sha-256 --auth-host=scram-sha-256` | T-43 | `pg_hba.conf` sin `trust` | `OPE-01`, `OPE-20` a `OPE-23` |
| `log_min_error_statement=panic`, `log_parameter_max_length=0`, `log_parameter_max_length_on_error=0` | T-13 | ni sentencias ni parámetros en el log | `OPE-02`, `OPE-24`, `OPE-25` |
| `log_lock_waits=on`, `log_line_prefix=%m [%p] %q%u@%d ` | — | observabilidad de bloqueos; quién y en qué base | `OPE-04` |
| `logging` con `max-size: 10m`, `max-file: 5` | — | el log de Docker no crece sin límite | `OPE-28` |

`POSTGRES_INITDB_ARGS` solo actúa al **crear** el volumen: sobre un volumen existente hay que hacer `reset`
(o editar `pg_hba.conf` y ejecutar `SELECT pg_reload_conf()`).

Scripts nuevos (todos en `db/scripts/`, consultas en `db/ops/`):

| Script | `make` | Qué hace |
|---|---|---|
| `respaldar.sh` | `make backup` | respaldo lógico en `backups/` |
| `verificar_respaldo.sh` | `make verify-backup` | restaura el último respaldo en una base temporal y lo compara; no toca la principal |
| `restaurar.sh` | `make restore` | **destructivo**: reemplaza la base por un respaldo |
| `prueba_restauracion.sh` | `make restore-test` | **destructivo**: prueba completa de recuperación |
| `estado.sh` | `make status` | informe de observabilidad |
| `mantenimiento.sh` | — | `VACUUM (ANALYZE)` manual con antes y después |
| `anonimizar_vencidos.sh` | — | proceso periódico de privacidad |
| `purgar_auditoria.sh` | — | retención de la auditoría |
| `evidencia_fase6.sh` | — | regenera la evidencia de esta fase |

## 2. Respaldo

`bash db/scripts/respaldar.sh` genera tres archivos con la misma marca de tiempo UTC en `backups/`
(ignorada por Git):

| Archivo | Contenido |
|---|---|
| `<base>_<marca>.dump` | `pg_dump -Fc`: esquema, datos, privilegios, políticas RLS, valores de secuencias y ACL de la base |
| `<base>_<marca>.globales.sql` | `pg_dumpall --globals-only --no-role-passwords`: roles y membresías, **sin claves** |
| `<base>_<marca>.sha256` | suma de verificación de los dos anteriores |

- **Por qué dos archivos.** Los roles son del clúster, no de la base: `pg_dump` no los incluye. Sin el
  archivo de roles, restaurar en un servidor nuevo falla en el primer `ALTER ... OWNER TO app_owner`.
- **Por qué sin claves.** El verificador SCRAM de `app_backend_user` es material sensible y no hace falta:
  al restaurar, la clave se fija otra vez desde `.env`. El script falla si el archivo contuviera alguno.
- **Consistencia.** `pg_dump` trabaja sobre una instantánea: no bloquea a quienes leen o escriben y el
  resultado corresponde a un único instante.
- **Un respaldo ilegible no es un respaldo.** El script recorre el índice del archivo (`pg_restore --list`)
  y falla si no tiene objetos. En la corrida de la evidencia: 278.194 bytes, 660 objetos, 1 segundo, para
  una base de 21 tablas y 822 filas.
- **Rotación.** Conserva los 7 más recientes (`RESPALDOS_CONSERVAR`).

**Lo que el respaldo contiene y hay que proteger.** Datos personales de titulares y los hashes bcrypt de
`usuario_credencial`. El prototipo los deja en una carpeta local; en producción **[NO EJECUTADO]** deben
cifrarse (por ejemplo `gpg --symmetric` o cifrado del almacenamiento), copiarse fuera del servidor y tener
acceso restringido. Un respaldo en el mismo disco que la base no protege contra la pérdida del disco.

**Lo que el respaldo no contiene.** `pg_stat_statements` (estadísticas, no datos), la configuración del
servidor (`docker-compose.yml`, versionado) ni `.env` (los secretos se custodian aparte).

### Frecuencia y objetivos **[NO EJECUTADO: supuestos a validar con el negocio]**

Con solo respaldo lógico, se pierde todo lo ocurrido desde el último respaldo (RPO = intervalo entre
respaldos). Propuesta para el prototipo: uno diario, fuera del horario del taller, y otro antes de cada
migración. Si un día de atenciones perdido no es aceptable, hace falta archivado continuo de WAL y
recuperación a un punto en el tiempo (`archive_mode`, `pg_basebackup`, o una herramienta como pgBackRest):
**[AVANZADA]**, no implementado; hoy `archive_mode = off` (`fase6_operacion.txt` §2).

## 3. Restauración probada

### 3.1 La prueba

`bash db/scripts/prueba_restauracion.sh` simula la pérdida total de la base y la reconstruye **solo** con
los archivos del respaldo y `.env`. Resultado en `fase6_respaldo.txt`:

| Paso | Resultado |
|---|---|
| 1. Huella de la base de origen | 6 roles, 21 tablas, 49 políticas, 21 funciones, 32 triggers; 822 filas |
| 2. Respaldo | 660 objetos, 1 s |
| 3. Cambio posterior al respaldo | un administrador solicita la supresión de un titular: pasa a `bloqueado` |
| 4. Se elimina contenedor y volumen | clúster nuevo: 0 roles de la aplicación, 0 tablas |
| 5. `restaurar.sh` | roles creados, base restaurada, 5 s |
| 6. Comparación | **datos idénticos** (mismo md5 en las 21 tablas y mismas secuencias) y **esquema idéntico** |
| 7. Suite completa sobre la base restaurada | **518 PASS, 0 FAIL**, código 0 |

La comparación de datos usa `db/ops/huella.sql`: por cada tabla, número de filas y md5 de todas sus filas
ordenadas, más el último valor de cada secuencia. La del esquema es el sha256 de `pg_dump --schema-only`.
Que la suite pase después es la comprobación más fuerte: RLS forzado, privilegios, propietarios de las
funciones definidoras, triggers y la clave del backend quedaron como en el original.

### 3.2 Qué hace `restaurar.sh`

```bash
CONFIRMAR=repuestos_exactos bash db/scripts/restaurar.sh backups/<archivo>.dump
```

1. Verifica la suma sha256 y que el respaldo sea de esta base.
2. Si los roles no existen (clúster nuevo), los crea desde `.globales.sql`.
3. Fija la clave de `app_backend_user` desde `.env`.
4. Cierra las conexiones, elimina la base y la restaura con `pg_restore --create --exit-on-error`
   (`--create` recupera también el `REVOKE ... FROM PUBLIC` y el `GRANT CONNECT` de la base).
5. `VACUUM (ANALYZE)`: una base restaurada no tiene estadísticas y el planificador elegiría mal.
6. Ejecuta `fn_anonimizar_vencidos()` (ver §3.4).

Es destructivo y por eso exige `CONFIRMAR` con el nombre exacto de la base.

### 3.3 Lo que la prueba enseñó

- **El orden de los roles de una política cambia al restaurar.** `CREATE POLICY ... TO a, b, c` se guarda
  como una lista de OID; en el clúster restaurado los roles se crean en otro orden y `pg_dump` los lista
  distinto. El esquema es el mismo, pero una comparación textual ingenua lo da por diferente. La prueba
  normaliza ese orden (y el testigo aleatorio `\restrict` que `pg_dump` agrega a cada volcado).
- **Los triggers no se disparan al restaurar.** `pg_restore` carga los datos antes de crear triggers y
  claves foráneas: la auditoría restaurada es la original, sin registros nuevos, y los triggers de
  inmutabilidad no estorban.
- **`FORCE ROW LEVEL SECURITY` no afecta al respaldo** porque lo hace un superusuario, que no está sujeto a
  RLS: las 21 tablas salen completas. El respaldo debe hacerlo siempre la plataforma, nunca un rol de taller.

### 3.4 Restauración y derecho de supresión

El paso 3 de la prueba lo muestra: la supresión solicitada **después** del respaldo desaparece al
restaurar. Antes: 4 titulares activos, 2 bloqueados, 4 solicitudes. Restaurada: 5 activos, 1 bloqueado,
3 solicitudes. Es inherente a cualquier respaldo y tiene dos partes:

- **Bloqueos que vencieron entre el respaldo y hoy.** Los resuelve `restaurar.sh` ejecutando
  `fn_anonimizar_vencidos()` al terminar (en la prueba: 0, porque ninguno vencía).
- **Solicitudes y anonimizaciones posteriores al respaldo.** La base restaurada no sabe que existieron.
  Hay que reaplicarlas a mano, y para eso su registro debe vivir **fuera de la base**
  **[NO EJECUTADO]**: por ejemplo, que el backend deje constancia de cada solicitud de supresión en un
  sistema aparte (correo, gestor de tickets). El script lo recuerda al terminar.

Consecuencia para la retención de respaldos: un respaldo conserva datos que la base viva ya anonimizó. El
plazo durante el que se guardan los respaldos debe ser corto frente al de retención de datos, y debe
declararse al titular (**validar legalmente**).

### 3.5 Verificación rutinaria

La prueba de §3.1 destruye la base: sirve para el entorno de desarrollo, no para un servidor en uso.
`bash db/scripts/verificar_respaldo.sh` restaura el último respaldo en una base temporal `<base>_verif`,
compara su huella con la de la base principal y la elimina. Con un respaldo recién tomado, la huella es
idéntica; con uno anterior, lista las tablas que cambiaron desde entonces (`fase6_respaldo.txt` §8 y §9).

## 4. Acceso al servidor: `pg_hba.conf`

**Antes** (`fase6_antes.txt` §A1, §A2): la imagen `postgres:16` deja `trust` en el socket local y en el
loopback del contenedor. Cualquier proceso dentro del contenedor se conectaba como superusuario, o como
`app_backend_user`, sin clave.

**Ahora** (`fase6_operacion.txt` §1): las siete reglas exigen `scram-sha-256`.

| Prueba | Resultado |
|---|---|
| `OPE-20`, `OPE-21` | sin clave, por el socket local: `no password supplied` (backend y superusuario) |
| `OPE-22` | clave incorrecta: `password authentication failed` |
| `OPE-23` | clave de `.env`: conexión aceptada |
| `OPE-01` | ninguna regla de `pg_hba_file_rules` usa otro método |

Consecuencia para los scripts: `psql`, `pg_dump` y `pg_restore` se ejecutan dentro del contenedor con
`PGPASSWORD` tomado de las variables de entorno que el contenedor ya tiene. La clave nunca aparece en la
línea de comandos del equipo.

**Producción [NO EJECUTADO].** El prototipo no tiene TLS ni una red de backend que restringir. La forma
recomendada es:

```
# TYPE    BASE               ROL               ORIGEN             METODO
local     all                postgres                             scram-sha-256
hostssl   repuestos_exactos  app_backend_user  <red del backend>  scram-sha-256
host      all                all               all                reject
```

Es decir: TLS obligatorio (`hostssl`), el rol del backend solo hacia su base y solo desde su red, y todo
lo demás rechazado de forma explícita. La administración entra por el socket local del servidor.

## 5. Registro (log) del servidor

El problema, comprobado antes del cambio (`fase6_antes.txt` §A4): con la configuración por defecto, una
sentencia que **falla** se copia entera al log.

```
STATEMENT:  ALTER ROLE rol_que_no_existe PASSWORD '<canario>'
```

En el prototipo la contraseña viaja dentro de la consulta (`docs/seguridad.md` §9.3), así que un login
mal formado o una migración que falla dejarían una clave en un archivo de texto.

| Parámetro | Valor | Efecto | Prueba |
|---|---|---|---|
| `log_statement` | `none` | ninguna sentencia se registra por el hecho de ejecutarse | `OPE-02` |
| `log_min_error_statement` | `panic` | una sentencia fallida deja su `ERROR`, no su texto | `OPE-24` |
| `log_parameter_max_length` | `0` | los parámetros (`$1`) nunca se escriben | `OPE-25` |
| `log_parameter_max_length_on_error` | `0` | lo mismo en los errores | `OPE-02` |
| `log_min_duration_statement` | `-1` | sin log de sentencias lentas (ver abajo) | `OPE-03`, `OPE-26` |
| `log_lock_waits` | `on` | registra esperas de bloqueo de más de 1 s | `OPE-04` |
| `log_line_prefix` | `%m [%p] %q%u@%d ` | hora, proceso, rol y base en cada línea | `OPE-04` |

Resultado (`fase6_operacion.txt` §4 y §5): tras `reset → migrate → seed → test` el log contiene 206 líneas
`ERROR` (los errores esperados de la suite) y **0** líneas `STATEMENT`; ninguna de las tres claves de `.env`
aparece.

**El costo.** Sin el texto de la sentencia, diagnosticar un error con solo el log es más difícil: queda el
mensaje, el rol, la base y la hora, y hay que correlacionarlo con el log del backend por `request_id`. Es
el intercambio correcto mientras la contraseña viaje en la consulta; con el hash calculado en el backend
(`docs/seguridad.md` §9.4) se podría volver a `error`.

**Por qué el log de sentencias lentas queda apagado.** `log_min_duration_statement` es la herramienta
habitual para encontrar consultas lentas, pero registra el texto completo. `OPE-25` y `OPE-26` lo miden
activándolo solo en una sesión: con parámetros se registra `SELECT $1::text` sin el valor; con el valor
escrito como literal, **el valor queda en el log**. El backend usa parámetros, pero las migraciones y las
semillas envían las claves como literal (`psql` interpola `:'clave_demo'` antes de enviar). Para encontrar
consultas lentas se usa `pg_stat_statements`, que no escribe en el log (§8). En producción, con el hash
fuera de la base, puede activarse con un umbral de 500 ms **[NO EJECUTADO]**.

**`pg_stat_statements` también guarda texto.** Normaliza las constantes de `SELECT`, `INSERT`, `UPDATE` y
`DELETE`, pero no las de las sentencias de utilidad: el `CREATE ROLE ... PASSWORD '...'` de `V000` estaba
legible en la vista, igual que un `EXPLAIN` del login de la medición de rendimiento (`fase6_antes.txt`
§A5). Solo un superusuario puede leerla, pero no hay razón para conservarlo: `migrate.sh`, `seed.sh`,
`restaurar.sh` y `perf/run.sh` vacían las estadísticas al terminar, y `OPE-07` comprueba que no quede
ninguna clave. En producción la clave de un rol se fija con `\password` de `psql`, que calcula el
verificador SCRAM en el cliente y nunca envía la clave en claro **[NO EJECUTADO]**.

**Dónde está el log.** El servidor escribe en `stderr` y lo guarda Docker
(`docker compose logs db`), rotado en 5 archivos de 10 MB. No se activó `log_connections`: el `healthcheck`
consulta al servidor cada 3 segundos y cada consulta deja una línea. Activado durante 10 segundos
(`fase6_operacion.txt` §9) produjo 5 líneas `connection received`, de las que solo 2 eran conexiones
autenticadas (las del propio experimento). En producción, con una comprobación de salud menos frecuente,
conviene activarlo junto con `log_disconnections` para auditar accesos **[NO EJECUTADO]**.

## 6. Retención de la auditoría

`auditoria_operacion` solo crece: cada escritura de un taller agrega una fila. Con el volumen de la Fase 5
(2 millones de registros) ocupaba 573 MB, la mitad de la base (`docs/evidencia/rendimiento.md` §9).

**Política.** Los registros se conservan durante un plazo y luego se archivan y eliminan.

- **El plazo es una decisión legal, no técnica**: `purgar_auditoria.sh` no tiene valor por defecto.
- **Cota inferior.** El script rechaza un plazo menor que la mayor `retencion_anios` configurada por un
  taller (hoy 6): la bitácora debe cubrir al menos el tiempo que se conservan los datos que describe.
  Criterio de diseño, **validar legalmente**.
- **No contiene datos personales** (`docs/privacidad.md` §7), así que conservarla no entra en conflicto con
  la supresión; el límite lo pone el espacio y el principio de no guardar más de lo necesario.

**Procedimiento** (`bash db/scripts/purgar_auditoria.sh <años>`; sin `CONFIRMAR=1` solo simula):

1. Fija el corte: medianoche UTC de hoy menos el plazo.
2. Archiva las filas anteriores al corte en `backups/auditoria_anterior_a_<fecha>_<marca>.csv`, con su
   sha256.
3. En una transacción: elimina esas filas e inserta un registro de la purga en la propia auditoría (corte,
   cantidad, nombre y sha256 del archivo). Solo confirma si las filas eliminadas son exactamente las
   archivadas.
4. `VACUUM (ANALYZE)` de la tabla.

**Cómo convive con la inmutabilidad.** Los triggers rechazan `DELETE` incluso al superusuario (`OPE-10`).
La purga usa `SET LOCAL session_replication_role = replica`, que desactiva los triggers comunes **solo en
esa transacción**:

| Alternativa | Por qué no |
|---|---|
| `ALTER TABLE ... DISABLE TRIGGER` | toma `ACCESS EXCLUSIVE`: detiene toda escritura auditada mientras dura, y desprotege la tabla para **todas** las sesiones |
| Una función `SECURITY DEFINER` de purga | sería un camino de borrado permanente dentro del esquema; la purga es un acto de plataforma, no de la aplicación |

`session_replication_role` solo puede fijarlo un superusuario: el administrador del taller, la conexión
del backend y `app_owner` reciben `42501` (`OPE-15` a `OPE-17`). Terminada la purga, la misma transacción
vuelve a rechazar `DELETE` y `TRUNCATE` (`OPE-12`, `OPE-13`).

| Prueba | Resultado |
|---|---|
| `OPE-11`, `OPE-14` | elimina exactamente lo anterior al corte; repetirla no elimina nada |
| `OPE-29` a `OPE-31` | con el script real: 3 registros de 40 años archivados en CSV, eliminados, y la purga registrada |
| `fase6_operacion.txt` §7 | simulación con 6 años: 0 de 383 registros; plazo de 2 años: rechazado |

**Límites.** (a) Con millones de filas, un `DELETE` es lento y deja espacio que solo `VACUUM` recupera para
reutilizar: la solución es particionar por mes y eliminar particiones enteras, **[AVANZADA]**, no
implementado. (b) El archivo CSV queda en `backups/`: debe custodiarse como un respaldo. (c) Un
superusuario puede borrar sin usar este procedimiento (`docs/seguridad.md` §10 (b)); lo que el
procedimiento garantiza es que la vía prevista archiva y deja rastro.

## 7. Proceso periódico de privacidad

`fn_anonimizar_vencidos()` anonimiza los titulares cuyo bloqueo por retención venció
(`docs/privacidad.md` §8). La imagen `postgres:16` no trae `pg_cron` (T-18): la ejecuta
`db/scripts/anonimizar_vencidos.sh`, una vez al día, desde el programador del sistema.

```
anonimizar: 2026-10-04T15:48Z titulares anonimizados: 0; vencidos pendientes: 0; proximo vencimiento: 2032-08-25
```

- La función solo tiene `EXECUTE` para `app_owner`, que no tiene `LOGIN`: el script se conecta como
  superusuario y hace `SET ROLE app_owner`.
- Es idempotente y tolera dos ejecuciones simultáneas (`SKIP LOCKED`); probado en `08_privacidad.sql`.
- Termina con código distinto de cero si queda algún bloqueo vencido: el programador debe alertar.
- La misma cuenta está en `estado.sh` §10 y en la prueba `OPE-08`.

Programación **[NO EJECUTADO]** (no se registró ninguna tarea en este equipo):

```
# Linux (cron), todos los dias a las 03:15
15 3 * * *  cd /ruta/al/proyecto && bash db/scripts/anonimizar_vencidos.sh >> /var/log/re_anonimizar.log 2>&1

# Windows (Programador de tareas)
schtasks /Create /SC DAILY /ST 03:15 /TN "RE anonimizar vencidos" /TR "bash C:\ruta\db\scripts\anonimizar_vencidos.sh"
```

En producción convendría un rol propio con `LOGIN`, miembro de `app_owner`, en lugar del superusuario
**[AVANZADA]**; no se creó para no agregar un rol que el prototipo no usa.

## 8. Observabilidad

`bash db/scripts/estado.sh` (consultas en `db/ops/observabilidad.sql`, solo lectura). Salida real en
`fase6_observabilidad.txt`.

| § | Qué muestra | Para qué |
|---|---|---|
| 1, 2 | versión, tamaño, conexiones por rol y estado | saturación de conexiones; sesiones `idle in transaction` |
| 3 | transacciones abiertas hace más de 1 minuto | retienen bloqueos e impiden que el `VACUUM` limpie |
| 4 | sesiones esperando un bloqueo y quién las bloquea | diagnóstico en vivo (`pg_blocking_pids`) |
| 5 | tablas: tamaño, filas vivas y muertas, último `VACUUM` y `ANALYZE` | que el autovacuum esté llegando |
| 6 | índices `ix_` sin recorridos | candidatos a revisar (con la cautela de la Fase 5: `idx_scan` cuenta sondeos del planificador) |
| 7 | sentencias con más tiempo acumulado (`pg_stat_statements`) | consultas lentas, sin escribir nada en el log |
| 8 | confirmaciones, reversiones, interbloqueos, archivos temporales, aciertos de caché | salud general |
| 9 | edad de los identificadores de transacción | que el autovacuum evite el *wraparound* |
| 10 | bloqueos de titular vencidos sin anonimizar | que el proceso de §7 esté corriendo |
| 11 | registros y antigüedad de la auditoría | cuándo corresponde la purga de §6 |
| 12 | inicios de sesión fallidos en 24 h y cuentas bloqueadas | intentos de acceso |

Las vistas de `pg_stat_statements` no son legibles por ningún rol de la aplicación (`OPE-06`).

**En el log**: las esperas de bloqueo. La prueba de concurrencia produce 10 líneas como esta
(`fase6_operacion.txt` §4), con el rol y la base, y sin el texto de la sentencia:

```
app_backend_user@repuestos_exactos LOG:  process 347 still waiting for ShareLock on transaction 1872 after 1000.103 ms
app_backend_user@repuestos_exactos DETAIL:  Process holding the lock: 340. Wait queue: 347.
```

**Lo que falta [AVANZADA, no implementado]:** exportar métricas a un sistema de monitoreo
(`postgres_exporter` y Prometheus), alertas, y `pgaudit` para registrar lo que la auditoría por triggers no
ve (operaciones denegadas, lecturas).

## 9. Mantenimiento

| Tarea | Quién | Estado |
|---|---|---|
| `VACUUM` y `ANALYZE` | autovacuum (`autovacuum = on`, `track_counts = on`; `OPE-05`) | automático |
| `VACUUM (ANALYZE)` manual | `mantenimiento.sh`, tras una carga masiva, una restauración o una purga | probado |
| Purga de la auditoría | `purgar_auditoria.sh` (§6) | probado |
| Anonimización de vencidos | `anonimizar_vencidos.sh` (§7) | probado; programación documentada |
| Respaldo y verificación | `respaldar.sh`, `verificar_respaldo.sh` (§2, §3.5) | probado; programación documentada |

`mantenimiento.sh` en la evidencia (`fase6_operacion.txt` §8): de 178 filas muertas a 0, en 2 segundos.
No usa `VACUUM FULL`, que bloquea la tabla; con el tamaño del prototipo no hay hinchazón que lo justifique.

**Memoria compartida (T-51).** Con los 64 MB por defecto, el `VACUUM` paralelo de la base de volumen
fallaba con `could not resize shared memory segment` y la Fase 5 tuvo que usar `PARALLEL 0`. Con
`shm_size: 256mb`, `db/perf/run.sh` volvió al `VACUUM` normal sobre el mismo volumen
(`fase6_perf.txt`): 8 lanzamientos de procesos paralelos, 35 medidas, código 0.

**Migraciones (T-21).** `migrate.sh` aplica todos los archivos en orden sobre una base vacía, cada uno en
una transacción. No lleva registro de lo aplicado: sobre una base con datos, una migración nueva se aplica
con su prefijo (`bash db/scripts/migrate.sh V010`) y **después de un respaldo**. Una tabla de control con
versión y *checksum*, como la de Flyway, es **[AVANZADA]** y no se implementó.

**Actualizaciones del motor [NO EJECUTADO].** La imagen es `postgres:16`: una versión menor nueva se toma
al actualizar la imagen y recrear el contenedor (el volumen se conserva). Un cambio de versión mayor exige
respaldo y restauración (§2, §3) o `pg_upgrade`.

## 10. Lo que esta fase no cubre

- **Recuperación a un punto en el tiempo.** Solo hay respaldo lógico: se pierde lo posterior al último.
- **Alta disponibilidad.** Una sola instancia, sin réplica.
- **Cifrado y copia externa de los respaldos**, y su programación: documentados, no ejecutados.
- **TLS** y la regla `hostssl` de §4.
- **Tiempos de respaldo y restauración con volumen.** Se midieron con las semillas (1 s y 5 s). Con la
  base de volumen de la Fase 5 serán mucho mayores; no se midió.
- **La programación real de las tareas periódicas.** Los scripts se ejecutaron a mano.
- **Restauración parcial** (una tabla o un taller). `pg_restore` permite elegir tablas, pero restaurar un
  solo taller exige filtrar por `taller_id` y no se diseñó.
- **Monitoreo externo y alertas.**

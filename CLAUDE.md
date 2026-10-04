# Repuestos Exactos — base de datos PostgreSQL 16

Proyecto universitario: BD multi-taller para diagnóstico OBD-II y matriz comparativa de repuestos.
Responder siempre en **español**. Detalle y justificación de decisiones: `docs/decisiones.md`.

## Reglas de trabajo

- **Nada es válido hasta ejecutarlo** contra el PostgreSQL 16 del contenedor. Prohibido inventar salidas,
  costos, tiempos o filas: toda cifra sale de una ejecución real guardada en `docs/evidencia/`.
- **Nunca escribir secretos** en archivos versionados ni en evidencia. Las claves viven en `.env`
  (ignorado por Git) y llegan al SQL con `psql -v` como `:'clave_backend'` y `:'clave_demo'`.
  `.env.example` solo tiene placeholders.
- Ejecutar comandos solo dentro de esta carpeta y solo sobre el contenedor `repuestos_exactos_db`
  y el volumen `repuestos_exactos_pgdata`.
- Si una prueba falla, se corrige la migración, no se relaja la prueba.
- No reabrir las decisiones tomadas; los problemas se anotan en "Temas para conversar" de `docs/decisiones.md`.
- Commit local al final de cada fase. Puntos de parada: fases 0, 1, 2 y 7.
- Prohibido: `SERIAL`, `now()` en CHECK, CHECK con subconsulta, `SECURITY DEFINER` sin `SET search_path`
  (y siempre con `pg_temp` al final: `pg_catalog, public, pg_temp`), `SET` de sesión para el contexto del
  taller, pseudocódigo u omisiones ("...").

## Comandos

`make` no está instalado en este equipo Windows: usar los scripts (el `Makefile` solo delega en ellos).

| Make | Script | Qué hace |
|---|---|---|
| `make up` / `down` | `docker compose up -d --wait` / `down` | levanta / detiene |
| `make reset` | `bash db/scripts/reset.sh` | elimina el volumen y recrea una base vacía |
| `make migrate` | `bash db/scripts/migrate.sh` | aplica `db/migrations/V*.sql` en orden |
| `make seed` | `bash db/scripts/seed.sh` | carga `db/seeds/*.sql` como superusuario |
| `make test` | `bash db/tests/run_all.sh` | suite SQL; código ≠ 0 si hay algún FAIL |
| `make perf` | `bash db/perf/run.sh` | volumen + EXPLAIN (Fase 5) |
| `make psql` | `bash db/scripts/psql.sh [-c ... | -f /db/...]` | psql 16 del contenedor |
| `make all` | reset → migrate → seed → test | criterio de aceptación: código 0 |
| `make backup` / `verify-backup` | `bash db/scripts/respaldar.sh` / `verificar_respaldo.sh` | respaldo en `backups/`; verificación en base temporal |
| `make restore` / `restore-test` | `restaurar.sh <dump>` (con `CONFIRMAR=<base>`) / `prueba_restauracion.sh` | **destructivos** |
| `make status` | `bash db/scripts/estado.sh` | informe de observabilidad |

Notas: se usa el `psql` **del contenedor** (el del host es v18). `db/` está montado en `/db` (solo lectura).
`psql -c` no interpola variables `:'x'`; usar `-f` o stdin.

## Orden de ejecución

`V000` roles y extensiones (superusuario) → `V001` tipos → `V002` catálogos → `V003` tablas multi-taller,
operativas, cotización y auditoría → `V004` comentarios → `V005` funciones y triggers → `V006` índices →
`V007` grants → `V008` RLS (`ENABLE` y `FORCE` solo aquí) → `V009` ajustes de índices (Fase 5) →
`V010` `search_path` con `pg_temp` (Fase 7) → semillas (superusuario) → pruebas.

`V001`+ corren como superusuario con `SET ROLE app_owner` previo (dueño de los objetos = `app_owner`).
Las funciones `SECURITY DEFINER` pasan a `app_funciones`; para eso `app_owner` es miembro de
`app_funciones` (`INHERIT FALSE, SET TRUE`) y `app_funciones` tiene `CREATE` en `public`.

## Decisiones tomadas

1. Multi-taller por segregación lógica: `taller_id` obligatorio en toda tabla operativa; un taller nuevo es un `INSERT`.
2. Un usuario pertenece a un solo taller; email único global.
3. Estados de `sesion_diagnostico`: `pendiente`, `cotizado`, `completado`, `cancelado`. Transiciones:
   pendiente→cotizado, pendiente→cancelado, cotizado→completado, cotizado→cancelado. Validadas con trigger.
4. Perfiles `genuino`, `oem`, `generico`, siempre en ese orden.
5. Precios `BIGINT` en unidad mínima; moneda por taller, default `'CLP'`.
6. Precio maestro global `repuesto.precio_referencia`;
   `precio_venta = ROUND(precio_referencia * (1 + margen_pct / 100))`. Listas por taller: [AVANZADA].
7. Catálogos globales de solo lectura para talleres: `marca_vehiculo`, `modelo_vehiculo`, `dtc_catalogo`,
   `componente_repuesto`, `dtc_componente`, `repuesto`, `compatibilidad_repuesto`.
8. `modelo_vehiculo → marca_vehiculo` normalizado (evita dependencia transitiva en `vehiculo`).
9. Un `repuesto` pertenece a un `componente_repuesto`; DTC↔componente es N:M (`dtc_componente`);
   DTC↔repuesto es la **vista** `v_dtc_repuesto`.
10. `compatibilidad_repuesto(repuesto, modelo_vehiculo, anio_desde, anio_hasta)`. Por motor: [AVANZADA].
11. Cotizaciones: varias revisiones por sesión, una sola vigente (índice único parcial); abierta mientras
    `cerrada_en IS NULL`; el `total` se congela al cerrar; cerrada = inmutable.
12. Método de ingreso `obd_bluetooth` | `manual`; `dispositivo_id` obligatorio si y solo si es `obd_bluetooth`.
13. Titular y vehículo pertenecen a un taller. Vehículo→titular: FK simple y anulable.
14. El auditor ve solo su taller.
15. Patente obligatoria salvo vehículo anonimizado (`patente` y `vin` pasan a `NULL`).
16. Sin RUT; identificador determinista = HMAC-SHA-256 calculado en el backend.
17. Autenticación de prototipo con `crypt()` y `gen_salt('bf', 10)` en la BD.
18. Todo tiempo es `TIMESTAMPTZ`.

Decisiones abiertas resueltas (ver `docs/decisiones.md` §2): durabilidad en km; `margen_pct NUMERIC(5,2)`
0–200, default 30; `retencion_anios` default 6 (validar legalmente); sesión siempre con vehículo; solo
cotizaciones (sin documentos tributarios); `ON DELETE RESTRICT` + estado de baja.

## Convenciones

- `snake_case`, español sin mezclar idiomas, tablas en singular.
- PK `id BIGINT GENERATED ALWAYS AS IDENTITY`. Tablas de enlace N:M: PK compuesta natural, sin `id`.
- Entidades expuestas por la API: `id_publico UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE`.
  La API nunca expone ids secuenciales.
- FK `<entidad>_id`. Timestamps `creado_en`, `actualizado_en`; `eliminado_en` solo con borrado lógico;
  inicio de sesión de diagnóstico: `iniciada_en`.
- Prefijos: `pk_`, `fk_`, `uq_`, `ck_`, `ix_`, `trg_`, `fn_`, `v_`, `pol_<tabla>_<rol>_<operacion>`; enums `tipo_`.
- Variables de sesión: `app.taller_id`, `app.usuario_id`, `app.ip_origen`, `app.request_id`.
- Los campos JSON de la API coinciden con los nombres de columna.
- Enums: `tipo_rol_usuario` (admin, mecanico, auditor), `tipo_estado_atencion`, `tipo_severidad`
  (baja, media, alta, critica), `tipo_perfil_repuesto`, `tipo_nivel_riesgo` (bajo, medio, alto),
  `tipo_metodo_ingreso`, `tipo_resultado_auditoria` (exito, fallo, denegado), `tipo_operacion_auditoria`,
  `tipo_estado_dispositivo` (activo, inactivo, baja), `tipo_tema_visual` (claro, oscuro),
  `tipo_estado_tratamiento` (activo, bloqueado, anonimizado), `tipo_finalidad_tratamiento`,
  `tipo_solicitud_derecho`, `tipo_estado_solicitud`.
- `COMMENT ON TABLE/COLUMN` para todas las tablas.

## Seguridad (resumen)

- Roles: `app_owner` (dueño, no se usa en ejecución), `app_funciones` (NOLOGIN, BYPASSRLS, dueño solo de
  funciones definidoras), grupos `taller_admin`, `taller_mecanico`, `taller_auditor`, y `app_backend_user`
  (LOGIN, sin privilegios de tabla, miembro de los grupos con `INHERIT FALSE, SET TRUE`).
- Patrón de petición: `BEGIN; SET LOCAL ROLE <grupo>; set_config('app.taller_id', $1, true); ...; COMMIT;`
- RLS con `FORCE`; contexto `(SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)`.
- Dentro de `SECURITY DEFINER`, `current_user` es `app_funciones`: el rol real se lee con `current_setting('role')`.
- Aislamiento: `UNIQUE (id, taller_id)` en tablas padre y FK compuestas `(padre_id, taller_id)` en las hijas.


## Notas de implementación (Fase 2)

- `migrate.sh` corre cada archivo con `--single-transaction`; acepta un prefijo (`migrate.sh V005`).
- En `V005` los `COMMENT ON FUNCTION` van antes de `ALTER FUNCTION ... OWNER TO app_funciones`
  (COMMENT exige ser el dueño). Los `GRANT EXECUTE` de esas funciones se hacen en `V007` con
  `SET ROLE app_funciones`.
- Índices únicos parciales (reglas de integridad) en `V003`; índices de rendimiento en `V006`.
- El trigger del detalle bloquea la cabecera con `FOR SHARE` (no `FOR KEY SHARE`): cubre también el
  cierre por `UPDATE` directo.
- Toda cotización nace borrador (trigger); `total` y `cerrada_en` los fija el trigger al cerrar. Las
  semillas deben recorrer el flujo real, no insertar estados finales.
- Errores de negocio con `SQLSTATE` propio `RE001`–`RE012` (tabla en `docs/seguridad.md` §11).
- Políticas `pol_<tabla>_miembros_<op>` cuando aplican a los tres grupos.
- Tras cambiar un `COMMENT ON`: `bash db/scripts/diccionario.sh`. Tras cambiar el esquema:
  `bash db/scripts/evidencia_esquema.sh`. Prueba de humo: `bash db/scripts/psql.sh -f /db/tests/humo/fase2_humo.sql`.
- `psql.sh` pasa `-q` y `ON_ERROR_STOP=1`; un script con errores esperados debe poner
  `\set ON_ERROR_STOP off` y `\set ON_ERROR_ROLLBACK on`.
- En Git Bash no pasar rutas de Windows (`$TEMP`) a `awk -v`: las barras invertidas se interpretan como
  escapes. Usar heredoc o la herramienta de edición.

## Notas de implementación (Fase 3)

- Semillas (`db/seeds/`): `01` catálogos y el alta de talleres de `02` como superusuario; el resto asume el
  rol de taller (`SET LOCAL ROLE` + `set_config`) para pasar por GRANT, RLS y auditoría reales. No son
  re-ejecutables: `seed.sh` se niega si `taller` tiene filas. `99_resumen.sql` verifica y aborta si falla.
- `db/seeds/incluir/flujo_atencion.sql` es un `DO` que lee `semilla.atenciones` (JSON) y recorre el flujo
  real; se incluye con `\ir`. psql no interpola variables dentro de `DO`: usar `set_config` o claves naturales.
- `db/queries/`: toda sentencia del backend es un `PREPARE` (`q_*` lectura, `tx_*` escritura, `ctx` contexto).
  `\ir preparar.sql` las carga todas. Entran y salen `id_publico`; no filtran por `taller_id` (lo hace RLS).
- Una función que devuelve `void` dentro de un `SELECT`: envolverla en `WITH ... AS MATERIALIZED`.
- Demostraciones: `demo_consultas.sql` (sin errores, `ON_ERROR_STOP`) y `demo_transacciones.sql` (errores
  esperados, cada uno seguido de `\echo ... :LAST_ERROR_SQLSTATE`; todo en una transacción con `ROLLBACK`).
  Tras cambiarlas: `bash db/scripts/evidencia_fase3.sh` (cuenta que los errores sean los esperados).
- La prueba de humo de la Fase 2 solo corre sobre una base **sin** semillas.
- Temas T-35 a T-42 en `docs/decisiones.md` §8.3.

## Notas de implementación (Fase 4)

- Suite: `db/tests/NN_*.sql` (cada archivo: `\ir incluir/inicio.sql` … `ROLLBACK`) + `db/tests/concurrencia.sh`.
  Una línea `PASS | …` o `FAIL | …` por prueba. Requiere semillas.
- Afirmaciones en `db/tests/incluir/`: `afirmar.sql` (consulta que deja `:ok` con `\gset`), `error.sql`
  (`\set esperado <SQLSTATE>` antes de la sentencia que debe fallar; marca `[E]`), `exito.sql`, `filas.sql`.
  Cambio de rol: `\ir incluir/rol_mecanico_1.sql` y similares; `rol_plataforma.sql` para ver sin RLS.
- `run_all.sh` falla si en un archivo el número de `ERROR:` difiere del de pruebas `[E]`: todo error
  esperado debe ir seguido de `\ir incluir/error.sql`.
- `\gset` deja SIN definir la variable de una columna NULL: para afirmar sobre NULL, hacerlo dentro del SQL.
- Para afirmar sobre el resultado de un `PREPARE`: `CREATE TEMP TABLE x AS EXECUTE q_…` (requiere el
  `GRANT TEMPORARY` temporal que hace `09_consultas.sql`); el orden devuelto se recupera con `ctid`.
- Un trigger `BEFORE` corre antes que el `WITH CHECK` de RLS (ver T-44).
- `concurrencia.sh` hace `COMMIT`, limpia sus datos (kilometraje 900001–900009, patente `ZZZZ99`) y deja
  auditoría. No afirmar conteos absolutos de `auditoria_operacion`.
- En scripts con `set -euo pipefail`, `grep` sin coincidencias aborta: usar `|| true`.
- Temas T-43 a T-48 en `docs/decisiones.md` §9.2. T-43 (pg_hba `trust` local) quedó resuelto en la Fase 6.

## Notas de implementación (Fase 5)

- `bash db/perf/run.sh` crea `<base>_perf` con `CREATE DATABASE ... TEMPLATE`, carga `db/perf/volumen.sql`,
  mide y la elimina (`PERF_CONSERVAR=1` la conserva). Nunca cargar volumen en la base principal. Tarda unos
  6 minutos; no es parte de `make all`.
- **Bajo RLS un enum no puede ser clave de búsqueda de un índice** (`enum_eq` no es leakproof): usar índices
  parciales y escribir el valor como literal. Lo vigila la prueba `ESQ-28`.
- **Sin parámetros opcionales sobre columnas indexadas** (`$1 IS NULL OR ...`): en el plan genérico quedan
  como filtro. Si el parámetro decide el índice, dos sentencias (`q_historial*`, `q_auditoria*`).
- El planificador no conoce `app.taller_id`: estima el taller promedio. Para "un valor por fila", subconsulta
  escalar antes que `JOIN`.
- `idx_scan` cuenta también los sondeos del planificador: para decidir sobre un índice, comparar el plan con
  y sin él dentro de una transacción (`experimentos_indices.sql`).
- `VACUUM` paralelo: funciona desde la Fase 6 (`shm_size: 256mb`; con los 64 MB por defecto había que usar `PARALLEL 0`, T-51).
- Los índices nuevos o eliminados van en una migración nueva (`V009`), no editando `V006`.
- Tras cambiar una sentencia de `db/queries/`: regenerar `evidencia_fase3.sh` y `evidencia_fase4.sh`.
- Temas T-49 a T-54 en `docs/decisiones.md` §10.3.

## Notas de implementación (Fase 6)

- **Toda conexión exige clave** (`pg_hba.conf` solo `scram-sha-256`, vía `POSTGRES_INITDB_ARGS`; se aplica al
  crear el volumen). Dentro del contenedor usar siempre las funciones de `_lib.sh`: `psql_super`,
  `psql_backend` (rol del backend) y `en_contenedor <programa>` (`pg_dump`, `pg_restore`...). Un `psql` suelto
  con `docker compose exec` falla con `no password supplied`.
- **El log no contiene sentencias** (`log_min_error_statement=panic`): al depurar, el `ERROR` del log viene sin
  su `STATEMENT`; el texto hay que verlo en la salida de `psql`. No activar `log_min_duration_statement` en el
  compose: registra literales (`OPE-26`). Las consultas lentas se buscan con `estado.sh` §7.
- **`pg_stat_statements` guarda sin normalizar las sentencias de utilidad** (`CREATE ROLE ... PASSWORD`,
  `EXPLAIN`, `CREATE TABLE AS`): todo script que envíe una clave como literal termina con
  `vaciar_estadisticas_sentencias`. Lo vigila `OPE-07`.
- `db/ops/`: SQL de operación reutilizable (`huella.sql`, `observabilidad.sql`, `purgar_auditoria.sql`). Este
  último no abre transacción y deja `:purga_eliminadas`; lo incluyen el script y la prueba.
- La única vía para borrar auditoría es `purgar_auditoria.sh` (`SET LOCAL session_replication_role = replica`,
  solo superusuario). Sin plazo por defecto; rechaza menos que la mayor `retencion_anios`.
- `prueba_restauracion.sh` y `evidencia_fase6.sh` **eliminan el volumen**. Los respaldos quedan en `backups/`
  (ignorada por Git; rotación de 7). `FASE6_PERF=1` agrega la corrida de rendimiento y conserva `fase5_*.txt`.
- Comparar esquemas con `pg_dump --schema-only` exige normalizar `\restrict` y el orden de los roles de las
  políticas (cambia tras restaurar): ver `normalizar_esquema` en `prueba_restauracion.sh`.
- Pruebas con shell (`concurrencia.sh`, `operacion.sh`) se registran en el arreglo `guiones` de `run_all.sh`.
  `operacion.sh` confirma transacciones y deja un registro de purga en la auditoría.
- En scripts con `set -euo pipefail`, `diff` con diferencias devuelve 1 y aborta: `{ diff ... || true; }`.
- No pasar SQL con barras invertidas (`\gexec`, `\bind`) en un heredoc de la herramienta Bash: usar la
  herramienta de escritura de archivos.
- Temas T-55 a T-62 en `docs/decisiones.md` §11.4.

## Notas de implementación (Fase 7)

- **Una función nueva fija `SET search_path = pg_catalog, public, pg_temp`.** Sin `pg_temp` explícito se busca
  primero para tablas y una temporal homónima suplanta a la real (`V010`). Lo vigila `ESQ-30`, que además
  exige que las funciones `fn_` sean exactamente 21: al agregar una, actualizar esa cifra y `ESQ-25`.
- **No otorgar `TEMPORARY` a un rol de la aplicación** (`ESQ-31`). `09_consultas.sql` y la prueba de sombra de
  `07_auditoria.sql` lo otorgan dentro de su transacción y el `ROLLBACK` lo revierte.
- `db/tests/humo/fase7_dictamen.sql` no es parte de la suite: comprobaciones de catálogo y experimentos que
  cita `docs/dictamen.md`. Termina en `ROLLBACK` y espera exactamente un error (B5a).
- `evidencia_fase7.sh` **elimina el volumen** (ejecuta las recetas de `make all`). Si `make` existe, lo usa.
  `fase7_antes.txt` es una captura única sobre `V000`–`V009` y no se regenera.
- Orden para regenerar toda la evidencia: `evidencia_fase6.sh` → `evidencia_fase7.sh` →
  `evidencia_esquema.sh` → `diccionario.sh` → `evidencia_fase3.sh` → `evidencia_fase4.sh`. Después, revisar
  las cifras que citan `docs/operacion.md` y `docs/pruebas.md` (cambian entre corridas).
- En la herramienta Bash, un heredoc con comillas simples y acentos graves dentro puede fallar al analizarse:
  para ediciones largas de Markdown usar la herramienta de edición.
- Temas T-63 a T-69 en `docs/decisiones.md` §12.4. T-63 a T-66 resueltos en §12.6: los valida la API
  (T-65: configuración de producción); la base no cambia.

## Estado

- **Proyecto cerrado: fases 0 a 7 completas.** Esquema en `db/migrations/` (V000–V010), semillas en
  `db/seeds/`, consultas y transacciones en `db/queries/` (43 sentencias), suite en `db/tests/` (518 pruebas),
  medición en `db/perf/`, operación en `db/scripts/` y `db/ops/`; `reset → migrate → seed → test` verificado
  desde cero con código 0, y también sobre una base restaurada desde un respaldo.
- Documentos: `docs/dictamen.md`, `docs/decisiones.md`, `docs/modelo/` (01–05), `docs/seguridad.md`,
  `docs/privacidad.md`, `docs/consultas.md`, `docs/transacciones.md`, `docs/pruebas.md`, `docs/operacion.md`,
  `docs/evidencia/rendimiento.md`.
- Desarrollo concluido. Fuera del alcance de la base: T-63 a T-66 (API y producción, §12.6); `make` sigue sin instalar (T-1, T-67); la medición de
  rendimiento no se repitió tras `V010` (T-60).

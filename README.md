# Repuestos Exactos — base de datos

Base de datos PostgreSQL 16 del sistema **Repuestos Exactos**: interpreta diagnósticos OBD-II y arma una
matriz comparativa de repuestos (genuino, OEM y genérico) de la que sale una cotización trazable, para
varios talleres mecánicos sobre una misma base. Proyecto universitario de Ingeniería en Computación e
Informática.

> **Estado: entrega final.** `reset → migrate → seed → test` termina con código 0 sobre una base vacía, con
> 518 pruebas y 0 fallos (`docs/evidencia/fase7_cierre.txt`). El alcance es la base de datos: no hay backend
> ni aplicación. Qué se sostiene y qué falta para producción: `docs/dictamen.md`.

## Integración con la aplicación

V011 agrega identidad Google e invitaciones; V012 agrega la propiedad explícita y los perfiles de negocio **propietario/mecánico**. El rol técnico histórico `admin` no implica propiedad por sí solo. La asignación está en `taller.propietario_usuario_id`; `v_usuario_perfil` determina el perfil habilitado. Los auditores de demostración se conservan para pruebas SQL, pero no pueden ingresar a la aplicación.

Contrato, migración y límites: [propietario y mecánico](../Backend_Repuestos_Exactos/docs/propietario_y_mecanico.md). El estado de entrega final y sus 518 pruebas de abajo corresponden al cierre histórico V010; la evidencia actual de esta ampliación se registra por separado.

## Requisitos

- Docker en ejecución (Docker Desktop en Windows).
- Bash (Git Bash en Windows).
- `make` es opcional: cada objetivo del `Makefile` delega en un script de `db/`.

## Inicio rápido

```bash
cp .env.example .env        # y reemplazar los placeholders por claves propias
docker compose up -d --wait # o: make up

# criterio de aceptacion (make all)
bash db/scripts/reset.sh && bash db/scripts/migrate.sh && bash db/scripts/seed.sh && bash db/tests/run_all.sh
```

La última línea de la suite debe ser `test: todo PASS (518 pruebas en 12 archivos)`.

| Objetivo | Sin make |
|---|---|
| `make up` | `docker compose up -d --wait` |
| `make down` | `docker compose down` |
| `make reset` | `bash db/scripts/reset.sh` (**elimina el volumen**) |
| `make migrate` | `bash db/scripts/migrate.sh` |
| `make seed` | `bash db/scripts/seed.sh` |
| `make test` | `bash db/tests/run_all.sh` |
| `make perf` | `bash db/perf/run.sh` |
| `make psql` | `bash db/scripts/psql.sh` |
| `make all` | `reset` → `migrate` → `seed` → `test` |
| `make backup` / `verify-backup` / `status` | `bash db/scripts/respaldar.sh` / `verificar_respaldo.sh` / `estado.sh` |

La base queda publicada solo en `127.0.0.1:5433`. `.env` nunca se versiona.

Toda conexión exige clave, también dentro del contenedor (`pg_hba.conf` sin `trust`). Esa configuración se
aplica al **crear** el volumen: con un volumen anterior a la Fase 6 hay que ejecutar `reset`.

## Qué hay en el repositorio

| Carpeta | Contenido |
|---|---|
| `db/migrations/` | `V000`–`V010`: roles, tipos, tablas, comentarios, funciones y triggers, índices, privilegios, RLS y dos ajustes posteriores |
| `db/seeds/` | datos de demostración: catálogos y dos talleres con su operación |
| `db/queries/` | las 43 sentencias que enviaría el backend, como `PREPARE`, y dos demostraciones |
| `db/tests/` | suite SQL (10 archivos) y dos guiones con conexiones reales (concurrencia y operación) |
| `db/perf/` | carga de volumen y medición con `EXPLAIN (ANALYZE, BUFFERS)` |
| `db/scripts/`, `db/ops/` | ejecución, respaldo, restauración, observabilidad, mantenimiento y generación de evidencia |
| `docs/` | decisiones, modelo, seguridad, privacidad, contrato de consultas, pruebas, operación y dictamen |
| `docs/evidencia/` | salida real de cada ejecución que los documentos citan |

## El diseño en cinco ideas

1. **Un taller es una fila, no un esquema.** `taller_id` en toda tabla operativa, claves foráneas compuestas
   `(padre_id, taller_id)` que hacen imposible una referencia entre talleres, y RLS con `FORCE` encima.
2. **Catálogo global, operación local.** Marcas, modelos, DTC, componentes y repuestos son comunes y de
   solo lectura; cada taller aporta su margen.
3. **El backend se conecta sin privilegios.** `app_backend_user` no puede leer nada hasta asumir, por
   transacción, el rol del usuario (`SET LOCAL ROLE`) y fijar el taller (`set_config(..., true)`).
4. **El dinero no se reescribe.** Precios en `BIGINT`, cotización con *snapshot* de precio y margen, total
   congelado al cerrar e inmutable después.
5. **Privacidad por diseño.** Sin RUT, supresión con bloqueo por retención y anonimización irreversible, y
   una auditoría que nunca contiene datos personales.

## Datos de demostración

`bash db/scripts/seed.sh` carga dos talleres con usuarios, vehículos y atenciones en todos los estados.
Todos los usuarios comparten la clave `CLAVE_DEMO` de `.env`. Las semillas no son re-ejecutables: para
recargar, `reset` + `migrate` + `seed`.

| Taller | Usuarios |
|---|---|
| Taller Mecánico Los Aromos (margen 30 %) | `admin@`, `mecanico1@`, `mecanico2@`, `auditor@losaromos.example` |
| Servicio Automotriz Ñuble (margen 45,5 %) | `admin@`, `mecanico@`, `auditor@nuble.example` |

```bash
bash db/scripts/psql.sh -f /db/queries/demo_consultas.sql       # consultas de lectura
bash db/scripts/psql.sh -f /db/queries/demo_transacciones.sql   # transacciones (termina en ROLLBACK)
```

## Pruebas

```bash
bash db/tests/run_all.sh           # suite completa; codigo 0 = todo PASS
bash db/tests/control_negativo.sh  # demuestra que la prueba de concurrencia detecta el defecto de T-8
```

La suite corre sobre las semillas y se puede repetir sin `reset`. No deja cambios, salvo los registros de
auditoría de las pruebas que confirman transacciones (concurrencia y operación). Qué prueba cada archivo y
qué no cubre: `docs/pruebas.md`.

## Operación

```bash
bash db/scripts/respaldar.sh             # make backup: respaldo en backups/ (ignorada por Git)
bash db/scripts/verificar_respaldo.sh    # make verify-backup: lo restaura en una base temporal y compara
bash db/scripts/estado.sh                # make status: conexiones, bloqueos, tablas, sentencias costosas
bash db/scripts/mantenimiento.sh         # VACUUM (ANALYZE) manual
bash db/scripts/anonimizar_vencidos.sh   # proceso periodico de privacidad (programar a diario)
bash db/scripts/purgar_auditoria.sh 6    # retencion de la auditoria: simulacion; CONFIRMAR=1 para purgar
```

Destructivos (reemplazan la base; piden confirmación o la advierten en su cabecera):

```bash
CONFIRMAR=repuestos_exactos bash db/scripts/restaurar.sh backups/<archivo>.dump   # make restore
bash db/scripts/prueba_restauracion.sh   # make restore-test: respaldo -> borra el volumen -> restaura -> suite
```

Detalle en `docs/operacion.md`.

## Rendimiento

```bash
bash db/perf/run.sh    # unos 6 minutos y 1,2 GB libres; no toca la base principal
```

Crea `<base>_perf` como copia de la base principal, le carga volumen sintético, mide las sentencias de
`db/queries/` con `EXPLAIN (ANALYZE, BUFFERS)` y la elimina. `PERF_CONSERVAR=1` la deja para inspeccionarla.

## Evidencia

Toda cifra de la documentación sale de un archivo de `docs/evidencia/`, y cada archivo lo genera un script:

| Script | Genera | Notas |
|---|---|---|
| `db/scripts/evidencia_esquema.sh` | `esquema.txt` | catálogo real: tablas, funciones, privilegios, políticas |
| `db/scripts/diccionario.sh` | `docs/modelo/05_diccionario_datos.md` | desde los `COMMENT ON` |
| `db/scripts/evidencia_fase3.sh` | `fase3_*.txt` | semillas, consultas y transacciones |
| `db/scripts/evidencia_fase4.sh` | `fase4_*.txt` | suite completa y control negativo |
| `db/perf/run.sh` | `fase5_*.txt` | medición con volumen |
| `db/scripts/evidencia_fase6.sh` | `fase6_*.txt` | **elimina el volumen**: respaldo, restauración y operación |
| `db/scripts/evidencia_fase7.sh` | `fase7_cierre.txt`, `fase7_dictamen.txt` | **elimina el volumen**: `make all` y dictamen |

`fase0_*`, `fase1_*`, `fase2_humo.txt`, `fase6_antes.txt` y `fase7_antes.txt` son capturas de un momento del
proyecto y no se regeneran.

## Documentación

Por dónde empezar: `docs/dictamen.md` (qué se entrega y con qué límites) y `docs/decisiones.md` (por qué).

- `docs/dictamen.md` — dictamen de cierre: veredicto, hallazgos verificados por ejecución y lo que falta para producción.
- `docs/decisiones.md` — resumen ejecutivo, decisiones abiertas, supuestos, temas para conversar (T-1 a T-69) y verificación de cada fase.
- `docs/modelo/` — dominio y reglas de negocio, modelo conceptual (Mermaid), modelo lógico, normalización y diccionario de datos (generado).
- `docs/seguridad.md`, `docs/privacidad.md` — roles, RBAC y RLS, autenticación, auditoría, supresión y anonimización.
- `docs/consultas.md`, `docs/transacciones.md` — contrato de las consultas del frontend (`db/queries/`) y transacciones atómicas.
- `docs/pruebas.md` — qué prueba la suite (`db/tests/`), cómo está construida y qué no cubre.
- `docs/evidencia/rendimiento.md` — medición con volumen: planes, hallazgos y decisiones sobre índices.
- `docs/operacion.md` — respaldo y restauración probados, `pg_hba`, registro del servidor, retención de la auditoría, proceso periódico de privacidad, observabilidad y mantenimiento.

## Límites conocidos

Es un prototipo. Los principales (lista completa en `docs/dictamen.md` §4 y §6):

- La contraseña del usuario llega en claro al motor (`crypt()` en la base); en producción el hash lo calcula el backend.
- Sin TLS, sin PgBouncer real, sin recuperación a un punto en el tiempo y con respaldos sin cifrar.
- Las tareas periódicas (respaldo, anonimización de vencidos) tienen script pero no están programadas.
- Cuatro reglas que la base no hace cumplir y quedan a cargo de la API y de la configuración de producción (temas T-63 a T-66, `docs/decisiones.md` §12.6).
- Los supuestos legales (Ley N° 21.719, plazos de retención) están marcados **validar**: no es asesoría legal.
- `make` no se probó literalmente en este equipo; la evidencia ejecuta las recetas del `Makefile`.

## V013: alternativas guardadas

`V013__repuestos_guardados.sql` incorpora referencias seleccionadas por propietario/mecánico, con RLS, autor, contexto DTC/componente, idempotencia y auditoría. No modifica el estado de diagnósticos ni crea cotizaciones. No conserva precios, títulos, imágenes ni stock externos.

V014 completa las convenciones del esquema: nombres explícitos de restricciones/políticas, comentarios de columnas y claves foráneas con `ON DELETE RESTRICT`. Conserva los datos y la migración V013 original.

En una base existente hasta V012, aplicar `bash db/scripts/migrate.sh V013` y después `bash db/scripts/migrate.sh V014`. Si V013 ya está aplicada, ejecutar solamente V014. Respaldar antes. No volver a ejecutar todas las migraciones sobre una base existente.

Revisión del incremento: 517 comprobaciones de los doce archivos SQL aprobadas sobre una copia aislada; pruebas de backend adicionales cubren guardado, idempotencia, RLS y contexto cambiado. Las pruebas de esquema y auditoría ahora incluyen los objetos de V013.

[Flujo y evidencia de validación](../Backend_Repuestos_Exactos/docs/integracion_mercadolibre.md).

## V015: captura OBD2 con observaciones por ECU

V015__captura_obd.sql permite registrar lógicamente un adaptador sin una MAC inventada y añade metadatos de captura e idempotencia a sesion_diagnostico. observacion_obd conserva código, ECU y categoría (almacenado/pendiente/permanente), incluidos códigos que no existen en dtc_catalogo. El vínculo compuesto sesión/taller, RLS forzada, permisos y auditoría siguen las convenciones existentes. Las sesiones y fallas previas se conservan.

El propietario registra adaptadores; propietario y mecánico pueden registrar diagnósticos con su identidad y taller. La API crea también falla_sesion para los códigos catalogados. Guardar una captura no crea cotizaciones ni modifica estados de reparación. El reintento usa una clave única por taller y una huella del contenido; la API comprueba además autor y contexto.

Para una base existente en V014: respaldar y ejecutar bash db/scripts/migrate.sh V015 desde RE-db. No volver a ejecutar todas las migraciones ni eliminar el volumen. La base local de este workspace ya tiene V015 aplicada y cuenta con un respaldo previo fuera de Git.

Validación: 517 comprobaciones de los doce archivos db/tests sobre una copia aislada y pruebas Dart de captura/idempotencia/RLS con PostgreSQL real. Los conteos de esquema y auditoría incluyen observacion_obd. Las lecturas físicas del vLinker MC están pendientes; estas pruebas no verifican radio Bluetooth ni comportamiento de un vehículo real.

[Traza](../Backend_Repuestos_Exactos/docs/evidencia/traza_bluetooth_obd2.json) · [Evidencia](../Backend_Repuestos_Exactos/docs/evidencia/bluetooth_validacion.json).

## V016: Peugeot 3008 y uso del VIN existente

V016__catalogo_peugeot_3008.sql añade de forma idempotente Peugeot / 3008 al catálogo global. El año 2017 se declara al registrar el vehículo; la migración no crea un vehículo, VIN, motor, falla ni compatibilidad de repuesto de ejemplo. Aplicar sobre V015 con respaldo: bash db/scripts/migrate.sh V016.

El VIN automático usa vehiculo.vin, su índice único por taller, permisos, RLS y exclusión de identificadores de auditoría ya existentes. No necesita columnas nuevas. La API completa un VIN vacío y guarda la captura en la misma transacción; rechaza identidades distintas y no conserva copias adicionales del VIN. El detalle del diagnóstico muestra la identidad actual del vehículo, no una copia histórica inmutable. La anonimización existente continúa eliminando el VIN.

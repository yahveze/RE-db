# Repuestos Exactos — base de datos

Base de datos PostgreSQL 16 del sistema **Repuestos Exactos** (diagnóstico OBD-II y matriz comparativa de
repuestos para talleres mecánicos). Proyecto universitario de Ingeniería en Computación e Informática.

> Estado: **Fase 6** (esquema, seguridad, semillas, consultas, transacciones, suite de 514 pruebas, medición de rendimiento y operación con respaldo y restauración probados). Este README se completa en la Fase 7.

## Requisitos

- Docker en ejecución (Docker Desktop en Windows).
- Bash (Git Bash en Windows).
- `make` es opcional: cada objetivo del `Makefile` delega en un script de `db/`.

## Inicio rápido

```bash
cp .env.example .env        # y reemplazar los placeholders por claves propias
docker compose up -d --wait # o: make up
bash db/scripts/psql.sh -c "SELECT version();"
```

| Objetivo | Sin make |
|---|---|
| `make up` | `docker compose up -d --wait` |
| `make down` | `docker compose down` |
| `make reset` | `bash db/scripts/reset.sh` |
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
bash db/scripts/evidencia_fase3.sh                              # regenera docs/evidencia/fase3_*.txt
```

## Pruebas

```bash
bash db/tests/run_all.sh           # suite completa; codigo 0 = todo PASS
bash db/tests/control_negativo.sh  # demuestra que la prueba de concurrencia detecta el defecto de T-8
```

La suite corre sobre las semillas y no deja cambios, salvo los registros de auditoría de la prueba de
concurrencia.

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

## Documentación

- `docs/decisiones.md` — resumen ejecutivo, decisiones abiertas, supuestos y temas para conversar.
- `docs/modelo/` — dominio y reglas de negocio, modelo conceptual (Mermaid), modelo lógico, normalización y diccionario de datos (generado).
- `docs/seguridad.md`, `docs/privacidad.md` — roles, RBAC y RLS, autenticación, auditoría, supresión y anonimización.
- `docs/consultas.md`, `docs/transacciones.md` — contrato de las consultas del frontend (`db/queries/`) y transacciones atómicas.
- `docs/pruebas.md` — qué prueba la suite (`db/tests/`), cómo está construida y qué no cubre.
- `docs/evidencia/rendimiento.md` — medición con volumen: planes, hallazgos y decisiones sobre índices.
- `docs/operacion.md` — respaldo y restauración probados, `pg_hba`, registro del servidor, retención de la auditoría, proceso periódico de privacidad, observabilidad y mantenimiento.
- `docs/evidencia/` — salidas reales de las ejecuciones.

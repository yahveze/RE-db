# Repuestos Exactos — base de datos

Base de datos PostgreSQL 16 del sistema **Repuestos Exactos** (diagnóstico OBD-II y matriz comparativa de
repuestos para talleres mecánicos). Proyecto universitario de Ingeniería en Computación e Informática.

> Estado: **Fase 4** (esquema, seguridad, semillas, consultas, transacciones y suite de 468 pruebas; faltan rendimiento y operación). Este README se completa en la Fase 7.

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

La base queda publicada solo en `127.0.0.1:5433`. `.env` nunca se versiona.

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

## Documentación

- `docs/decisiones.md` — resumen ejecutivo, decisiones abiertas, supuestos y temas para conversar.
- `docs/modelo/` — dominio y reglas de negocio, modelo conceptual (Mermaid), modelo lógico, normalización y diccionario de datos (generado).
- `docs/seguridad.md`, `docs/privacidad.md` — roles, RBAC y RLS, autenticación, auditoría, supresión y anonimización.
- `docs/consultas.md`, `docs/transacciones.md` — contrato de las consultas del frontend (`db/queries/`) y transacciones atómicas.
- `docs/pruebas.md` — qué prueba la suite (`db/tests/`), cómo está construida y qué no cubre.
- `docs/operacion.md` — Fase 6.
- `docs/evidencia/` — salidas reales de las ejecuciones.

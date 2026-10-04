# Repuestos Exactos — base de datos

Base de datos PostgreSQL 16 del sistema **Repuestos Exactos** (diagnóstico OBD-II y matriz comparativa de
repuestos para talleres mecánicos). Proyecto universitario de Ingeniería en Computación e Informática.

> Estado: **Fase 2** (esquema y seguridad implementados; faltan semillas, consultas y pruebas). Este README se completa en la Fase 7.

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

## Documentación

- `docs/decisiones.md` — resumen ejecutivo, decisiones abiertas, supuestos y temas para conversar.
- `docs/modelo/` — dominio y reglas de negocio, modelo conceptual (Mermaid), modelo lógico, normalización y diccionario de datos (generado).
- `docs/seguridad.md`, `docs/privacidad.md` — roles, RBAC y RLS, autenticación, auditoría, supresión y anonimización.
- `docs/operacion.md` — Fase 6.
- `docs/evidencia/` — salidas reales de las ejecuciones.

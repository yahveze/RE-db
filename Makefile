# Repuestos Exactos - tareas de base de datos.
# Cada objetivo delega en un script de db/, de modo que tambien se pueden
# ejecutar sin make (por ejemplo: bash db/scripts/migrate.sh).
SHELL := bash

.PHONY: up down reset migrate seed test perf psql all

up:
	docker compose up -d --wait

down:
	docker compose down

# Elimina el volumen del proyecto y recrea una base vacia.
reset:
	bash db/scripts/reset.sh

migrate:
	bash db/scripts/migrate.sh

seed:
	bash db/scripts/seed.sh

test:
	bash db/tests/run_all.sh

perf:
	bash db/perf/run.sh

psql:
	bash db/scripts/psql.sh

all: reset migrate seed test

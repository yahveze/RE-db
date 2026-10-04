# Repuestos Exactos - tareas de base de datos.
# Cada objetivo delega en un script de db/, de modo que tambien se pueden
# ejecutar sin make (por ejemplo: bash db/scripts/migrate.sh).
SHELL := bash

.PHONY: up down reset migrate seed test perf psql all backup verify-backup restore restore-test status

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

# --- Operacion (Fase 6, docs/operacion.md) ---

# Respaldo logico en backups/ (ignorada por Git).
backup:
	bash db/scripts/respaldar.sh

# Restaura el ultimo respaldo en una base temporal y lo compara; no toca la principal.
verify-backup:
	bash db/scripts/verificar_respaldo.sh

# DESTRUCTIVO: reemplaza la base por el respaldo. make restore ARCHIVO=backups/x.dump CONFIRMAR=<base>
restore:
	CONFIRMAR=$(CONFIRMAR) bash db/scripts/restaurar.sh $(ARCHIVO)

# DESTRUCTIVO: respaldo -> elimina el volumen -> restaura -> compara -> suite.
restore-test:
	bash db/scripts/prueba_restauracion.sh

status:
	bash db/scripts/estado.sh

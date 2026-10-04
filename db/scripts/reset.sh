#!/usr/bin/env bash
# Elimina el contenedor y el volumen de ESTE proyecto y recrea una base vacia.
# 'down -v' solo afecta a los recursos del proyecto compose de esta carpeta.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

docker compose down -v --remove-orphans
esperar_db
echo "reset: base vacia lista"

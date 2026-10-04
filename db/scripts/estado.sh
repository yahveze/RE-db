#!/usr/bin/env bash
# Estado de la base para el operador: conexiones, bloqueos, tablas, indices sin
# uso, sentencias mas costosas, auditoria y pendientes de privacidad.
# Solo lectura. Consultas en db/ops/observabilidad.sql.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

psql_super -f /db/ops/observabilidad.sql

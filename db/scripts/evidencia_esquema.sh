#!/usr/bin/env bash
# Genera docs/evidencia/esquema.txt a partir del catalogo del motor
# (\dt, \du, \d+, pg_policies, role_table_grants, ...).
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

salida="docs/evidencia/esquema.txt"
{
  echo "# Esquema real de la base (generado por db/scripts/evidencia_esquema.sh)"
  echo "# Fecha: $(date -u +%Y-%m-%dT%H:%MZ)"
  echo
  psql_super -f /db/scripts/evidencia_esquema.sql
} > "$salida" 2>&1
echo "evidencia: $salida ($(wc -l < "$salida") lineas)"

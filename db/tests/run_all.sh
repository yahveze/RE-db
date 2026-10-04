#!/usr/bin/env bash
# Ejecuta db/tests/*.sql. Termina con codigo distinto de cero si psql falla
# o si alguna prueba imprime FAIL. La suite se escribe en la Fase 4.
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/_lib.sh"

shopt -s nullglob
archivos=(db/tests/*.sql)
if [ ${#archivos[@]} -eq 0 ]; then
  echo "test: AVISO - todavia no hay pruebas en db/tests/ (0 ejecutadas)"
  exit 0
fi

fallos=0
for archivo in "${archivos[@]}"; do
  nombre="$(basename "$archivo")"
  echo "==> $nombre"
  if ! salida="$(psql_super -f "/db/tests/$nombre" 2>&1)"; then
    echo "$salida"
    echo "FAIL: $nombre termino con error de psql"
    fallos=$((fallos + 1))
    continue
  fi
  echo "$salida"
  if grep -q "FAIL" <<<"$salida"; then
    fallos=$((fallos + 1))
  fi
done

if [ "$fallos" -gt 0 ]; then
  echo "test: $fallos archivo(s) con fallos"
  exit 1
fi
echo "test: todo PASS"

#!/usr/bin/env bash
# Genera la evidencia de la Fase 4 sobre una base migrada y con semillas:
#   docs/evidencia/fase4_pruebas.txt           salida completa de la suite
#   docs/evidencia/fase4_control_negativo.txt  la prueba de concurrencia detecta
#                                              el defecto de T-8 cuando se reintroduce
# Termina con codigo distinto de cero si la suite o el control fallan.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

generar() {
  local salida="$1" titulo="$2"; shift 2
  local codigo=0
  {
    echo "# $titulo (generado por db/scripts/evidencia_fase4.sh)"
    echo "# Fecha: $(date -u +%Y-%m-%dT%H:%MZ)"
    echo
    "$@" || codigo=$?
    echo
    echo "# codigo de salida: $codigo"
  } > "$salida" 2>&1
  echo "evidencia: $salida ($(wc -l < "$salida") lineas, codigo $codigo)"
  return "$codigo"
}

fallo=0
generar docs/evidencia/fase4_pruebas.txt          "Suite de pruebas (db/tests/run_all.sh)" bash db/tests/run_all.sh || fallo=1
generar docs/evidencia/fase4_control_negativo.txt "Control negativo de concurrencia (db/tests/control_negativo.sh)" bash db/tests/control_negativo.sh || fallo=1
exit "$fallo"

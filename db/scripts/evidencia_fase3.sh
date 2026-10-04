#!/usr/bin/env bash
# Genera la evidencia de la Fase 3 sobre una base ya migrada y con semillas:
#   docs/evidencia/fase3_semillas.txt       resumen y verificaciones de la carga
#   docs/evidencia/fase3_consultas.txt      consultas de lectura (sin errores)
#   docs/evidencia/fase3_transacciones.txt  transacciones (con errores esperados)
# Ninguno de los tres guiones modifica datos. Termina con codigo distinto de
# cero si una consulta falla o si las transacciones producen un numero de
# errores distinto del que el guion declara esperar.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

generar() {
  local salida="$1" titulo="$2" guion="$3"
  {
    echo "# $titulo (generado por db/scripts/evidencia_fase3.sh)"
    echo "# Fecha: $(date -u +%Y-%m-%dT%H:%MZ)"
    echo
    psql_super -f "$guion"
  } > "$salida" 2>&1
  echo "evidencia: $salida ($(wc -l < "$salida") lineas)"
}

generar docs/evidencia/fase3_semillas.txt      "Semillas: verificacion y resumen"      /db/seeds/99_resumen.sql
generar docs/evidencia/fase3_consultas.txt     "Consultas de lectura sobre las semillas" /db/queries/demo_consultas.sql
generar docs/evidencia/fase3_transacciones.txt "Transacciones de escritura"            /db/queries/demo_transacciones.sql

# Cada error esperado del guion va seguido de una linea que imprime su SQLSTATE.
esperados="$(grep -c 'LAST_ERROR_SQLSTATE' db/queries/demo_transacciones.sql)"
obtenidos="$(grep -c 'ERROR:' docs/evidencia/fase3_transacciones.txt || true)"
if [ "$esperados" != "$obtenidos" ]; then
  echo "evidencia: FALLO - transacciones con $obtenidos errores, se esperaban $esperados" >&2
  exit 1
fi
if ! grep -q '^ t  *| t  *| t  *| t  *| t  *| t ' docs/evidencia/fase3_transacciones.txt; then
  echo "evidencia: FALLO - la demostracion de transacciones dejo cambios en la base" >&2
  exit 1
fi
echo "evidencia: transacciones con $obtenidos errores, todos esperados; base sin cambios"

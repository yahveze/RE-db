#!/usr/bin/env bash
# Suite de pruebas. Requiere la base migrada y con semillas.
#   1. db/tests/NN_*.sql  -> cada archivo corre en una transaccion con ROLLBACK
#                            e imprime una linea PASS o FAIL por prueba.
#   2. db/tests/concurrencia.sh -> dos conexiones reales por escenario.
#   3. db/tests/operacion.sh    -> autenticacion local, log del servidor y
#                                  scripts de operacion (Fase 6).
# Termina con codigo distinto de cero si:
#   * alguna prueba imprime FAIL;
#   * psql termina con error;
#   * un archivo produce un numero de errores SQL ("ERROR:") distinto del de sus
#     pruebas de error ("[E]"): asi un error NO esperado no pasa inadvertido.
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/_lib.sh"

shopt -s nullglob
archivos=(db/tests/*.sql)
if [ ${#archivos[@]} -eq 0 ]; then
  echo "test: AVISO - todavia no hay pruebas en db/tests/ (0 ejecutadas)"
  exit 0
fi

if [ "$(psql_super -At -c "SELECT count(*) FROM taller")" = "0" ]; then
  echo "test: la base no tiene semillas (ejecutar antes: bash db/scripts/seed.sh)" >&2
  exit 1
fi

contar() { grep -c "$1" <<<"$2" || true; }

total_pass=0
total_fail=0
con_fallos=0
for archivo in "${archivos[@]}"; do
  nombre="$(basename "$archivo")"
  if salida="$(psql_super -f "/db/tests/$nombre" 2>&1)"; then codigo=0; else codigo=$?; fi
  echo "$salida"
  pass="$(contar '^PASS |' "$salida")"
  fail="$(contar '^FAIL |' "$salida")"
  errores="$(contar 'ERROR:' "$salida")"
  esperados="$(contar '^\(PASS\|FAIL\) | \[E\]' "$salida")"
  total_pass=$((total_pass + pass))
  total_fail=$((total_fail + fail))
  estado="ok"
  if [ "$codigo" -ne 0 ]; then
    echo "FAIL | $nombre: psql termino con codigo $codigo"; estado="FALLO"
  fi
  if [ "$errores" != "$esperados" ]; then
    echo "FAIL | $nombre: $errores errores SQL para $esperados pruebas de error (hay un error no esperado)"; estado="FALLO"
  fi
  if [ "$fail" -gt 0 ] || [ "$pass" -eq 0 ]; then estado="FALLO"; fi
  [ "$estado" = "ok" ] || con_fallos=$((con_fallos + 1))
  echo "==> $nombre: $pass PASS, $fail FAIL, $errores errores esperados [$estado]"
  echo
done

guiones=(concurrencia.sh operacion.sh)
for guion in "${guiones[@]}"; do
  if salida="$(bash "db/tests/$guion" 2>&1)"; then codigo=0; else codigo=$?; fi
  echo "$salida"
  pass="$(contar '^PASS |' "$salida")"
  fail="$(contar '^FAIL |' "$salida")"
  total_pass=$((total_pass + pass))
  total_fail=$((total_fail + fail))
  if [ "$codigo" -ne 0 ] || [ "$fail" -gt 0 ] || [ "$pass" -eq 0 ]; then
    con_fallos=$((con_fallos + 1)); estado="FALLO"
  else
    estado="ok"
  fi
  echo "==> $guion: $pass PASS, $fail FAIL [$estado]"
  echo
done

if [ "$con_fallos" -gt 0 ]; then
  echo "test: $total_pass PASS, $total_fail FAIL - $con_fallos archivo(s) con fallos"
  exit 1
fi
echo "test: todo PASS ($total_pass pruebas en $(( ${#archivos[@]} + ${#guiones[@]} )) archivos)"

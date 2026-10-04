#!/usr/bin/env bash
# =============================================================================
# Control negativo de la prueba de concurrencia (no forma parte de run_all.sh).
#
# Una prueba que nunca falla no demuestra nada. Este guion reintroduce a
# proposito el defecto descrito en T-8: quita el bloqueo FOR SHARE con que el
# trigger del detalle lee la cabecera de la cotizacion. Con el defecto, una
# linea que llega durante el cierre deberia colarse en una cotizacion ya
# cerrada, y concurrencia.sh debe detectarlo (CON-01 en FAIL).
#
# La funcion original se guarda antes y se restaura SIEMPRE al salir (trap).
# Termina con codigo 0 solo si: con el defecto la prueba falla, y restaurada la
# funcion la prueba vuelve a pasar.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/_lib.sh"

funcion="fn_trg_cotizacion_detalle_validar"
original="$(mktemp)"
mutada="$(mktemp)"

psql_super -At -c "SELECT pg_get_functiondef('$funcion'::regproc)" > "$original"
if [ "$(grep -c 'FOR SHARE' "$original")" != "1" ]; then
  echo "control negativo: se esperaba exactamente un FOR SHARE en $funcion" >&2
  exit 1
fi
sed 's/FOR SHARE//' "$original" > "$mutada"

restaurar() {
  psql_super -At < "$original" >/dev/null
  rm -f "$original" "$mutada"
}
trap restaurar EXIT

echo "### Control negativo: $funcion SIN el bloqueo FOR SHARE"
psql_super -At < "$mutada" >/dev/null
if salida="$(bash db/tests/concurrencia.sh 2>&1)"; then codigo=0; else codigo=$?; fi
grep '^\(PASS\|FAIL\) | CON-0[12]' <<<"$salida" | cut -c1-200
detectado=no
if [ "$codigo" -ne 0 ] && grep -q '^FAIL | CON-01' <<<"$salida"; then detectado=si; fi

echo
echo "### Funcion restaurada"
psql_super -At < "$original" >/dev/null
if salida="$(bash db/tests/concurrencia.sh 2>&1)"; then codigo=0; else codigo=$?; fi
grep '^\(PASS\|FAIL\) | CON-0[12]' <<<"$salida" | cut -c1-200
restaurado=no
if [ "$codigo" -eq 0 ] && [ "$(psql_super -At -c "SELECT pg_get_functiondef('$funcion'::regproc) LIKE '%FOR SHARE%'")" = "t" ]; then
  restaurado=si
fi

echo
echo "defecto detectado por la prueba: $detectado"
echo "prueba en verde tras restaurar:  $restaurado"
[ "$detectado" = "si" ] && [ "$restaurado" = "si" ]

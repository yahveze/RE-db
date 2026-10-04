#!/usr/bin/env bash
# =============================================================================
# Genera la evidencia de la Fase 7 (cierre):
#   docs/evidencia/fase7_cierre.txt    criterio de aceptacion: 'make all' desde
#                                      una base vacia, estado final del esquema,
#                                      suite repetida y busqueda de secretos
#   docs/evidencia/fase7_dictamen.txt  comprobaciones y experimentos que cita
#                                      docs/dictamen.md (db/tests/humo/fase7_dictamen.sql)
#
# ATENCION: 'make all' empieza por 'reset', que ELIMINA el volumen del proyecto.
#
# Si 'make' esta instalado se ejecuta 'make all' literalmente. Si no (T-1), se
# leen del Makefile las dependencias de 'all' y la receta de cada una, y se
# ejecutan tal como estan escritas: lo que no se prueba es el programa make.
# docs/evidencia/fase7_antes.txt es una captura unica del estado anterior a
# V010 y no se regenera.
# Termina con codigo distinto de cero si algun paso falla.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

generar() {
  local salida="$1" titulo="$2"; shift 2
  local codigo=0
  {
    echo "# $titulo (generado por db/scripts/evidencia_fase7.sh)"
    echo "# Fecha: $(date -u +%Y-%m-%dT%H:%MZ)"
    echo
    "$@" || codigo=$?
    echo
    echo "# codigo de salida: $codigo"
  } > "$salida" 2>&1
  echo "evidencia: $salida ($(wc -l < "$salida") lineas, codigo $codigo)"
  return "$codigo"
}

# De la salida de la suite se conservan los resumenes por archivo y cualquier
# FAIL; la salida completa, prueba por prueba, es docs/evidencia/fase4_pruebas.txt.
resumir_suite() {
  { grep -E '^(reset:|==>|migrate:|seed:|test:|FAIL )' || true; }
}

receta() {
  awk -v objetivo="$1" '
    $0 ~ "^" objetivo ":" { dentro = 1; next }
    dentro && /^\t/       { sub(/^\t/, ""); print; next }
    dentro                { exit }' Makefile
}

cierre() {
  local codigo=0 objetivo linea v n archivos
  echo "## 1. Entorno"
  echo "commit de partida: $(git rev-parse --short HEAD) ($(git log -1 --format=%s))"
  echo "docker: $(docker version --format '{{.Server.Version}}' | tr -d '\r')   bash: ${BASH_VERSION}"
  if command -v make >/dev/null 2>&1; then
    echo "make: $(make --version | head -1)"
  else
    echo "make: NO instalado en este equipo (T-1)"
  fi
  echo
  echo "## 2. make all = reset -> migrate -> seed -> test, desde una base vacia"
  if command -v make >/dev/null 2>&1; then
    echo "\$ make all"
    make all 2>&1 | resumir_suite
    codigo=${PIPESTATUS[0]}
  else
    echo "Makefile: $(grep '^all:' Makefile)"
    for objetivo in $(sed -n 's/^all: *//p' Makefile); do
      while IFS= read -r linea; do
        echo "\$ $linea        # receta de '$objetivo' en el Makefile"
        bash -c "$linea" 2>&1 | resumir_suite
        [ "${PIPESTATUS[0]}" -eq 0 ] || codigo=1
      done < <(receta "$objetivo")
      [ "$codigo" -eq 0 ] || break
    done
  fi
  echo "codigo de salida de 'make all': $codigo"
  [ "$codigo" -eq 0 ] || return "$codigo"
  echo
  echo "## 3. Estado final del esquema"
  psql_super <<'SQL' || codigo=$?
SELECT version();
SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'r') AS tablas,
       (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'v' AND c.relname LIKE 'v\_%') AS vistas,
       (SELECT count(*) FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'public' AND t.typtype = 'e') AS enums,
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname LIKE 'fn\_%') AS funciones,
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname LIKE 'fn\_%' AND p.prosecdef) AS definidoras,
       (SELECT count(*) FROM pg_trigger g JOIN pg_class c ON c.oid = g.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND NOT g.tgisinternal) AS triggers,
       (SELECT count(*) FROM pg_policies WHERE schemaname = 'public') AS politicas,
       (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public') AS indices,
       (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND indexname LIKE 'ix\_%') AS indices_ix;
SELECT (SELECT count(*) FROM taller) AS talleres, (SELECT count(*) FROM usuario) AS usuarios,
       (SELECT count(*) FROM repuesto) AS repuestos, (SELECT count(*) FROM vehiculo) AS vehiculos,
       (SELECT count(*) FROM sesion_diagnostico) AS sesiones, (SELECT count(*) FROM cotizacion) AS cotizaciones;
SQL
  echo "migraciones: $(ls db/migrations/V*.sql | wc -l)   semillas: $(ls db/seeds/*.sql | wc -l)   sentencias PREPARE en db/queries/: $(cat db/queries/[qt]0*.sql | grep -c '^PREPARE ')"
  echo
  echo "## 4. La suite se puede repetir sobre la misma base (no deja cambios que la afecten)"
  echo "\$ $(receta test)"
  bash -c "$(receta test)" 2>&1 | { grep -E '^(test:|FAIL )' || true; }
  [ "${PIPESTATUS[0]}" -eq 0 ] || codigo=1
  echo
  echo "## 5. Secretos: valores de .env en archivos versionados o por versionar (solo conteos)"
  archivos="$(git ls-files -co --exclude-standard | wc -l)"
  for v in POSTGRES_PASSWORD APP_BACKEND_PASSWORD CLAVE_DEMO; do
    n="$(git ls-files -co --exclude-standard -z | xargs -0 grep -lF -- "${!v}" 2>/dev/null | wc -l)"
    echo "$v: $n de $archivos archivos"
    [ "$n" -eq 0 ] || codigo=1
  done
  echo ".env ignorado por Git: $(git check-ignore -q .env && echo si || echo NO)   backups/ ignorada: $(git check-ignore -q backups/x.dump && echo si || echo NO)"
  return "$codigo"
}

dictamen() {
  local codigo=0
  psql_super -f /db/tests/humo/fase7_dictamen.sql || codigo=$?
  return "$codigo"
}

fallo=0
generar docs/evidencia/fase7_cierre.txt   "Cierre: criterio de aceptacion (make all) y estado final" cierre || fallo=1
generar docs/evidencia/fase7_dictamen.txt "Dictamen de cierre: comprobaciones y experimentos (db/tests/humo/fase7_dictamen.sql)" dictamen || fallo=1

# El guion del dictamen espera exactamente UN error: el rechazo de la tabla
# temporal (B5a). Tras V010, la hipotesis B5b no desvia ningun registro.
errores="$(grep -c 'ERROR:' docs/evidencia/fase7_dictamen.txt || true)"
if [ "$errores" != "1" ]; then
  echo "evidencia: FALLO - el dictamen produjo $errores errores, se esperaba 1" >&2
  fallo=1
fi
if ! grep -A2 'registros_desviados_a_la_tabla_temporal' docs/evidencia/fase7_dictamen.txt | grep -q '^ *0$'; then
  echo "evidencia: FALLO - la tabla temporal recibio registros de auditoria (V010 no esta aplicada)" >&2
  fallo=1
fi
exit "$fallo"

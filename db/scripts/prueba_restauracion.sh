#!/usr/bin/env bash
# =============================================================================
# Prueba de recuperacion ante la perdida total de la base (make restore-test).
#
# ES DESTRUCTIVA sobre el entorno de desarrollo: elimina el volumen del proyecto
# (igual que reset.sh) y reconstruye la base SOLO desde el respaldo. Requiere la
# base migrada y con semillas.
#
#   1. Huella de los datos y del esquema de la base de origen.
#   2. Respaldo (respaldar.sh).
#   3. Un cambio posterior al respaldo: se solicita la supresion de un titular.
#   4. Perdida total: se elimina el contenedor y el volumen (reset.sh). El
#      cluster nuevo no tiene roles ni tablas.
#   5. Restauracion (restaurar.sh) desde los archivos del respaldo y .env.
#   6. La huella de datos y la del esquema deben ser identicas a las del paso 1.
#      El cambio del paso 3 se pierde: es el limite de un respaldo logico.
#   7. La suite completa debe pasar sobre la base restaurada.
#
# Termina con codigo 0 solo si la huella coincide y la suite pasa.
# Evidencia: bash db/scripts/evidencia_fase6.sh -> docs/evidencia/fase6_respaldo.txt
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

if [ "$(psql_super -At -c "SELECT count(*) FROM taller")" = "0" ]; then
  echo "prueba de restauracion: la base no tiene semillas (ejecutar antes: bash db/scripts/seed.sh)" >&2
  exit 1
fi

huella_datos()   { psql_super -At -f /db/ops/huella.sql; }
# El volcado del esquema se normaliza en dos puntos que cambian sin que cambie
# el esquema:
#   * \restrict / \unrestrict llevan un testigo aleatorio distinto en cada volcado;
#   * la lista de roles de una politica (TO a, b, c) sale en el orden de los OID
#     de los roles, y un cluster restaurado los crea en otro orden: se ordena.
normalizar_esquema() {
  grep -v '^\\\(un\)\?restrict ' | awk '
    /^CREATE POLICY .* TO / {
      i = index($0, " TO "); resto = substr($0, i + 4)
      j = match(resto, / (USING|WITH CHECK) /)
      if (j > 0) {
        n = split(substr(resto, 1, j - 1), r, ", ")
        for (a = 1; a <= n; a++) for (b = a + 1; b <= n; b++) if (r[b] < r[a]) { t = r[a]; r[a] = r[b]; r[b] = t }
        lista = r[1]; for (a = 2; a <= n; a++) lista = lista ", " r[a]
        $0 = substr($0, 1, i + 3) lista substr(resto, j)
      }
    }
    { print }'
}
huella_esquema() { en_contenedor pg_dump --schema-only -d "$POSTGRES_DB" | normalizar_esquema | sha256sum | cut -d' ' -f1; }
privacidad() {
  psql_super -At -F ' ' -c "SELECT 'titulares activos:', count(*) FILTER (WHERE estado_tratamiento = 'activo'), '| bloqueados:', count(*) FILTER (WHERE estado_tratamiento = 'bloqueado'), '| anonimizados:', count(*) FILTER (WHERE estado_tratamiento = 'anonimizado'), '| solicitudes de derechos:', (SELECT count(*) FROM solicitud_derecho_titular) FROM titular"
}
resumen_cluster() {
  psql_super -At -F ' ' -c "SELECT 'roles de la aplicacion:', (SELECT count(*) FROM pg_roles WHERE rolname ~ '^(app_|taller_)'), '| tablas:', (SELECT count(*) FROM pg_tables WHERE schemaname = 'public'), '| politicas RLS:', (SELECT count(*) FROM pg_policies WHERE schemaname = 'public'), '| funciones:', (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname LIKE 'fn\\_%'), '| triggers:', (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid WHERE c.relnamespace = 'public'::regnamespace AND NOT t.tgisinternal)"
}

echo "### 1. Base de origen"
datos_antes="$(huella_datos)"
esquema_antes="$(huella_esquema)"
resumen_cluster
echo "tablas: $(grep -vc '^secuencia ' <<<"$datos_antes") | filas: $(grep -v '^secuencia ' <<<"$datos_antes" | awk -F'|' '{ n += $2 } END { print n }')"
echo "huella de datos (sha256 de db/ops/huella.sql): $(sha256sum <<<"$datos_antes" | cut -d' ' -f1)"
echo "huella de esquema (sha256 de pg_dump --schema-only): $esquema_antes"
privacidad
echo

echo "### 2. Respaldo"
salida="$(bash db/scripts/respaldar.sh)"
grep -v '^RESPALDO=' <<<"$salida"
dump="$(sed -n 's/^RESPALDO=//p' <<<"$salida")"
echo

echo "### 3. Cambio posterior al respaldo: el administrador solicita la supresion de un titular"
psql_super >/dev/null <<'SQL'
BEGIN;
SELECT set_config('app.taller_id',  (SELECT taller_id::text FROM usuario WHERE email = 'admin@losaromos.example'), true),
       set_config('app.usuario_id', (SELECT id::text        FROM usuario WHERE email = 'admin@losaromos.example'), true),
       set_config('app.request_id', 'prueba-restauracion', true);
SET LOCAL ROLE taller_admin;
SELECT fn_solicitar_supresion_titular(t.id)
FROM   (SELECT id FROM titular WHERE estado_tratamiento = 'activo' ORDER BY id LIMIT 1) t;
COMMIT;
SQL
privacidad
echo

echo "### 4. Perdida total: se elimina el contenedor y el volumen"
bash db/scripts/reset.sh 2>&1 | grep '^reset:'
resumen_cluster
echo

echo "### 5. Restauracion desde el respaldo"
CONFIRMAR="$POSTGRES_DB" bash db/scripts/restaurar.sh "$dump"
echo

echo "### 6. Comparacion con la base de origen"
datos_despues="$(huella_datos)"
esquema_despues="$(huella_esquema)"
resumen_cluster
echo "huella de datos: $(sha256sum <<<"$datos_despues" | cut -d' ' -f1)"
echo "huella de esquema: $esquema_despues"
fallo=0
if [ "$datos_antes" = "$datos_despues" ]; then
  echo "DATOS: IDENTICOS (mismas filas y mismo md5 en las $(grep -vc '^secuencia ' <<<"$datos_antes") tablas; mismas secuencias)"
else
  echo "DATOS: DIFERENTES"
  diff <(echo "$datos_antes") <(echo "$datos_despues") || true
  fallo=1
fi
if [ "$esquema_antes" = "$esquema_despues" ]; then
  echo "ESQUEMA: IDENTICO (tablas, restricciones, indices, funciones, triggers, privilegios y politicas)"
else
  echo "ESQUEMA: DIFERENTE"
  fallo=1
fi
echo "conexion del backend con la clave de .env: $(psql_backend -c "SELECT session_user" 2>&1 | tr -d '\r')"
echo "el cambio del paso 3 no esta en la base restaurada (la solicitud de supresion debe reaplicarse a mano):"
privacidad
echo

echo "### 7. Suite completa sobre la base restaurada"
if salida="$(bash db/tests/run_all.sh 2>&1)"; then codigo=0; else codigo=$?; fi
grep -E '^==>|^test:|^FAIL' <<<"$salida"
echo "codigo de salida de la suite: $codigo"
[ "$codigo" -eq 0 ] || fallo=1

echo
if [ "$fallo" -eq 0 ]; then
  echo "prueba de restauracion: CORRECTA"
else
  echo "prueba de restauracion: FALLO"
fi
exit "$fallo"

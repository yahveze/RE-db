#!/usr/bin/env bash
# =============================================================================
# Pruebas de concurrencia: DOS conexiones reales por escenario, ambas con el rol
# de conexion del backend (app_backend_user) y SET LOCAL ROLE taller_mecanico.
#
# Metodo. En cada escenario la sesion A ejecuta su operacion y mantiene la
# transaccion abierta 4 segundos (pg_sleep) antes de COMMIT. La sesion B espera
# 1,5 segundos y lanza la operacion que entra en conflicto. De B se registra:
#   * cuanto tardo su sentencia (si espero mas de 1 s, estuvo bloqueada por A);
#   * el SQLSTATE con que termino.
# Al final se lee el estado que quedo en la base. Todos los escenarios corren en
# paralelo: cada uno usa su propia sesion de diagnostico (kilometraje 90000N).
#
# A diferencia del resto de la suite, aqui las transacciones hacen COMMIT (no
# hay otra forma de que dos conexiones se vean). Los datos de prueba se crean
# al empezar y se borran al terminar; solo quedan sus registros de auditoria,
# que por diseno no se pueden borrar.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/_lib.sh"

dir="$(mktemp -d)"

# psql_backend (db/scripts/_lib.sh): psql como app_backend_user, con su clave,
# por el socket local del contenedor. El guion SQL llega por la entrada estandar.

limpiar() {
  psql_super -At <<'SQL' >/dev/null
BEGIN;
DELETE FROM cotizacion WHERE sesion_id IN (SELECT id FROM sesion_diagnostico WHERE kilometraje BETWEEN 900001 AND 900009);
DELETE FROM falla_sesion WHERE sesion_id IN (SELECT id FROM sesion_diagnostico WHERE kilometraje BETWEEN 900001 AND 900009);
DELETE FROM sesion_diagnostico WHERE kilometraje BETWEEN 900001 AND 900009;
DELETE FROM vehiculo WHERE patente = 'ZZZZ99';
UPDATE usuario_credencial SET intentos_fallidos = 0, bloqueado_hasta = NULL
WHERE  usuario_id = (SELECT id FROM usuario WHERE email = 'auditor@nuble.example');
COMMIT;
SQL
}
trap 'limpiar; rm -rf "$dir"' EXIT

echo "### Concurrencia"
limpiar

# ----------------------------------------------------------------------------
# Datos de prueba, creados con el rol y el flujo del mecanico.
#   1, 2, 7, 8, 9: borrador con una linea     3, 4: sin cotizacion
#   5, 6: cotizacion cerrada y sesion en 'cotizado'
# ----------------------------------------------------------------------------
psql_super -At <<'SQL' >/dev/null
BEGIN;
SELECT set_config('app.taller_id',  (SELECT id::text FROM taller  WHERE nombre = 'Taller Mecánico Los Aromos'), true),
       set_config('app.usuario_id', (SELECT id::text FROM usuario WHERE email = 'mecanico1@losaromos.example'), true),
       set_config('app.request_id', 'concurrencia-preparacion', true);
SET LOCAL ROLE taller_mecanico;

INSERT INTO vehiculo (taller_id, modelo_vehiculo_id, anio, motor, patente)
SELECT fn_contexto_taller_id(), mo.id, 2020, '2.4 Diésel', 'ZZZZ99' FROM modelo_vehiculo mo WHERE mo.nombre = 'Hilux';

INSERT INTO sesion_diagnostico (taller_id, vehiculo_id, usuario_id, metodo_ingreso, kilometraje)
SELECT v.taller_id, v.id, fn_contexto_usuario_id(), 'manual', 900000 + g
FROM   vehiculo v, generate_series(1, 9) g WHERE v.patente = 'ZZZZ99';

INSERT INTO falla_sesion (sesion_id, dtc_id, taller_id, severidad)
SELECT s.id, d.id, s.taller_id, 'alta'
FROM   sesion_diagnostico s, dtc_catalogo d WHERE s.kilometraje BETWEEN 900001 AND 900009 AND d.codigo = 'P0301';

SELECT count(*) FROM sesion_diagnostico s, LATERAL fn_crear_cotizacion(s.id, gen_random_uuid()) c
WHERE  s.kilometraje IN (900001, 900002, 900005, 900006, 900007, 900008, 900009);

INSERT INTO cotizacion_detalle (cotizacion_id, repuesto_id, taller_id, cantidad)
SELECT c.id, r.id, c.taller_id, 1
FROM   cotizacion c JOIN sesion_diagnostico s ON s.id = c.sesion_id, repuesto r
WHERE  s.kilometraje BETWEEN 900001 AND 900009 AND r.codigo_fabricante = 'ILKAR7B11';

SELECT count(*) FROM cotizacion c JOIN sesion_diagnostico s ON s.id = c.sesion_id, LATERAL fn_cerrar_cotizacion(c.id) x
WHERE  s.kilometraje IN (900005, 900006);
SELECT count(*) FROM sesion_diagnostico s, LATERAL fn_cambiar_estado_sesion(s.id, 'cotizado') x
WHERE  s.kilometraje IN (900005, 900006);
COMMIT;
SQL

taller="$(psql_super -At -c "SELECT id FROM taller WHERE nombre = 'Taller Mecánico Los Aromos'")"
usuario="$(psql_super -At -c "SELECT id FROM usuario WHERE email = 'mecanico1@losaromos.example'")"

# Abre la peticion del mecanico. $1 = segundos que espera antes de empezar.
cabecera() {
  cat <<SQL
\\set ON_ERROR_STOP off
SELECT pg_sleep($1);
BEGIN;
SET LOCAL ROLE taller_mecanico;
SELECT set_config('app.taller_id', '$taller', true), set_config('app.usuario_id', '$usuario', true),
       set_config('app.request_id', 'concurrencia', true);
SQL
}

# Sesion A: ejecuta $2 y retiene sus bloqueos 4 segundos antes de confirmar.
sesion_a() {
  { cabecera 0; echo "$2"; echo "SELECT pg_sleep(4); COMMIT;"; } | psql_backend > "$dir/$1.a" 2>&1 &
}

# Sesion B: empieza 1,5 s despues, ejecuta $2 y registra SQLSTATE y espera.
sesion_b() {
  { cabecera 1.5
    echo "SELECT clock_timestamp() AS t0 \\gset"
    echo "$2"
    echo "\\echo SQLSTATE=:SQLSTATE"
    echo "COMMIT;"
    echo "SELECT 'ESPERO=' || (clock_timestamp() - :'t0'::timestamptz > interval '1 second');"
  } | psql_backend > "$dir/$1.b" 2>&1 &
}

S() { echo "(SELECT s.id FROM sesion_diagnostico s WHERE s.kilometraje = 90000$1)"; }
C() { echo "(SELECT c.id FROM cotizacion c JOIN sesion_diagnostico s ON s.id = c.sesion_id WHERE s.kilometraje = 90000$1 ORDER BY c.id LIMIT 1)"; }
linea() { echo "INSERT INTO cotizacion_detalle (cotizacion_id, repuesto_id, taller_id, cantidad)
SELECT $(C "$1"), r.id, $taller, $3 FROM repuesto r WHERE r.codigo_fabricante = '$2'"; }
clave='eeeeeeee-0000-4000-8000-00000000000'

# C1  A cierra la cotizacion; B agrega una linea mientras tanto.
sesion_a c1 "SELECT count(*) FROM fn_cerrar_cotizacion($(C 1));"
sesion_b c1 "$(linea 1 GEN-BOB-01 1);"
# C2  A agrega una linea (sin confirmar); B cierra la cotizacion.
sesion_a c2 "$(linea 2 GEN-BOB-01 1);"
sesion_b c2 "SELECT count(*) FROM fn_cerrar_cotizacion($(C 2));"
# C3  A y B crean la cotizacion con la MISMA clave de idempotencia.
sesion_a c3 "SELECT count(*) FROM fn_crear_cotizacion($(S 3), '${clave}3');"
sesion_b c3 "SELECT count(*) FROM fn_crear_cotizacion($(S 3), '${clave}3');"
# C4  A y B crean un borrador en la misma sesion con claves DISTINTAS.
sesion_a c4 "SELECT count(*) FROM fn_crear_cotizacion($(S 4), '${clave}4');"
sesion_b c4 "SELECT count(*) FROM fn_crear_cotizacion($(S 4), '${clave}5');"
# C5  A completa la sesion; B la cancela.
sesion_a c5 "SELECT count(*) FROM fn_cambiar_estado_sesion($(S 5), 'completado');"
sesion_b c5 "SELECT count(*) FROM fn_cambiar_estado_sesion($(S 5), 'cancelado');"
# C6  A completa la sesion; B la completa enviando la version que leyo antes (2).
sesion_a c6 "SELECT count(*) FROM fn_cambiar_estado_sesion($(S 6), 'completado');"
sesion_b c6 "SELECT count(*) FROM fn_cambiar_estado_sesion($(S 6), 'completado', 2);"
# C7  A y B cierran la misma cotizacion.
sesion_a c7 "SELECT count(*) FROM fn_cerrar_cotizacion($(C 7));"
sesion_b c7 "SELECT count(*) FROM fn_cerrar_cotizacion($(C 7));"
# C8  A y B cambian la cantidad del mismo repuesto (PUT de la misma linea).
sesion_a c8 "$(linea 8 ILKAR7B11 5) ON CONFLICT (cotizacion_id, repuesto_id) DO UPDATE SET cantidad = EXCLUDED.cantidad;"
sesion_b c8 "$(linea 8 ILKAR7B11 7) ON CONFLICT (cotizacion_id, repuesto_id) DO UPDATE SET cantidad = EXCLUDED.cantidad;"
# C9  A cancela la sesion; B cierra su borrador (bloqueos en el mismo orden: sesion -> cotizacion).
sesion_a c9 "SELECT count(*) FROM fn_cambiar_estado_sesion($(S 9), 'cancelado');"
sesion_b c9 "SELECT count(*) FROM fn_cerrar_cotizacion($(C 9));"
# C10 Dos inicios de sesion fallidos simultaneos del mismo usuario (sin rol ni contexto).
{ echo "BEGIN; SELECT autenticado FROM fn_autenticar_usuario('auditor@nuble.example', 'clave-mala-a');"
  echo "SELECT pg_sleep(4); COMMIT;"; } | psql_backend > "$dir/c10.a" 2>&1 &
{ echo "SELECT pg_sleep(1.5);"
  echo "SELECT clock_timestamp() AS t0 \\gset"
  echo "SELECT autenticado FROM fn_autenticar_usuario('auditor@nuble.example', 'clave-mala-b');"
  echo "\\echo SQLSTATE=:SQLSTATE"
  echo "SELECT 'ESPERO=' || (clock_timestamp() - :'t0'::timestamptz > interval '1 second');"
} | psql_backend > "$dir/c10.b" 2>&1 &

wait

# ----------------------------------------------------------------------------
# Estado final (una linea "clave=valor" por dato).
# ----------------------------------------------------------------------------
psql_super -At > "$dir/estado" <<'SQL'
WITH s AS (SELECT s.id, s.kilometraje - 900000 AS n, s.estado, s.version FROM sesion_diagnostico s WHERE s.kilometraje BETWEEN 900001 AND 900009),
     c AS (SELECT s.n, c.id, c.cerrada_en, c.total, c.vigente, c.version,
                  (SELECT count(*) FROM cotizacion_detalle d WHERE d.cotizacion_id = c.id) AS lineas,
                  (SELECT max(d.cantidad) FROM cotizacion_detalle d WHERE d.cotizacion_id = c.id) AS cantidad
           FROM cotizacion c JOIN s ON s.id = c.sesion_id)
SELECT 'c1=' || (SELECT cerrada_en IS NOT NULL AND lineas = 1 AND total = 11687 FROM c WHERE n = 1)
UNION ALL SELECT 'c2=' || (SELECT cerrada_en IS NOT NULL AND lineas = 2 AND total = 11687 + 23387 FROM c WHERE n = 2)
UNION ALL SELECT 'c3=' || (SELECT count(*) = 1 FROM c WHERE n = 3)
UNION ALL SELECT 'c4=' || (SELECT count(*) = 1 FROM c WHERE n = 4)
UNION ALL SELECT 'c5=' || (SELECT estado = 'completado' AND version = 3 FROM s WHERE n = 5)
UNION ALL SELECT 'c6=' || (SELECT estado = 'completado' AND version = 3 FROM s WHERE n = 6)
UNION ALL SELECT 'c7=' || (SELECT cerrada_en IS NOT NULL AND vigente AND version = 2 AND total = 11687 FROM c WHERE n = 7)
UNION ALL SELECT 'c8=' || (SELECT lineas = 1 AND cantidad = 7 FROM c WHERE n = 8)
UNION ALL SELECT 'c9=' || (SELECT (SELECT estado = 'cancelado' FROM s WHERE n = 9) AND cerrada_en IS NULL AND total IS NULL FROM c WHERE n = 9)
UNION ALL SELECT 'c10=' || (SELECT cr.intentos_fallidos = 2 FROM usuario_credencial cr JOIN usuario u ON u.id = cr.usuario_id
                            WHERE u.email = 'auditor@nuble.example');
SQL

fallos=0
# verificar <escenario> <SQLSTATE esperado de B> <descripcion>
verificar() {
  local e="$1" esperado="$2" descripcion="$3" obtenido espero estado
  obtenido="$(grep -o 'SQLSTATE=.*' "$dir/$e.b" | head -1 | cut -d= -f2 | tr -d '\r')"
  espero="$(grep -o 'ESPERO=.*' "$dir/$e.b" | head -1 | cut -d= -f2 | tr -d '\r')"
  estado="$(grep "^$e=" "$dir/estado" | cut -d= -f2 | tr -d '\r')"
  if [ "$obtenido" = "$esperado" ] && [ "$espero" = "true" ] && [ "$estado" = "true" ]; then
    echo "PASS | $descripcion (B espero a A; SQLSTATE $obtenido)"
  else
    echo "FAIL | $descripcion -> SQLSTATE de B '$obtenido' (esperado $esperado), B espero: '$espero', estado final correcto: '$estado'"
    sed 's/^/       A> /' "$dir/$e.a"; sed 's/^/       B> /' "$dir/$e.b"
    fallos=$((fallos + 1))
  fi
}

verificar c1  RE003 "CON-01 linea que llega durante el cierre: espera y es rechazada; el total no la incluye (T-8)"
verificar c2  00000 "CON-02 cierre durante una insercion de linea: espera y el total incluye la linea"
verificar c3  00000 "CON-03 misma clave de idempotencia en paralelo: una sola cotizacion (RN-57)"
verificar c4  23505 "CON-04 dos borradores en paralelo para la misma sesion: solo queda uno (RN-52)"
verificar c5  RE001 "CON-05 completar y cancelar a la vez: gana el primero, el segundo ve un estado terminal"
verificar c6  RE007 "CON-06 completar a la vez con version leida antes: conflicto de version, sin doble cambio"
verificar c7  00000 "CON-07 dos cierres de la misma cotizacion: el segundo la devuelve ya cerrada, sin tocarla"
verificar c8  00000 "CON-08 dos cambios de cantidad de la misma linea: se serializan, queda una linea"
verificar c9  RE004 "CON-09 cancelar la sesion y cerrar su borrador a la vez: el cierre es rechazado"
verificar c10 00000 "CON-10 dos logins fallidos simultaneos: el contador no pierde ninguno"

if grep -lq '40P01\|deadlock' "$dir"/*.a "$dir"/*.b 2>/dev/null; then
  echo "FAIL | CON-11 hubo un interbloqueo (deadlock) en algun escenario"
  fallos=$((fallos + 1))
else
  echo "PASS | CON-11 ningun escenario produjo un interbloqueo (orden de bloqueo sesion -> cotizacion)"
fi

con_error_a="$( { grep -l 'ERROR' "$dir"/*.a 2>/dev/null || true; } | wc -l | tr -d ' ')"
if [ "$con_error_a" = "0" ]; then
  echo "PASS | CON-12 ninguna sesion A (la que llega primero) fallo"
else
  echo "FAIL | CON-12 $con_error_a sesion(es) A terminaron con error"
  { grep -H 'ERROR' "$dir"/*.a || true; } | sed 's/^/       /'
  fallos=$((fallos + 1))
fi

[ "$fallos" -eq 0 ]

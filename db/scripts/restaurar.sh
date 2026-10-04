#!/usr/bin/env bash
# =============================================================================
# Restauracion de un respaldo generado por respaldar.sh (make restore).
#
#   CONFIRMAR=<nombre de la base> bash db/scripts/restaurar.sh backups/<archivo>.dump
#
# ES DESTRUCTIVA: elimina la base actual y la recrea desde el respaldo. Por eso
# exige CONFIRMAR con el nombre exacto de la base. Sirve tanto sobre un cluster
# recien creado (tras perder el volumen) como sobre uno en uso.
#
# Pasos:
#   1. Verifica la suma sha256 del respaldo.
#   2. Si faltan los roles (cluster nuevo), los crea desde <archivo>.globales.sql.
#   3. Fija la clave de app_backend_user desde .env (el respaldo no trae claves).
#   4. Cierra las conexiones, elimina la base y la restaura con
#      pg_restore --create (recrea tambien los privilegios de la base).
#   5. VACUUM (ANALYZE): una base restaurada no tiene estadisticas.
#   6. Ejecuta fn_anonimizar_vencidos(): un respaldo antiguo puede traer de
#      vuelta titulares cuyo bloqueo ya vencio.
#
# Lo que NO puede hacer: reaplicar las supresiones solicitadas despues de la
# fecha del respaldo (docs/operacion.md seccion 3.4).
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

dump="${1:-}"
if [ -z "$dump" ] || [ ! -f "$dump" ]; then
  echo "uso: CONFIRMAR=$POSTGRES_DB bash db/scripts/restaurar.sh backups/<archivo>.dump" >&2
  exit 1
fi
if [ "${CONFIRMAR:-}" != "$POSTGRES_DB" ]; then
  echo "restaurar: esta operacion ELIMINA la base '$POSTGRES_DB' y la reemplaza por el respaldo." >&2
  echo "restaurar: para continuar, repetir con CONFIRMAR=$POSTGRES_DB" >&2
  exit 1
fi
globales="${dump%.dump}.globales.sql"
suma="${dump%.dump}.sha256"
inicio=$SECONDS

# 1. Integridad del archivo.
if [ -f "$suma" ]; then
  ( cd "$(dirname "$dump")" && sha256sum --check --quiet "$(basename "$suma")" )
  echo "restaurar: suma sha256 correcta"
else
  echo "restaurar: AVISO - no hay archivo .sha256; no se verifica la integridad"
fi

# El respaldo debe ser de esta base: pg_restore --create usa el nombre guardado.
origen="$(en_contenedor pg_restore --list < "$dump" | sed -n 's/^; *dbname: //p' | tr -d '\r')"
if [ "$origen" != "$POSTGRES_DB" ]; then
  echo "restaurar: el respaldo es de la base '$origen', no de '$POSTGRES_DB'" >&2
  exit 1
fi

psql_mantenimiento() { psql_super -d postgres "$@"; }

# 2. Roles: solo si no existen (cluster nuevo). Se omite la creacion del
#    superusuario, que ya existe en cualquier cluster.
if [ "$(psql_mantenimiento -At -c "SELECT count(*) FROM pg_roles WHERE rolname = 'app_owner'")" = "0" ]; then
  if [ ! -f "$globales" ]; then
    echo "restaurar: faltan los roles y no existe $globales" >&2
    exit 1
  fi
  grep -vx "CREATE ROLE ${POSTGRES_USER};" "$globales" | psql_mantenimiento >/dev/null
  echo "restaurar: roles creados desde $(basename "$globales")"
else
  echo "restaurar: los roles ya existen; no se aplica el archivo de roles"
fi

# 3. Clave del rol de conexion, desde .env.
psql_mantenimiento >/dev/null <<'SQL'
ALTER ROLE app_backend_user PASSWORD :'clave_backend';
SQL

# 4. Base: fuera conexiones, eliminar y restaurar.
psql_mantenimiento -c "DROP DATABASE IF EXISTS \"$POSTGRES_DB\" WITH (FORCE)"
en_contenedor pg_restore --create --exit-on-error -d postgres < "$dump"
echo "restaurar: base '$POSTGRES_DB' restaurada desde $(basename "$dump")"

# 5. Estadisticas del planificador y mapa de visibilidad.
psql_super -c "VACUUM (ANALYZE)"

# 6. Bloqueos de titular que vencieron entre el respaldo y hoy.
anonimizados="$(psql_super -At -c "SET ROLE app_owner" -c "SELECT fn_anonimizar_vencidos()")"
echo "restaurar: titulares con bloqueo vencido anonimizados tras restaurar: $anonimizados"

# El ALTER ROLE ... PASSWORD del paso 3 es una sentencia de utilidad con la clave literal.
vaciar_estadisticas_sentencias

echo "restaurar: terminado en $((SECONDS - inicio)) s"
echo "restaurar: PENDIENTE MANUAL - reaplicar las supresiones de titulares solicitadas despues de la fecha del respaldo"

#!/usr/bin/env bash
# =============================================================================
# Proceso periodico de privacidad: anonimiza los titulares cuyo bloqueo por
# retencion ya vencio (fn_anonimizar_vencidos). Pensado para ejecutarse una vez
# al dia desde el programador de tareas del sistema (docs/operacion.md
# seccion 7): la imagen postgres:16 no trae pg_cron.
#
# La funcion solo tiene EXECUTE para app_owner, que no tiene LOGIN: el script
# se conecta como superusuario y asume ese rol con SET ROLE.
#
# Es idempotente (una segunda ejecucion no encuentra nada) y dos ejecuciones
# simultaneas no se bloquean (SKIP LOCKED). Termina con codigo distinto de
# cero si despues de ejecutarla queda algun bloqueo vencido sin procesar.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

procesados="$(psql_super -At -c "SET ROLE app_owner" -c "SELECT fn_anonimizar_vencidos()")"
pendientes="$(psql_super -At -c "SELECT count(*) FROM titular WHERE estado_tratamiento = 'bloqueado' AND bloqueado_hasta <= current_date")"
proximo="$(psql_super -At -c "SELECT coalesce(min(bloqueado_hasta)::text, 'ninguno') FROM titular WHERE estado_tratamiento = 'bloqueado'")"

echo "anonimizar: $(date -u +%Y-%m-%dT%H:%MZ) titulares anonimizados: $procesados; vencidos pendientes: $pendientes; proximo vencimiento: $proximo"
[ "$pendientes" = "0" ]

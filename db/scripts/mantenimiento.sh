#!/usr/bin/env bash
# =============================================================================
# Mantenimiento manual: VACUUM (ANALYZE) de toda la base.
#
# El autovacuum esta activo y es quien hace este trabajo en regimen normal. Este
# script es para despues de una carga masiva, una restauracion o una purga, y
# para dejar constancia del antes y el despues. No bloquea lecturas ni
# escrituras (no es VACUUM FULL).
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

resumen() {
  psql_super -At -F ' ' -c "SELECT 'tablas: ' || count(*), '| filas muertas: ' || coalesce(sum(n_dead_tup), 0), '| sin analyze: ' || count(*) FILTER (WHERE last_analyze IS NULL AND last_autoanalyze IS NULL), '| base: ' || pg_size_pretty(pg_database_size(current_database())) FROM pg_stat_user_tables WHERE schemaname = 'public'"
}

echo "mantenimiento: antes   -> $(resumen)"
inicio=$SECONDS
psql_super -c "VACUUM (ANALYZE)"
# Las estadisticas acumuladas se publican con un pequeno retraso.
psql_super -c "SELECT pg_stat_force_next_flush(), pg_sleep(0.5)" >/dev/null
echo "mantenimiento: despues -> $(resumen)"
echo "mantenimiento: VACUUM (ANALYZE) en $((SECONDS - inicio)) s"

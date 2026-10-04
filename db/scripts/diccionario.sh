#!/usr/bin/env bash
# Genera docs/modelo/05_diccionario_datos.md desde el catalogo del motor.
# El diccionario nunca se edita a mano: se cambia el COMMENT ON y se regenera.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

salida="docs/modelo/05_diccionario_datos.md"
{
  echo "# 5. Diccionario de datos"
  echo
  echo "> **Archivo generado.** No editar a mano: se obtiene del catalogo de PostgreSQL"
  echo "> (\`COMMENT ON\` de \`db/migrations/V004__comentarios.sql\`) con \`bash db/scripts/diccionario.sh\`."
  echo "> Asi el diccionario no puede desalinearse del esquema real."
  psql_super -f /db/scripts/diccionario.sql
} > "$salida"
echo "diccionario: $salida ($(wc -l < "$salida") lineas)"

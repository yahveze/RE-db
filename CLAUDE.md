# Repuestos Exactos — base de datos PostgreSQL 16

Proyecto universitario: BD multi-taller para diagnóstico OBD-II y matriz comparativa de repuestos.
Responder siempre en **español**. Detalle y justificación de decisiones: `docs/decisiones.md`.

## Reglas de trabajo

- **Nada es válido hasta ejecutarlo** contra el PostgreSQL 16 del contenedor. Prohibido inventar salidas,
  costos, tiempos o filas: toda cifra sale de una ejecución real guardada en `docs/evidencia/`.
- **Nunca escribir secretos** en archivos versionados ni en evidencia. Las claves viven en `.env`
  (ignorado por Git) y llegan al SQL con `psql -v` como `:'clave_backend'` y `:'clave_demo'`.
  `.env.example` solo tiene placeholders.
- Ejecutar comandos solo dentro de esta carpeta y solo sobre el contenedor `repuestos_exactos_db`
  y el volumen `repuestos_exactos_pgdata`.
- Si una prueba falla, se corrige la migración, no se relaja la prueba.
- No reabrir las decisiones tomadas; los problemas se anotan en "Temas para conversar" de `docs/decisiones.md`.
- Commit local al final de cada fase. Puntos de parada: fases 0, 1, 2 y 7.
- Prohibido: `SERIAL`, `now()` en CHECK, CHECK con subconsulta, `SECURITY DEFINER` sin `SET search_path`,
  `SET` de sesión para el contexto del taller, pseudocódigo u omisiones ("...").

## Comandos

`make` no está instalado en este equipo Windows: usar los scripts (el `Makefile` solo delega en ellos).

| Make | Script | Qué hace |
|---|---|---|
| `make up` / `down` | `docker compose up -d --wait` / `down` | levanta / detiene |
| `make reset` | `bash db/scripts/reset.sh` | elimina el volumen y recrea una base vacía |
| `make migrate` | `bash db/scripts/migrate.sh` | aplica `db/migrations/V*.sql` en orden |
| `make seed` | `bash db/scripts/seed.sh` | carga `db/seeds/*.sql` como superusuario |
| `make test` | `bash db/tests/run_all.sh` | suite SQL; código ≠ 0 si hay algún FAIL |
| `make perf` | `bash db/perf/run.sh` | volumen + EXPLAIN (Fase 5) |
| `make psql` | `bash db/scripts/psql.sh [-c ... | -f /db/...]` | psql 16 del contenedor |
| `make all` | reset → migrate → seed → test | criterio de aceptación: código 0 |

Notas: se usa el `psql` **del contenedor** (el del host es v18). `db/` está montado en `/db` (solo lectura).
`psql -c` no interpola variables `:'x'`; usar `-f` o stdin.

## Orden de ejecución

`V000` roles y extensiones (superusuario) → `V001` tipos → `V002` catálogos → `V003` tablas multi-taller,
operativas, cotización y auditoría → `V004` comentarios → `V005` funciones y triggers → `V006` índices →
`V007` grants → `V008` RLS (`ENABLE` y `FORCE` solo aquí) → semillas (superusuario) → pruebas.

`V001`+ corren como superusuario con `SET ROLE app_owner` previo (dueño de los objetos = `app_owner`).
Las funciones `SECURITY DEFINER` pasan a `app_funciones`; para eso `app_owner` es miembro de
`app_funciones` (`INHERIT FALSE, SET TRUE`) y `app_funciones` tiene `CREATE` en `public`.

## Decisiones tomadas

1. Multi-taller por segregación lógica: `taller_id` obligatorio en toda tabla operativa; un taller nuevo es un `INSERT`.
2. Un usuario pertenece a un solo taller; email único global.
3. Estados de `sesion_diagnostico`: `pendiente`, `cotizado`, `completado`, `cancelado`. Transiciones:
   pendiente→cotizado, pendiente→cancelado, cotizado→completado, cotizado→cancelado. Validadas con trigger.
4. Perfiles `genuino`, `oem`, `generico`, siempre en ese orden.
5. Precios `BIGINT` en unidad mínima; moneda por taller, default `'CLP'`.
6. Precio maestro global `repuesto.precio_referencia`;
   `precio_venta = ROUND(precio_referencia * (1 + margen_pct / 100))`. Listas por taller: [AVANZADA].
7. Catálogos globales de solo lectura para talleres: `marca_vehiculo`, `modelo_vehiculo`, `dtc_catalogo`,
   `componente_repuesto`, `dtc_componente`, `repuesto`, `compatibilidad_repuesto`.
8. `modelo_vehiculo → marca_vehiculo` normalizado (evita dependencia transitiva en `vehiculo`).
9. Un `repuesto` pertenece a un `componente_repuesto`; DTC↔componente es N:M (`dtc_componente`);
   DTC↔repuesto es la **vista** `v_dtc_repuesto`.
10. `compatibilidad_repuesto(repuesto, modelo_vehiculo, anio_desde, anio_hasta)`. Por motor: [AVANZADA].
11. Cotizaciones: varias revisiones por sesión, una sola vigente (índice único parcial); abierta mientras
    `cerrada_en IS NULL`; el `total` se congela al cerrar; cerrada = inmutable.
12. Método de ingreso `obd_bluetooth` | `manual`; `dispositivo_id` obligatorio si y solo si es `obd_bluetooth`.
13. Titular y vehículo pertenecen a un taller. Vehículo→titular: FK simple y anulable.
14. El auditor ve solo su taller.
15. Patente obligatoria salvo vehículo anonimizado (`patente` y `vin` pasan a `NULL`).
16. Sin RUT; identificador determinista = HMAC-SHA-256 calculado en el backend.
17. Autenticación de prototipo con `crypt()` y `gen_salt('bf', 10)` en la BD.
18. Todo tiempo es `TIMESTAMPTZ`.

Decisiones abiertas resueltas (ver `docs/decisiones.md` §2): durabilidad en km; `margen_pct NUMERIC(5,2)`
0–200, default 30; `retencion_anios` default 6 (validar legalmente); sesión siempre con vehículo; solo
cotizaciones (sin documentos tributarios); `ON DELETE RESTRICT` + estado de baja.

## Convenciones

- `snake_case`, español sin mezclar idiomas, tablas en singular.
- PK `id BIGINT GENERATED ALWAYS AS IDENTITY`. Tablas de enlace N:M: PK compuesta natural, sin `id`.
- Entidades expuestas por la API: `id_publico UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE`.
  La API nunca expone ids secuenciales.
- FK `<entidad>_id`. Timestamps `creado_en`, `actualizado_en`; `eliminado_en` solo con borrado lógico;
  inicio de sesión de diagnóstico: `iniciada_en`.
- Prefijos: `pk_`, `fk_`, `uq_`, `ck_`, `ix_`, `trg_`, `fn_`, `v_`, `pol_<tabla>_<rol>_<operacion>`; enums `tipo_`.
- Variables de sesión: `app.taller_id`, `app.usuario_id`, `app.ip_origen`, `app.request_id`.
- Los campos JSON de la API coinciden con los nombres de columna.
- Enums: `tipo_rol_usuario` (admin, mecanico, auditor), `tipo_estado_atencion`, `tipo_severidad`
  (baja, media, alta, critica), `tipo_perfil_repuesto`, `tipo_nivel_riesgo` (bajo, medio, alto),
  `tipo_metodo_ingreso`, `tipo_resultado_auditoria` (exito, fallo, denegado), `tipo_operacion_auditoria`,
  `tipo_estado_dispositivo` (activo, inactivo, baja), `tipo_tema_visual` (claro, oscuro),
  `tipo_estado_tratamiento` (activo, bloqueado, anonimizado), `tipo_finalidad_tratamiento`,
  `tipo_solicitud_derecho`, `tipo_estado_solicitud`.
- `COMMENT ON TABLE/COLUMN` para todas las tablas.

## Seguridad (resumen)

- Roles: `app_owner` (dueño, no se usa en ejecución), `app_funciones` (NOLOGIN, BYPASSRLS, dueño solo de
  funciones definidoras), grupos `taller_admin`, `taller_mecanico`, `taller_auditor`, y `app_backend_user`
  (LOGIN, sin privilegios de tabla, miembro de los grupos con `INHERIT FALSE, SET TRUE`).
- Patrón de petición: `BEGIN; SET LOCAL ROLE <grupo>; set_config('app.taller_id', $1, true); ...; COMMIT;`
- RLS con `FORCE`; contexto `(SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)`.
- Dentro de `SECURITY DEFINER`, `current_user` es `app_funciones`: el rol real se lee con `current_setting('role')`.
- Aislamiento: `UNIQUE (id, taller_id)` en tablas padre y FK compuestas `(padre_id, taller_id)` en las hijas.


## Notas de implementación (Fase 2)

- `migrate.sh` corre cada archivo con `--single-transaction`; acepta un prefijo (`migrate.sh V005`).
- En `V005` los `COMMENT ON FUNCTION` van antes de `ALTER FUNCTION ... OWNER TO app_funciones`
  (COMMENT exige ser el dueño). Los `GRANT EXECUTE` de esas funciones se hacen en `V007` con
  `SET ROLE app_funciones`.
- Índices únicos parciales (reglas de integridad) en `V003`; índices de rendimiento en `V006`.
- El trigger del detalle bloquea la cabecera con `FOR SHARE` (no `FOR KEY SHARE`): cubre también el
  cierre por `UPDATE` directo.
- Toda cotización nace borrador (trigger); `total` y `cerrada_en` los fija el trigger al cerrar. Las
  semillas deben recorrer el flujo real, no insertar estados finales.
- Errores de negocio con `SQLSTATE` propio `RE001`–`RE012` (tabla en `docs/seguridad.md` §11).
- Políticas `pol_<tabla>_miembros_<op>` cuando aplican a los tres grupos.
- Tras cambiar un `COMMENT ON`: `bash db/scripts/diccionario.sh`. Tras cambiar el esquema:
  `bash db/scripts/evidencia_esquema.sh`. Prueba de humo: `bash db/scripts/psql.sh -f /db/tests/humo/fase2_humo.sql`.
- `psql.sh` pasa `-q` y `ON_ERROR_STOP=1`; un script con errores esperados debe poner
  `\set ON_ERROR_STOP off` y `\set ON_ERROR_ROLLBACK on`.
- En Git Bash no pasar rutas de Windows (`$TEMP`) a `awk -v`: las barras invertidas se interpretan como
  escapes. Usar heredoc o la herramienta de edición.

## Estado

- Fases 0, 1 y 2 completas. Esquema en `db/migrations/` (V000–V008), verificado desde cero.
- Documentos: `docs/decisiones.md`, `docs/modelo/` (01–05), `docs/seguridad.md`, `docs/privacidad.md`.
- Siguiente: Fase 3 (semillas, consultas del frontend con su contrato, transacciones).

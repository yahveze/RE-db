# 3. Modelo lógico

Especificación relacional que implementan las migraciones `V001`–`V003`. Los tipos son de PostgreSQL 16.
Este documento fue el **borrador del diccionario de datos**: el definitivo es `05_diccionario_datos.md`, que
se genera desde el catálogo del motor (`COMMENT ON` de `V004`) para que no pueda desalinearse del esquema real.

## 3.1 Convenciones aplicadas

- `id BIGINT GENERATED ALWAYS AS IDENTITY` como PK, salvo tablas de enlace (PK compuesta natural) y
  tablas 1:1 (la PK es la FK al padre).
- `id_publico UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE` en lo que la API expone.
- Todo texto obligatorio lleva `CHECK (btrim(col) <> '')`. Todo tiempo es `TIMESTAMPTZ`.
- **Nombres de FK abreviados**, fijados por el enunciado y usados en todo el proyecto:
  `dtc_id` → `dtc_catalogo`, `componente_id` → `componente_repuesto`, `sesion_id` → `sesion_diagnostico`,
  `dispositivo_id` → `dispositivo_diagnostico`. El resto usa el nombre completo de la entidad.
- **FK compuesta** significa `(x_id, taller_id) → padre (id, taller_id)`.
- `ON DELETE`: `RESTRICT` salvo donde se indica.

## 3.2 Tipos enumerados (`V001`)

| Tipo | Valores | Origen de los valores |
|---|---|---|
| `tipo_rol_usuario` | admin, mecanico, auditor | enunciado |
| `tipo_estado_atencion` | pendiente, cotizado, completado, cancelado | decisión 3 |
| `tipo_severidad` | baja, media, alta, critica | enunciado |
| `tipo_perfil_repuesto` | genuino, oem, generico | decisión 4 |
| `tipo_nivel_riesgo` | bajo, medio, alto | enunciado |
| `tipo_metodo_ingreso` | obd_bluetooth, manual | decisión 12 |
| `tipo_resultado_auditoria` | exito, fallo, denegado | enunciado |
| `tipo_operacion_auditoria` | INSERT, UPDATE, DELETE, LOGIN, LOGIN_FALLIDO | sección 10 |
| `tipo_estado_dispositivo` | activo, inactivo, baja | enunciado |
| `tipo_tema_visual` | claro, oscuro | enunciado |
| `tipo_estado_tratamiento` | activo, bloqueado, anonimizado | enunciado |
| `tipo_solicitud_derecho` | acceso, rectificacion, supresion, oposicion, portabilidad, bloqueo | sección 9 |
| `tipo_finalidad_tratamiento` | prestacion_servicio, contacto_seguimiento, marketing | **propuesta** (el enunciado no los lista) |
| `tipo_estado_solicitud` | recibida, en_proceso, resuelta, rechazada | **propuesta** (el enunciado no los lista) |

El orden de declaración de `tipo_perfil_repuesto` coincide con el de presentación, pero las consultas
ordenan con `CASE` explícito (como pide el enunciado) para no depender del orden interno del enum.

**Por qué enum y no tabla de referencia:** son conjuntos cerrados que el código de la app conoce; un enum
ocupa 4 bytes, valida sin JOIN y agrega valores con `ALTER TYPE ... ADD VALUE`. Su costo: quitar o
renombrar un valor exige migración. Si los valores fueran datos administrables, serían tabla.

---

## 3.3 Multi-taller

### `taller`
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `id` | BIGINT identity | no | PK |
| `id_publico` | UUID | no | UNIQUE |
| `nombre` | TEXT | no | |
| `activo` | BOOLEAN | no | default `true`; baja lógica del taller |
| `creado_en`, `actualizado_en` | TIMESTAMPTZ | no | default `now()` |

### `taller_configuracion` (1:1 con `taller`)
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `taller_id` | BIGINT | no | **PK** y FK → `taller` |
| `moneda` | CHAR(3) | no | default `'CLP'`; CHECK `^[A-Z]{3}$` (código ISO 4217) |
| `tema` | `tipo_tema_visual` | no | default `'claro'` |
| `margen_pct` | NUMERIC(5,2) | no | default `30.00`; CHECK 0–200 |
| `retencion_anios` | SMALLINT | no | default `6`; CHECK 0–30. **Validar legalmente** |
| `actualizado_en` | TIMESTAMPTZ | no | |

Separada de `taller` no por normalización (comparten clave) sino por **privilegios y ritmo de cambio**:
el administrador modifica la configuración, pero no la identidad del taller.

### `usuario`
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `id` | BIGINT identity | no | PK |
| `id_publico` | UUID | no | UNIQUE |
| `taller_id` | BIGINT | no | FK → `taller` |
| `email` | TEXT | no | UNIQUE global; CHECK `email = lower(email)` y formato básico |
| `nombre` | TEXT | no | |
| `rol` | `tipo_rol_usuario` | no | |
| `activo` | BOOLEAN | no | default `true`; un usuario no se borra, se desactiva |
| `creado_en`, `actualizado_en` | TIMESTAMPTZ | no | |

Además `UNIQUE (id, taller_id)` (tabla padre de FK compuestas).

### `usuario_credencial` (1:1 con `usuario`)
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `usuario_id` | BIGINT | no | **PK** y FK → `usuario` **ON DELETE CASCADE** |
| `hash_contrasena` | TEXT | no | bcrypt (`$2a$10$…`); nunca sale de la BD |
| `intentos_fallidos` | INTEGER | no | default 0; CHECK `>= 0` |
| `bloqueado_hasta` | TIMESTAMPTZ | sí | bloqueo temporal por intentos |
| `ultimo_login_en` | TIMESTAMPTZ | sí | |
| `actualizado_en` | TIMESTAMPTZ | no | |

Sin `taller_id`, sin RLS y **sin privilegios para ningún rol de grupo**: solo la tocan funciones definidoras.
`CASCADE` porque una credencial no tiene sentido sin su usuario.

---

## 3.4 Privacidad

### `titular`
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `id` | BIGINT identity | no | PK |
| `id_publico` | UUID | no | UNIQUE |
| `taller_id` | BIGINT | no | FK → `taller` |
| `nombre` | TEXT | sí | obligatorio mientras no esté anonimizado |
| `telefono` | TEXT | sí | contacto opcional |
| `email` | TEXT | sí | contacto opcional |
| `identificador_hmac` | BYTEA | sí | HMAC-SHA-256 calculado en el backend; CHECK `octet_length = 32` |
| `estado_tratamiento` | `tipo_estado_tratamiento` | no | default `'activo'` |
| `bloqueado_hasta` | DATE | sí | fin de la retención |
| `anonimizado_en` | TIMESTAMPTZ | sí | |
| `creado_en`, `actualizado_en` | TIMESTAMPTZ | no | |

Restricciones: `UNIQUE (id, taller_id)`; único parcial `(taller_id, identificador_hmac) WHERE identificador_hmac IS NOT NULL`;
- `ck_titular_estado_bloqueado`: `(estado_tratamiento = 'bloqueado') = (bloqueado_hasta IS NOT NULL)`
- `ck_titular_estado_anonimizado`: `(estado_tratamiento = 'anonimizado') = (anonimizado_en IS NOT NULL)`
- `ck_titular_anonimizado_sin_datos`: si está anonimizado, `nombre`, `telefono`, `email` e `identificador_hmac` son `NULL`; si no, `nombre` es obligatorio.

### `consentimiento_titular`
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `id` | BIGINT identity | no | PK |
| `taller_id` | BIGINT | no | FK → `taller` |
| `titular_id` | BIGINT | no | FK compuesta → `titular` |
| `finalidad` | `tipo_finalidad_tratamiento` | no | |
| `version_terminos` | TEXT | no | qué texto aceptó |
| `canal` | TEXT | no | CHECK en (`presencial`, `app`, `web`, `telefono`) — **propuesta** |
| `otorgado_en` | TIMESTAMPTZ | no | |
| `revocado_en` | TIMESTAMPTZ | sí | CHECK `>= otorgado_en` |

Único parcial `(titular_id, finalidad) WHERE revocado_en IS NULL`. Revocar no borra la fila: queda la
prueba de que existió consentimiento entre ambas fechas.

### `solicitud_derecho_titular`
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `id` | BIGINT identity | no | PK |
| `id_publico` | UUID | no | UNIQUE |
| `taller_id` | BIGINT | no | FK → `taller` |
| `titular_id` | BIGINT | no | FK compuesta → `titular` |
| `tipo` | `tipo_solicitud_derecho` | no | |
| `estado` | `tipo_estado_solicitud` | no | default `'recibida'` |
| `usuario_responsable_id` | BIGINT | sí | FK compuesta → `usuario` |
| `recibida_en` | TIMESTAMPTZ | no | default `now()` |
| `resuelta_en` | TIMESTAMPTZ | sí | CHECK: no nula ⇔ estado en (`resuelta`, `rechazada`) |
| `actualizado_en` | TIMESTAMPTZ | no | |

Sin campo de texto libre: una observación podría contener datos personales y terminaría en la auditoría.

---

## 3.5 Catálogos globales (sin `taller_id`, sin RLS)

### `marca_vehiculo`
`id` PK · `id_publico` UNIQUE · `nombre` TEXT NOT NULL UNIQUE · `creado_en`.

### `modelo_vehiculo`
`id` PK · `id_publico` UNIQUE · `marca_vehiculo_id` BIGINT NOT NULL FK → `marca_vehiculo` · `nombre` TEXT NOT NULL · `creado_en` · `UNIQUE (marca_vehiculo_id, nombre)`.

### `dtc_catalogo`
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `id` | BIGINT identity | no | PK |
| `codigo` | TEXT | no | UNIQUE; CHECK `^[PCBU][0-3][0-9A-F]{3}$` |
| `descripcion` | TEXT | no | |
| `severidad_sugerida` | `tipo_severidad` | no | valor inicial propuesto para `falla_sesion.severidad` |
| `creado_en` | TIMESTAMPTZ | no | |

Sin `id_publico`: la API lo identifica por `codigo`, que ya es público y estable.

### `componente_repuesto`
`id` PK · `id_publico` UNIQUE · `nombre` TEXT NOT NULL UNIQUE · `descripcion` TEXT · `creado_en`.

### `dtc_componente` (N:M)
`dtc_id` FK → `dtc_catalogo` · `componente_id` FK → `componente_repuesto` · **PK `(dtc_id, componente_id)`**.

### `repuesto`
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `id` | BIGINT identity | no | PK |
| `id_publico` | UUID | no | UNIQUE |
| `componente_id` | BIGINT | no | FK → `componente_repuesto` |
| `perfil` | `tipo_perfil_repuesto` | no | |
| `marca` | TEXT | no | texto, no catálogo (ver normalización §4.6) |
| `nombre` | TEXT | no | |
| `codigo_fabricante` | TEXT | no | número de parte |
| `durabilidad_estimada_km` | INTEGER | no | CHECK `> 0` |
| `riesgo` | `tipo_nivel_riesgo` | no | |
| `precio_referencia` | BIGINT | no | CHECK `>= 0`; costo maestro en unidad mínima |
| `disponible` | BOOLEAN | no | default `true`; un repuesto no se borra, se marca no disponible |
| `creado_en`, `actualizado_en` | TIMESTAMPTZ | no | |

`UNIQUE (componente_id, marca, codigo_fabricante)`.

### `compatibilidad_repuesto` (N:M con atributos)
`repuesto_id` FK → `repuesto` · `modelo_vehiculo_id` FK → `modelo_vehiculo` · `anio_desde` SMALLINT ·
`anio_hasta` SMALLINT · **PK `(repuesto_id, modelo_vehiculo_id, anio_desde)`** ·
CHECK `anio_desde <= anio_hasta` y ambos entre 1981 y 2100.

`anio_desde` forma parte de la PK para admitir rangos disjuntos del mismo par (2005–2010 y 2016–2020).
Impedir rangos **solapados** exigiría una restricción `EXCLUDE` con `btree_gist` → **[AVANZADA]**; la
consulta de la matriz usa `EXISTS`, así que un solapamiento no duplica filas.

### Vista `v_dtc_repuesto`
```sql
SELECT dc.dtc_id, dc.componente_id, r.id AS repuesto_id
FROM   dtc_componente dc
JOIN   repuesto r ON r.componente_id = dc.componente_id;
```

---

## 3.6 Operación

### `vehiculo`
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `id` | BIGINT identity | no | PK |
| `id_publico` | UUID | no | UNIQUE |
| `taller_id` | BIGINT | no | FK → `taller` |
| `titular_id` | BIGINT | sí | FK compuesta → `titular` (MATCH SIMPLE) |
| `modelo_vehiculo_id` | BIGINT | no | FK → `modelo_vehiculo` |
| `anio` | SMALLINT | no | CHECK 1981–2100 |
| `motor` | TEXT | sí | por ejemplo `2.4 Diesel`; obligatorio si no hay VIN |
| `vin` | TEXT | sí | CHECK `^[A-HJ-NPR-Z0-9]{17}$` |
| `patente` | TEXT | sí | CHECK `^[A-Z]{2}[0-9]{4}$` o `^[BCDFGHJKLPRSTVWXYZ]{4}[0-9]{2}$` |
| `anonimizado_en` | TIMESTAMPTZ | sí | |
| `creado_en`, `actualizado_en` | TIMESTAMPTZ | no | |

Restricciones: `UNIQUE (id, taller_id)`; únicos parciales `(taller_id, vin) WHERE vin IS NOT NULL` y
`(taller_id, patente) WHERE patente IS NOT NULL`;
- `ck_vehiculo_patente_obligatoria`: `anonimizado_en IS NOT NULL OR patente IS NOT NULL`
- `ck_vehiculo_anonimizado_sin_identificadores`: `anonimizado_en IS NULL OR (patente IS NULL AND vin IS NULL)`
- `ck_vehiculo_identificacion_tecnica`: `anonimizado_en IS NOT NULL OR vin IS NOT NULL OR motor IS NOT NULL`

Los regex rechazan minúsculas: la normalización a mayúsculas es responsabilidad de quien inserta (la API),
y el CHECK garantiza que nunca entre un valor sin normalizar.

### `dispositivo_diagnostico`
`id` PK · `id_publico` UNIQUE · `taller_id` FK → `taller` · `mac` MACADDR NOT NULL ·
`estado` `tipo_estado_dispositivo` NOT NULL default `'activo'` · `fabricante` TEXT · `modelo` TEXT ·
`firmware` TEXT · `creado_en`, `actualizado_en` · `UNIQUE (taller_id, mac)` · `UNIQUE (id, taller_id)`.

### `sesion_diagnostico`
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `id` | BIGINT identity | no | PK |
| `id_publico` | UUID | no | UNIQUE |
| `taller_id` | BIGINT | no | FK → `taller` |
| `vehiculo_id` | BIGINT | no | FK compuesta → `vehiculo` |
| `usuario_id` | BIGINT | no | FK compuesta → `usuario` (mecánico que atiende) |
| `dispositivo_id` | BIGINT | sí | FK compuesta → `dispositivo_diagnostico` (MATCH SIMPLE) |
| `metodo_ingreso` | `tipo_metodo_ingreso` | no | |
| `kilometraje` | INTEGER | no | CHECK `>= 0` |
| `estado` | `tipo_estado_atencion` | no | default `'pendiente'` |
| `iniciada_en` | TIMESTAMPTZ | no | default `now()`; hace las veces de `creado_en` |
| `cotizada_en`, `completada_en`, `cancelada_en` | TIMESTAMPTZ | sí | los fija el trigger de estados |
| `version` | INTEGER | no | default 1; control optimista, la incrementa un trigger |
| `actualizado_en` | TIMESTAMPTZ | no | |

Restricciones: `UNIQUE (id, taller_id)`;
- `ck_sesion_dispositivo_segun_metodo`: `(metodo_ingreso = 'obd_bluetooth') = (dispositivo_id IS NOT NULL)`
- `ck_sesion_estado_timestamps`:

| estado | `cotizada_en` | `completada_en` | `cancelada_en` |
|---|---|---|---|
| pendiente | nulo | nulo | nulo |
| cotizado | **no nulo** | nulo | nulo |
| completado | **no nulo** | **no nulo** | nulo |
| cancelado | cualquiera | nulo | **no nulo** |

(`cancelado` admite `cotizada_en` porque se puede cancelar desde `cotizado`.)

### `falla_sesion` (N:M sesión ↔ DTC)
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `sesion_id` | BIGINT | no | FK compuesta → `sesion_diagnostico` |
| `dtc_id` | BIGINT | no | FK → `dtc_catalogo` |
| `taller_id` | BIGINT | no | FK → `taller`; desnormalización deliberada |
| `severidad` | `tipo_severidad` | no | la observada en esta sesión |
| `freeze_frame` | JSONB | sí | CHECK `jsonb_typeof = 'object'` |
| `creado_en` | TIMESTAMPTZ | no | |

**PK `(sesion_id, dtc_id)`**.

### `cotizacion`
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `id` | BIGINT identity | no | PK |
| `id_publico` | UUID | no | UNIQUE |
| `taller_id` | BIGINT | no | FK → `taller` |
| `sesion_id` | BIGINT | no | FK compuesta → `sesion_diagnostico` |
| `numero_revision` | INTEGER | no | CHECK `> 0` |
| `vigente` | BOOLEAN | no | default `false` |
| `cerrada_en` | TIMESTAMPTZ | sí | nulo = abierta |
| `total` | BIGINT | sí | CHECK `>= 0`; se congela al cerrar |
| `moneda` | CHAR(3) | no | copiada de la configuración al crear |
| `clave_idempotencia` | UUID | no | la genera el cliente |
| `version` | INTEGER | no | default 1; control optimista |
| `creado_en`, `actualizado_en` | TIMESTAMPTZ | no | |

Restricciones: `UNIQUE (id, taller_id)`, `UNIQUE (sesion_id, numero_revision)`,
`UNIQUE (taller_id, clave_idempotencia)`; únicos parciales `(sesion_id) WHERE vigente` y
`(sesion_id) WHERE cerrada_en IS NULL`;
- `ck_cotizacion_total_al_cerrar`: `(cerrada_en IS NULL) = (total IS NULL)`
- `ck_cotizacion_vigente_cerrada`: `NOT vigente OR cerrada_en IS NOT NULL`

### `cotizacion_detalle` (N:M cotización ↔ repuesto, con *snapshot*)
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `cotizacion_id` | BIGINT | no | FK compuesta → `cotizacion` **ON DELETE CASCADE** |
| `repuesto_id` | BIGINT | no | FK → `repuesto` |
| `taller_id` | BIGINT | no | FK → `taller`; desnormalización deliberada |
| `cantidad` | INTEGER | no | CHECK `> 0` |
| `nombre_snapshot` | TEXT | no | nombre del repuesto al cotizar |
| `marca_snapshot` | TEXT | no | |
| `perfil_snapshot` | `tipo_perfil_repuesto` | no | |
| `precio_referencia_snapshot` | BIGINT | no | CHECK `>= 0` |
| `margen_pct_snapshot` | NUMERIC(5,2) | no | CHECK 0–200 |
| `precio_unitario` | BIGINT | no | CHECK `= ROUND(precio_referencia_snapshot * (1 + margen_pct_snapshot / 100))` |
| `creado_en` | TIMESTAMPTZ | no | |

**PK `(cotizacion_id, repuesto_id)`**: un repuesto aparece una vez por cotización y la repetición se
expresa con `cantidad`. Las columnas `*_snapshot` y `precio_unitario` las llena un trigger; el cliente
solo envía `repuesto_id` y `cantidad`. `total = SUM(cantidad * precio_unitario)`.

---

## 3.7 Seguridad

### `auditoria_operacion` (sin FK, *append-only*)
| Columna | Tipo | Nulo | Notas |
|---|---|---|---|
| `id` | BIGINT identity | no | PK |
| `ocurrido_en` | TIMESTAMPTZ | no | default `clock_timestamp()` |
| `taller_id` | BIGINT | sí | valor, no FK; nulo en logins de emails inexistentes y en semillas |
| `usuario_id` | BIGINT | sí | valor, no FK |
| `rol` | TEXT | no | `current_setting('role')` o `session_user` |
| `operacion` | `tipo_operacion_auditoria` | no | |
| `tabla` | TEXT | sí | nulo en LOGIN |
| `registro_id` | BIGINT | sí | nulo en tablas de PK compuesta (la clave va en los JSON) |
| `datos_anteriores` | JSONB | sí | sin columnas sensibles |
| `datos_nuevos` | JSONB | sí | sin columnas sensibles |
| `ip_origen` | INET | sí | |
| `resultado` | `tipo_resultado_auditoria` | no | |
| `request_id` | TEXT | sí | correlación con los logs de la API |

`clock_timestamp()` y no `now()`: dentro de una transacción `now()` es constante y varias operaciones
quedarían con la misma hora.

---

## 3.8 Estrategia de borrado

| FK | `ON DELETE` | Justificación |
|---|---|---|
| `usuario_credencial.usuario_id` | **CASCADE** | dependiente sin sentido propio |
| `cotizacion_detalle → cotizacion` | **CASCADE** | el detalle es parte de la cotización |
| `taller_configuracion.taller_id` | RESTRICT | un taller no se borra; se desactiva |
| toda FK hacia `taller` | RESTRICT | borrar un taller arrastraría historiales |
| `vehiculo → titular` | RESTRICT | el titular se anonimiza, no se borra (decisión abierta g) |
| `sesion → vehiculo / usuario / dispositivo` | RESTRICT | el historial debe conservar sus referencias |
| `falla_sesion → sesion` | RESTRICT | una sesión no se borra: se cancela |
| `cotizacion → sesion` | RESTRICT | trazabilidad financiera |
| toda FK hacia un catálogo | RESTRICT | un catálogo en uso no puede desaparecer; `repuesto.disponible = false` |
| `consentimiento / solicitud → titular` | RESTRICT | son la evidencia de cumplimiento |

En la práctica ningún rol de ejecución tiene `DELETE` sobre estas tablas (salvo el detalle de cotizaciones
abiertas), así que `RESTRICT` es la segunda barrera, no la primera.

## 3.9 FK compuestas con columna anulable (`MATCH SIMPLE`)

`vehiculo (titular_id, taller_id)`, `sesion_diagnostico (dispositivo_id, taller_id)` y
`solicitud_derecho_titular (usuario_responsable_id, taller_id)` tienen una columna anulable. Con el modo
por defecto `MATCH SIMPLE`, **si alguna columna de la FK es `NULL` la restricción no se evalúa**: un
vehículo sin titular es válido aunque `taller_id` tenga valor. Cuando la columna deja de ser nula, el par
completo debe existir en el padre, y por eso no puede apuntar a otro taller. `MATCH FULL` no sirve aquí:
exigiría que `taller_id` también fuera nulo.

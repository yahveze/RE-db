# Privacidad y protección de datos personales

> **Advertencia.** Este documento describe un **diseño técnico**, no es asesoría legal. La Ley N° 21.719
> (que modifica la Ley N° 19.628) se trata como **supuesto de diseño a validar con asesoría legal**. Según
> la información de que dispongo, se publicó en diciembre de 2024 y entra en vigencia el 1 de diciembre
> de 2026: **verifica la fecha y el texto vigente**. Todo lo marcado **validar** depende de una
> interpretación jurídica que este proyecto no puede resolver.

El comportamiento descrito está comprobado en `docs/evidencia/fase2_humo.txt` (referencias `[humo §n]`).

## 1. Supuestos

| # | Supuesto | Estado |
|---|---|---|
| 1 | El titular del vehículo es una persona natural cuyos datos trata el taller | diseño |
| 2 | Patente y VIN son **datos personales indirectos** (permiten llegar a una persona) | supuesto prudente, **validar** |
| 3 | Cada taller es responsable de los datos que recoge | decisión 13 |
| 4 | El sistema solo emite cotizaciones, no documentos tributarios | decisión abierta f, **validar** |
| 5 | Plazo de conservación: 6 años desde la última atención | parametrizable, **validar** |
| 6 | Los usuarios del sistema son trabajadores; su nombre y email también son datos personales | diseño |

## 2. Inventario de datos personales

| Dato | Columna | Tipo | Quién lo ve | En auditoría |
|---|---|---|---|---|
| Nombre del titular | `titular.nombre` | identificación directa | admin, mecánico (si `activo`) | **excluido** |
| Teléfono | `titular.telefono` | contacto | admin, mecánico (si `activo`) | **excluido** |
| Email del titular | `titular.email` | contacto | admin, mecánico (si `activo`) | **excluido** |
| Identificador (HMAC) | `titular.identificador_hmac` | seudónimo | admin, mecánico (si `activo`) | **excluido** |
| Patente | `vehiculo.patente` | indirecto | admin, mecánico (si visible), auditor | **excluido** |
| VIN | `vehiculo.vin` | indirecto | admin, mecánico (si visible), auditor | **excluido** |
| Datos del escáner | `falla_sesion.freeze_frame` | potencialmente indirecto | los tres roles | **excluido** |
| Nombre del usuario | `usuario.nombre` | identificación directa | los tres roles | **excluido** |
| Email del usuario | `usuario.email` | identificación directa | admin, auditor | **excluido** |
| IP de origen | `auditoria_operacion.ip_origen` | indirecto (del trabajador) | admin, auditor | es la auditoría |

**No se almacena:** RUT, dirección, fecha de nacimiento, datos de pago ni datos sensibles.

## 3. Minimización

- `titular` tiene solo lo necesario para contactar al cliente: nombre obligatorio; teléfono, email e
  identificador opcionales.
- **Sin RUT.** Si el taller necesita reconocer a un cliente que vuelve, el backend calcula un HMAC del
  identificador y guarda solo ese valor (sección 4).
- `solicitud_derecho_titular` no tiene campo de observaciones: un texto libre terminaría conteniendo
  datos personales fuera de control.
- El titular **no es usuario del sistema**: no tiene credenciales ni acceso.

## 4. Identificador determinista: por qué HMAC y no SHA-256

**El problema.** Guardar `SHA-256(RUT)` parece anonimizar, pero no lo hace. Un hash protege un valor solo
si hay demasiados valores posibles para probarlos todos, y un RUT tiene **baja entropía**: son unas pocas
decenas de millones de números. Cualquiera con la tabla calcula el SHA-256 de todos los RUT posibles en
segundos y revierte cada hash por comparación. No hace falta "romper" SHA-256: basta enumerar.

**La solución.** `HMAC-SHA-256(secreto, RUT)`. El resultado depende de un secreto que el atacante no
tiene, así que enumerar los RUT no sirve: sin la clave no puede calcular ningún valor para comparar.

| Requisito | Cómo se cumple |
|---|---|
| El secreto **nunca** llega a la base | lo calcula el backend; la base solo recibe 32 bytes |
| Largo fijo | `CHECK (octet_length(identificador_hmac) = 32)` |
| Detectar al mismo titular | índice único parcial `(taller_id, identificador_hmac)` |
| No correlacionar entre talleres | **[RECOMENDADA para el backend]** derivar una clave por taller, o incluir el `taller_id` en el mensaje |

Si el secreto estuviera en la base (por ejemplo, calculando el HMAC con `pgcrypto`), quien robe la base
se llevaría hash y clave juntos, y volveríamos al caso del SHA-256 simple.

**Rotación de la clave.** Como el RUT no se guarda, no se puede recalcular el HMAC de los titulares
existentes. Procedimiento:

1. Agregar una columna `identificador_hmac_version SMALLINT` (**[AVANZADA]**, no implementada).
2. El backend conserva la clave anterior solo para **verificar**; los registros nuevos usan la nueva.
3. Cuando un titular vuelve y presenta su identificador, el backend lo encuentra con la clave antigua y
   reescribe el valor con la nueva.
4. Vencido el plazo que se defina, los valores que sigan en la versión antigua se anulan y se destruye
   la clave antigua.

Si la clave se filtra: rotarla de inmediato y anular los valores de la versión comprometida.

## 5. Consentimiento y base de licitud

`consentimiento_titular` registra, por titular y finalidad: versión de los términos aceptados, canal,
`otorgado_en` y `revocado_en`.

- Revocar **no borra** la fila: fija `revocado_en`. Queda la prueba de que el consentimiento existió
  entre ambas fechas.
- A lo más un consentimiento activo por titular y finalidad (índice único parcial).
- Finalidades modeladas: `prestacion_servicio`, `contacto_seguimiento`, `marketing`.

**Aclaración importante (validar).** No todo tratamiento se apoya en el consentimiento. La atención del
vehículo que el propio cliente solicita puede fundarse en **otra base de licitud** (por ejemplo, la
ejecución de un contrato o el cumplimiento de una obligación legal). Por eso el modelo **no exige** un
consentimiento para crear una sesión de diagnóstico: exigirlo confundiría las bases y haría que revocar
el consentimiento pareciera invalidar un servicio ya prestado. El consentimiento sí es la base natural de
finalidades accesorias como `marketing`.

## 6. Derechos del titular

`solicitud_derecho_titular` deja constancia de cada solicitud: tipo, estado, fechas y usuario responsable.

| Derecho | Cómo se atiende | Implementado |
|---|---|---|
| Acceso | el administrador consulta los datos del titular y sus vehículos | consulta |
| Rectificación | `UPDATE` de nombre y contacto (administrador o mecánico) | privilegios |
| **Supresión** | `fn_solicitar_supresion_titular` | **función** |
| Oposición | revocar el consentimiento de la finalidad (`revocado_en`) | privilegios |
| Portabilidad | exportación desde la API | fuera de la base |
| Bloqueo | estado `bloqueado` | vía supresión con retención |

Los plazos legales de respuesta **no están modelados** (validar cuáles aplican); `recibida_en` y
`resuelta_en` permiten medirlos.

## 7. Auditoría frente a supresión

**El conflicto.** La auditoría es inmutable: nada se actualiza ni se borra. Si contuviera el nombre de un
titular, ese nombre no podría suprimirse nunca, y la supresión sería incompleta.

**La resolución.** La auditoría **nunca recibe** datos personales. El trigger excluye estas columnas de
`datos_anteriores` y `datos_nuevos`:

| Tabla | Columnas excluidas |
|---|---|
| `titular` | `nombre`, `telefono`, `email`, `identificador_hmac` |
| `vehiculo` | `patente`, `vin` |
| `usuario` | `email`, `nombre` |
| `falla_sesion` | `freeze_frame` |
| `usuario_credencial` | la tabla completa (sin trigger de auditoría) |

Lo que **sí** queda son identificadores internos, estados, montos y fechas: permiten reconstruir *qué
pasó y quién del taller lo hizo*, sin reconstruir *a qué cliente*. Tras la anonimización, el `titular_id`
que aparece en la auditoría apunta a una fila sin datos.

Verificado en [humo §4e] (0 registros con datos personales) y en el `INSERT` de vehículo que se muestra
allí: aparecen `anio`, `motor` y `modelo_vehiculo_id`, pero no `patente` ni `vin`.

La lista se mantiene en un solo lugar: los argumentos de cada `CREATE TRIGGER ... fn_trg_auditar(...)`
en `V005`. **Agregar una columna personal a una tabla obliga a agregarla también ahí.**

## 8. Supresión con retención legal

### Flujo

```
fn_solicitar_supresion_titular(titular_id)        [administrador]
        │
        ├─ registra la solicitud (tipo 'supresion', estado 'en_proceso')
        │
        ├─ ¿última atención no cancelada + retencion_anios > hoy?
        │
        ├── SÍ → estado 'bloqueado', bloqueado_hasta = esa fecha
        │         · el mecánico deja de ver al titular y a sus vehículos
        │         · los datos se conservan solo por obligación de retención
        │
        └── NO → fn_anonimizar_titular(titular_id)   (inmediato, irreversible)

fn_anonimizar_vencidos()                           [proceso periódico, app_owner]
        └─ anonimiza todo titular 'bloqueado' con bloqueado_hasta <= hoy
```

- **Quién.** Solo el administrador puede solicitar la supresión. **Nadie** de un taller puede anonimizar
  directamente ([humo §5d]): hacerlo saltaría la retención.
- **Qué cuenta como atención.** Sesiones no canceladas de los vehículos del titular. Una sesión cancelada
  no generó servicio y no justifica conservar datos (criterio de diseño, **validar**).
- **`retencion_anios`** vive en `taller_configuracion`: cambiar el plazo es cambiar un dato. Con `0`,
  toda supresión anonimiza de inmediato.
- **Proceso periódico.** La imagen `postgres:16` no trae `pg_cron`: `fn_anonimizar_vencidos()` la ejecuta
  `db/scripts/anonimizar_vencidos.sh` desde el programador de tareas del sistema, asumiendo `app_owner`
  (`docs/operacion.md` §7). Si ese job no corre, los bloqueos vencidos quedan sin anonimizar; el script
  termina con error si queda alguno, y la misma cuenta aparece en `db/scripts/estado.sh` §10 y la vigila
  la prueba `OPE-08`:
  `SELECT count(*) FROM titular WHERE estado_tratamiento = 'bloqueado' AND bloqueado_hasta <= current_date`.

Comprobado en [humo §5c]: con una atención completada hoy y `retencion_anios = 6`, el titular queda
`bloqueado` con vencimiento a 6 años y la solicitud `en_proceso`. En [humo §7], vencido el plazo, el
proceso lo anonimiza y la solicitud pasa a `resuelta`.

### Qué hace la anonimización

| Tabla | Cambio |
|---|---|
| `titular` | `nombre`, `telefono`, `email`, `identificador_hmac` → `NULL`; `estado_tratamiento = 'anonimizado'`; `anonimizado_en = now()` |
| `vehiculo` (del titular) | `patente`, `vin` → `NULL`; `anonimizado_en = now()` |
| `consentimiento_titular` | los activos quedan revocados |
| `solicitud_derecho_titular` | la supresión pendiente pasa a `resuelta` |
| `sesion_diagnostico`, `falla_sesion`, `cotizacion`, `cotizacion_detalle` | **sin cambios** |

Se conserva como **dato técnico** la marca, el modelo, el año y el motor: "se atendió una Hilux 2021 2.4
con el DTC P0301 y se cotizaron $98.748" sigue siendo verdad y útil para estadísticas, pero ya no se
puede vincular con una persona. La trazabilidad financiera queda íntegra ([humo §7]: sesión `completado`,
total 98748).

Es **irreversible**: no hay copia de los valores borrados ni transición de salida desde `anonimizado`.
Los `CHECK` de `titular` y `vehiculo` impiden que un registro anonimizado vuelva a tener datos.

### Por qué `NULL` y no un hash de la patente

Podría pensarse en reemplazar la patente por su hash para "poder reconocer el vehículo si vuelve". Sería
un error por la misma razón de la sección 4. Las patentes chilenas de vehículos livianos tienen:

- formato antiguo `AA1234`: 26² × 10⁴ = 6.760.000 combinaciones;
- formato nuevo `BBBB12`: 18⁴ × 10² = 10.497.600 combinaciones.

Son unos **17 millones** de valores en total. Un hash sin clave se revierte calculando los 17 millones y
comparando: no anonimiza nada. Y un HMAC tampoco sirve aquí, porque el objetivo de la supresión es
justamente que el dato **deje de existir**, no que quede recuperable por quien tenga la clave. Por eso
la patente y el VIN pasan a `NULL`.

Consecuencia aceptada: si el mismo vehículo vuelve al taller después de la anonimización, se registra
como un vehículo nuevo, sin vínculo con su historial anterior.

## 9. Visibilidad por rol

| Estado del titular | Administrador | Mecánico | Auditor |
|---|---|---|---|
| `activo` | ve todo | ve todo | ve estado y fechas, **sin identidad** |
| `bloqueado` | ve todo (lo necesita para gestionar la retención) | **no ve** al titular ni sus vehículos | ve estado y fechas |
| `anonimizado` | ve la fila vacía | **no ve** | ve estado y fechas |

- El mecánico, que es quien opera a diario, pierde el acceso en cuanto se solicita la supresión
  ([humo §6]: 0 titulares, 0 vehículos). Sus sesiones siguen en el historial, sin datos del vehículo.
- El auditor nunca ve nombre, contacto ni HMAC: su privilegio sobre `titular` es por columna ([humo §4a]).
- **El auditor sí ve patente y VIN** (tema T-17, aprobado: el enunciado solo excluye la identidad del
  titular). Si se adopta el criterio más prudente, se le quitan con el mismo mecanismo de privilegios por
  columna.

## 10. Limitaciones

1. **Respaldos.** La anonimización modifica la base viva, no las copias de seguridad ya tomadas: un
   respaldo anterior sigue conteniendo los datos. La política de retención de respaldos debe ser coherente
   con la de datos, y una restauración debe ir seguida de re-aplicar las anonimizaciones posteriores a la
   fecha del respaldo. Comprobado en `docs/evidencia/fase6_respaldo.txt`: una supresión solicitada después
   del respaldo **desaparece** al restaurar (el titular vuelve a estar `activo`). `restaurar.sh` ejecuta
   `fn_anonimizar_vencidos()` al terminar, pero las solicitudes posteriores al respaldo hay que reaplicarlas
   a mano desde un registro externo a la base (`docs/operacion.md` §3.4).
2. **`freeze_frame`.** Es JSON libre proveniente del escáner. La anonimización no lo modifica; el backend
   **no debe guardar el VIN ni otro identificador dentro de él**. Está excluido de la auditoría por
   precaución.
3. **Registros del servidor y WAL.** Con `log_statement = none` y `log_min_error_statement = panic` las
   sentencias no se registran ni siquiera cuando fallan (`docs/operacion.md` §5), pero el WAL contiene los
   valores previos hasta que se recicla.
4. **Datos de los trabajadores.** Nombre y email de `usuario` están excluidos de la auditoría, pero no
   existe un flujo de supresión para usuarios: se desactivan (`activo = false`). Su tratamiento se rige
   por la relación laboral (**validar**).
5. **Plazos y bases legales.** El plazo de retención, la calificación de patente y VIN como datos
   personales, las bases de licitud y los plazos de respuesta a solicitudes son **supuestos a validar**.
6. **Portabilidad y acceso** se resuelven en la API; la base solo registra la solicitud.

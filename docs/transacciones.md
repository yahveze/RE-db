# Transacciones

Qué operaciones deben ser atómicas, qué sentencias las componen (`db/queries/t0*.sql`) y qué protege a cada
una frente a fallos y concurrencia. La ejecución real, con sus errores, está en
`docs/evidencia/fase3_transacciones.txt`; la numeración TX-n de este documento es la de sus secciones, y
**[TX-3a]** remite al paso `3a` de esa salida.

## 1. Marco común

- **Nivel de aislamiento: `READ COMMITTED`** (el del servidor, verificado en la Fase 0). No se usa
  `SERIALIZABLE`: las pocas reglas que dependen de más de una fila se protegen con bloqueos explícitos de
  fila y con índices únicos, lo que evita reintentos por fallos de serialización en el backend.
- **Una petición = una transacción.** Si cualquier sentencia falla, el backend hace `ROLLBACK` de la
  petición completa. Rol y contexto son `SET LOCAL`: mueren con la transacción.
- **Orden de bloqueo fijo: sesión → cotización → detalle.** Lo respetan `fn_cambiar_estado_sesion`,
  `fn_cerrar_cotizacion` y los triggers. Dos transacciones que toman los bloqueos en el mismo orden no
  pueden esperarse mutuamente.
- **Dos mecanismos frente a escrituras simultáneas**, con papeles distintos:

| Mecanismo | Qué resuelve | Dónde |
|---|---|---|
| Bloqueo pesimista (`FOR UPDATE` / `FOR SHARE`) | dos transacciones **a la vez** sobre la misma sesión o cotización: la segunda espera y luego ve el resultado de la primera | funciones y triggers |
| Control optimista (`version`) | un usuario que decide con datos **viejos**: leyó la versión 1, otro la cambió, y envía su cambio minutos después | `p_version_esperada` → `RE007` |
| Idempotencia (`clave_idempotencia`) | el **mismo** cliente reintenta porque no recibió la respuesta | `fn_crear_cotizacion` |

## 2. Transacciones

### TX-1 Alta de usuario con contraseña (administrador)

```sql
BEGIN; SET LOCAL ROLE taller_admin; EXECUTE ctx(...);
EXECUTE tx_crear_usuario($email, $nombre, $rol);
EXECUTE tx_establecer_contrasena($usuario_id_publico, $contrasena);
COMMIT;
```

Atómica porque un usuario sin credencial no puede autenticarse y quedaría como un registro a medias. Si la
contraseña se rechaza (`RE011`), el usuario tampoco queda creado [TX-1a]. Email repetido → `23505` [TX-1c].
La credencial solo se escribe mediante la función definidora, que valida rol y taller.

### TX-2 Titular, consentimiento y vehículo (mecánico o administrador)

```sql
EXECUTE tx_crear_titular($nombre, $telefono, $email, $hmac);
EXECUTE tx_registrar_consentimiento($titular_id_publico, 'prestacion_servicio', $version, $canal);
EXECUTE tx_crear_vehiculo($titular_id_publico, $modelo_id_publico, $anio, $motor, $vin, $patente);
```

Si el vehículo falla (patente duplicada `23505`, formato inválido `23514`) no queda un titular huérfano con
su consentimiento [TX-2a, 2b]. Un `id_publico` de titular inexistente produce cero filas en lugar de un
vehículo sin titular [TX-2c]. Las FK compuestas impiden además asociar un titular de otro taller.

### TX-3 Crear sesión con sus fallas (mecánico)

Una sola sentencia (`tx_crear_sesion`, CTE con dos `INSERT`), atómica por sí misma:

- un DTC que no está en el catálogo aborta todo (`23502`): no queda la sesión ni las otras fallas [TX-3a];
- un dispositivo que no está `activo` con ingreso OBD viola el CHECK de método (`23514`) [TX-3b];
- la sesión nace `pendiente`, versión 1, a nombre del usuario del contexto y con la hora del servidor: el
  cliente no envía estado, usuario ni fecha [TX-3c].

### TX-4 Armar la cotización (mecánico)

```sql
EXECUTE tx_crear_cotizacion($sesion_id_publico, $clave_idempotencia);
EXECUTE tx_guardar_linea($cotizacion_id_publico, $repuesto_id_publico, $cantidad);   -- una por línea
EXECUTE tx_quitar_linea($cotizacion_id_publico, $repuesto_id_publico);
```

- **Idempotencia:** la misma clave devuelve la misma cotización; la sesión sigue con una sola [TX-4b]. Otra
  clave mientras hay un borrador abierto → `23505` por el índice único parcial [TX-4c].
- **Precios:** el cliente envía repuesto y cantidad; el trigger copia el *snapshot* y calcula
  `precio_unitario`. Repetir un repuesto reemplaza la cantidad [TX-4d, 4e].
- Repuesto no disponible → `RE010`; cantidad no positiva → `23514` [TX-4f].
- Cada línea puede ir en su propia petición: mientras la cotización está abierta no hay nada que congelar.

### TX-5 Cerrar la cotización y pasar la sesión a `cotizado` (mecánico)

```sql
EXECUTE tx_cerrar_cotizacion($cotizacion_id_publico, $version_cotizacion);
EXECUTE tx_cambiar_estado($sesion_id_publico, 'cotizado', $version_sesion);
```

Es la transacción central. Dentro de `fn_cerrar_cotizacion`:

1. `FOR UPDATE` sobre la sesión y luego sobre la cotización (orden fijo).
2. Se apaga la vigente anterior **antes** de encender la nueva: el índice único parcial no es diferible.
3. El trigger suma el detalle, fija `total` y `cerrada_en` (hora del servidor) y rechaza un cierre sin líneas
   (`RE008`).

Protecciones: una línea que llega durante el cierre espera en el `FOR SHARE` del trigger del detalle y, al
despertar, encuentra la cotización cerrada (`RE003`) —nunca se agrega a un total ya congelado—; una versión
antigua da `RE007` [TX-5a]; repetir el cierre devuelve la misma cotización sin cambios [TX-5c]; cerrada, la
cotización y su detalle son inmutables [TX-5d].

Las dos sentencias van juntas para que no exista una sesión `pendiente` con cotización vigente si el
backend cae entre ambas.

### TX-6 Nueva revisión (mecánico)

Mismas sentencias que TX-4 y TX-5, con otra clave de idempotencia y **sin** el cambio de estado (la sesión
ya está `cotizado`). Al cerrarla, la revisión 2 pasa a ser la vigente y la revisión 1 queda cerrada, no
vigente y con su total intacto [TX-6]. En ningún instante hay dos vigentes ni ninguna: el apagado y el
encendido ocurren en la misma transacción.

### TX-7 Cambiar la configuración (administrador)

`tx_actualizar_configuracion` es un `UPDATE` sin `WHERE`: RLS lo limita a la fila del taller. El margen nuevo
rige para la matriz y para las líneas que se agreguen desde ese momento; lo ya cotizado conserva su
*snapshot* [TX-7b, 7c]. Fuera de rango → `23514` [TX-7a].

### TX-8 Completar o cancelar (mecánico)

```sql
EXECUTE tx_cambiar_estado($sesion_id_publico, 'completado', $version_sesion);
```

El trigger valida la transición (`RE001`), exige cotización vigente cerrada (`RE002`) y fija el timestamp.
Con una versión vieja → `RE007` y la API pide recargar [TX-8a]. Un estado terminal no admite otro estado ni
cotizaciones nuevas (`RE001`, `RE004`) [TX-8c].

### TX-9 Supresión de un titular (administrador)

```sql
EXECUTE tx_solicitar_supresion($titular_id_publico);
```

Dentro de la función: registra la solicitud y, según el plazo de retención, bloquea al titular o lo
anonimiza junto con **todos** sus vehículos, revoca sus consentimientos y resuelve la solicitud. A medias
quedaría un dato personal expuesto; por eso es una sola transacción. El mecánico no puede ejecutarla
(`42501`) [TX-9a]; tras el bloqueo deja de encontrar el vehículo, pero la sesión sigue en su historial
[TX-9c].

## 3. Aislamiento entre talleres en escritura (TX-10)

Las mismas sentencias, ejecutadas por la mecánica del taller 2 con `id_publico` reales del taller 1,
devuelven cero filas: no crean, no modifican y no revelan si el recurso existe [TX-10]. Como los padres se
resuelven por `id_publico` bajo RLS, el `taller_id` de cada fila nueva sale siempre de una fila visible o
del contexto, nunca del cliente.

## 4. Qué deja cada transacción en la auditoría

La demostración termina listando lo que generó [transacciones, sección final]: cada petición queda
identificada por su `request_id`, con el rol real (`taller_admin`, `taller_mecanico`) y, en los inicios de
sesión, `app_backend_user` sin `request_id` (ocurren antes de que exista contexto).

## 5. Lo que esta fase no demuestra

La demostración corre en **una sola sesión**: prueba atomicidad, reglas y aislamiento entre talleres, pero
no la concurrencia real. Que dos cierres simultáneos, o un cierre y una inserción de línea a la vez, se
comporten como se describe en TX-5 se demuestra con dos conexiones en `db/tests/concurrencia.sh` (Fase 4).

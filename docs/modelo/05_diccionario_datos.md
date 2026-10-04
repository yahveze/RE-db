# 5. Diccionario de datos

> **Archivo generado.** No editar a mano: se obtiene del catalogo de PostgreSQL
> (`COMMENT ON` de `db/migrations/V004__comentarios.sql`) con `bash db/scripts/diccionario.sh`.
> Asi el diccionario no puede desalinearse del esquema real.

## Multi-taller

### `taller`

Taller mecanico: unidad de aislamiento de datos (inquilino). Agregar un taller es un INSERT.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. Es el valor de app.taller_id en el contexto de la peticion. |
| `id_publico` | uuid | no | `gen_random_uuid()` | Identificador publico que expone la API. |
| `nombre` | text | no |  | Nombre del taller. |
| `activo` | boolean | no | `true` | Baja logica del taller. Un taller inactivo no puede autenticar usuarios. |
| `creado_en` | timestamp with time zone | no | `now()` | Fecha de creacion del registro. |
| `actualizado_en` | timestamp with time zone | no | `now()` | Fecha de la ultima modificacion. La mantiene un trigger. |

### `taller_configuracion`

Parametros del taller (1:1). Separada de taller por privilegios: el administrador la modifica.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `taller_id` | bigint | no |  | Taller al que pertenece la configuracion. Es la clave primaria. |
| `moneda` | character(3) | no | `'CLP'::bpchar` | Codigo ISO 4217 de la moneda del taller. Por defecto CLP. |
| `tema` | tipo_tema_visual | no | `'claro'::tipo_tema_visual` | Tema visual de la interfaz. |
| `margen_pct` | numeric(5,2) | no | `30.00` | Margen (markup sobre costo) en porcentaje, de 0 a 200. precio_venta = ROUND(precio_referencia * (1 + margen_pct / 100)). |
| `retencion_anios` | smallint | no | `6` | Anios de conservacion de datos tras la ultima atencion antes de anonimizar. Supuesto a validar con asesoria legal. |
| `actualizado_en` | timestamp with time zone | no | `now()` | Fecha de la ultima modificacion. La mantiene un trigger. |

### `usuario`

Persona que opera el sistema. Pertenece a un solo taller.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. Es el valor de app.usuario_id en el contexto de la peticion. |
| `id_publico` | uuid | no | `gen_random_uuid()` | Identificador publico que expone la API. |
| `taller_id` | bigint | no |  | Taller al que pertenece el usuario. |
| `email` | text | no |  | Email de inicio de sesion, en minusculas. Unico global. Dato personal: excluido de la auditoria. |
| `nombre` | text | no |  | Nombre del usuario. Dato personal: excluido de la auditoria. |
| `rol` | tipo_rol_usuario | no |  | Rol del usuario: admin, mecanico o auditor. |
| `activo` | boolean | no | `true` | Baja logica. Un usuario inactivo no puede iniciar sesion. |
| `creado_en` | timestamp with time zone | no | `now()` | Fecha de creacion del registro. |
| `actualizado_en` | timestamp with time zone | no | `now()` | Fecha de la ultima modificacion. La mantiene un trigger. |

### `usuario_credencial`

Credencial del usuario (1:1). Ningun rol de grupo tiene acceso: solo funciones SECURITY DEFINER. Sin trigger de auditoria.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `usuario_id` | bigint | no |  | Usuario dueno de la credencial. Es la clave primaria. |
| `hash_contrasena` | text | no |  | Hash bcrypt de la contrasena (crypt con gen_salt bf, costo 10). Nunca sale de la base. |
| `intentos_fallidos` | integer | no | `0` | Intentos fallidos consecutivos de inicio de sesion. |
| `bloqueado_hasta` | timestamp with time zone | si |  | Momento hasta el que la cuenta rechaza inicios de sesion por exceso de intentos. |
| `ultimo_login_en` | timestamp with time zone | si |  | Momento del ultimo inicio de sesion exitoso. |
| `actualizado_en` | timestamp with time zone | no | `now()` | Fecha de la ultima modificacion. La mantiene un trigger. |

## Privacidad

### `consentimiento_titular`

Consentimientos del titular por finalidad. Revocar no borra la fila: queda la evidencia.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. |
| `taller_id` | bigint | no |  | Taller del titular (desnormalizacion protegida por FK compuesta). |
| `titular_id` | bigint | no |  | Titular que otorga el consentimiento. |
| `finalidad` | tipo_finalidad_tratamiento | no |  | Finalidad consentida. |
| `version_terminos` | text | no |  | Version del texto de terminos que acepto el titular. |
| `canal` | text | no |  | Canal por el que se otorgo: presencial, app, web o telefono. |
| `otorgado_en` | timestamp with time zone | no | `now()` | Momento en que se otorgo. |
| `revocado_en` | timestamp with time zone | si |  | Momento en que se revoco. Nulo mientras esta activo. |

### `solicitud_derecho_titular`

Solicitudes de ejercicio de derechos del titular (acceso, rectificacion, supresion, oposicion, portabilidad, bloqueo).

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. Nunca se expone por la API. |
| `id_publico` | uuid | no | `gen_random_uuid()` | Identificador publico que expone la API. |
| `taller_id` | bigint | no |  | Taller del titular (desnormalizacion protegida por FK compuesta). |
| `titular_id` | bigint | no |  | Titular que presenta la solicitud. |
| `tipo` | tipo_solicitud_derecho | no |  | Derecho que se ejerce. |
| `estado` | tipo_estado_solicitud | no | `'recibida'::tipo_estado_solicitud` | Estado de tramitacion. |
| `usuario_responsable_id` | bigint | si |  | Usuario que gestiona la solicitud. Opcional. |
| `recibida_en` | timestamp with time zone | no | `now()` | Momento en que se recibio la solicitud. |
| `resuelta_en` | timestamp with time zone | si |  | Momento de la resolucion. No nulo si y solo si el estado es resuelta o rechazada. |
| `actualizado_en` | timestamp with time zone | no | `now()` | Fecha de la ultima modificacion. La mantiene un trigger. |

### `titular`

Persona natural titular de vehiculos. Dato personal, no es usuario del sistema. Pertenece a un taller. Sin RUT.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. Nunca se expone por la API. |
| `id_publico` | uuid | no | `gen_random_uuid()` | Identificador publico que expone la API. |
| `taller_id` | bigint | no |  | Taller responsable de los datos del titular. |
| `nombre` | text | si |  | Nombre del titular. Obligatorio salvo anonimizado. Dato personal: excluido de la auditoria. |
| `telefono` | text | si |  | Telefono de contacto, opcional. Dato personal: excluido de la auditoria. |
| `email` | text | si |  | Email de contacto, opcional. Dato personal: excluido de la auditoria. |
| `identificador_hmac` | bytea | si |  | HMAC-SHA-256 (32 bytes) de un identificador del titular, calculado por el backend con un secreto que nunca llega a la base. Excluido de la auditoria. |
| `estado_tratamiento` | tipo_estado_tratamiento | no | `'activo'::tipo_estado_tratamiento` | activo, bloqueado (conservado solo por retencion legal) o anonimizado. |
| `bloqueado_hasta` | date | si |  | Fecha en que vence la retencion y corresponde anonimizar. Solo en estado bloqueado. |
| `anonimizado_en` | timestamp with time zone | si |  | Momento de la anonimizacion irreversible. |
| `creado_en` | timestamp with time zone | no | `now()` | Fecha de creacion del registro. |
| `actualizado_en` | timestamp with time zone | no | `now()` | Fecha de la ultima modificacion. La mantiene un trigger. |

## Catalogos globales

### `compatibilidad_repuesto`

Relacion N:M: con que modelos y rango de anios es compatible un repuesto.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `repuesto_id` | bigint | no |  | Repuesto compatible. |
| `modelo_vehiculo_id` | bigint | no |  | Modelo de vehiculo con el que es compatible. |
| `anio_desde` | smallint | no |  | Primer anio del rango de compatibilidad (inclusive). |
| `anio_hasta` | smallint | no |  | Ultimo anio del rango de compatibilidad (inclusive). |

### `componente_repuesto`

Catalogo global de componentes (pieza funcional que se reemplaza). La matriz compara repuestos del mismo componente.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. Nunca se expone por la API. |
| `id_publico` | uuid | no | `gen_random_uuid()` | Identificador publico que expone la API. |
| `nombre` | text | no |  | Nombre del componente, por ejemplo Bujia. Unico. |
| `descripcion` | text | si |  | Descripcion opcional del componente. |
| `creado_en` | timestamp with time zone | no | `now()` | Fecha de creacion del registro. |

### `dtc_catalogo`

Catalogo global de codigos de falla OBD-II (DTC).

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. La API identifica el DTC por su codigo. |
| `codigo` | text | no |  | Codigo DTC, por ejemplo P0301. Formato ^[PCBU][0-3][0-9A-F]{3}$. Unico. |
| `descripcion` | text | no |  | Descripcion de la falla. |
| `severidad_sugerida` | tipo_severidad | no |  | Severidad propuesta por el catalogo; valor inicial de falla_sesion.severidad. |
| `creado_en` | timestamp with time zone | no | `now()` | Fecha de creacion del registro. |

### `dtc_componente`

Relacion N:M: que componentes pueden causar un DTC. PK compuesta natural.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `dtc_id` | bigint | no |  | DTC del catalogo. |
| `componente_id` | bigint | no |  | Componente asociado al DTC. |

### `marca_vehiculo`

Catalogo global de marcas de vehiculos. Solo lectura para los talleres.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. Nunca se expone por la API. |
| `id_publico` | uuid | no | `gen_random_uuid()` | Identificador publico que expone la API. |
| `nombre` | text | no |  | Nombre de la marca. Unico. |
| `creado_en` | timestamp with time zone | no | `now()` | Fecha de creacion del registro. |

### `modelo_vehiculo`

Catalogo global de modelos. Normaliza la dependencia modelo -> marca.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. Nunca se expone por la API. |
| `id_publico` | uuid | no | `gen_random_uuid()` | Identificador publico que expone la API. |
| `marca_vehiculo_id` | bigint | no |  | Marca a la que pertenece el modelo. |
| `nombre` | text | no |  | Nombre del modelo. Unico dentro de su marca. |
| `creado_en` | timestamp with time zone | no | `now()` | Fecha de creacion del registro. |

### `repuesto`

Catalogo global de repuestos. Cada repuesto pertenece a un componente y tiene un perfil y un precio maestro.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. Nunca se expone por la API. |
| `id_publico` | uuid | no | `gen_random_uuid()` | Identificador publico que expone la API. |
| `componente_id` | bigint | no |  | Componente al que pertenece el repuesto. |
| `perfil` | tipo_perfil_repuesto | no |  | Perfil comercial: genuino, oem o generico. |
| `marca` | text | no |  | Marca del repuesto. Texto y no catalogo: no existe atributo que dependa de la marca. |
| `nombre` | text | no |  | Nombre comercial del repuesto. |
| `codigo_fabricante` | text | no |  | Numero de parte del fabricante. Unico junto con componente y marca. |
| `durabilidad_estimada_km` | integer | no |  | Durabilidad estimada en kilometros. Mayor que cero. |
| `riesgo` | tipo_nivel_riesgo | no |  | Nivel de riesgo estimado del repuesto. |
| `precio_referencia` | bigint | no |  | Precio maestro (costo) en la unidad minima de la moneda. Lo mantiene solo la plataforma. |
| `disponible` | boolean | no | `true` | Si puede cotizarse. Un repuesto no se borra: se marca no disponible. |
| `creado_en` | timestamp with time zone | no | `now()` | Fecha de creacion del registro. |
| `actualizado_en` | timestamp with time zone | no | `now()` | Fecha de la ultima modificacion. La mantiene un trigger. |

### `v_dtc_repuesto` (vista)

Relacion DTC <-> repuesto derivada de dtc_componente y repuesto. Es vista para evitar redundancia y anomalias de actualizacion.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `dtc_id` | bigint | si |  | DTC del catalogo. |
| `componente_id` | bigint | si |  | Componente que vincula el DTC con el repuesto. |
| `repuesto_id` | bigint | si |  | Repuesto que resuelve el DTC a traves de su componente. |

## Operacion

### `cotizacion`

Revision numerada de la cotizacion de una sesion. Abierta mientras cerrada_en es nulo; cerrada es inmutable.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. Nunca se expone por la API. |
| `id_publico` | uuid | no | `gen_random_uuid()` | Identificador publico que expone la API. |
| `taller_id` | bigint | no |  | Taller de la sesion (desnormalizacion protegida por FK compuesta). |
| `sesion_id` | bigint | no |  | Sesion que se cotiza. |
| `numero_revision` | integer | no |  | Numero correlativo de la revision dentro de la sesion. Lo asigna un trigger. |
| `vigente` | boolean | no | `false` | Si es la cotizacion valida de la sesion. A lo mas una por sesion, y solo si esta cerrada. |
| `cerrada_en` | timestamp with time zone | si |  | Momento del cierre. Nulo = abierta (borrador). |
| `total` | bigint | si |  | Suma de cantidad * precio_unitario del detalle. Se calcula y congela al cerrar; nulo mientras esta abierta. |
| `moneda` | character(3) | no |  | Moneda de la cotizacion, copiada de la configuracion del taller al crearla. |
| `clave_idempotencia` | uuid | no |  | UUID generado por el cliente; reintentar con la misma clave devuelve la misma cotizacion. |
| `version` | integer | no | `1` | Contador para control optimista de concurrencia. Lo incrementa un trigger en cada UPDATE. |
| `creado_en` | timestamp with time zone | no | `now()` | Fecha de creacion del registro. |
| `actualizado_en` | timestamp with time zone | no | `now()` | Fecha de la ultima modificacion. La mantiene un trigger. |

### `cotizacion_detalle`

Lineas de una cotizacion. Guarda un snapshot del repuesto y del margen: desnormalizacion intencional.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `cotizacion_id` | bigint | no |  | Cotizacion a la que pertenece la linea. |
| `repuesto_id` | bigint | no |  | Repuesto cotizado. Un repuesto aparece una vez por cotizacion. |
| `taller_id` | bigint | no |  | Taller de la cotizacion (desnormalizacion protegida por FK compuesta; simplifica RLS). |
| `cantidad` | integer | no |  | Unidades cotizadas. Mayor que cero. Unico dato modificable mientras la cotizacion esta abierta. |
| `nombre_snapshot` | text | no |  | Nombre del repuesto al momento de cotizar. Lo llena un trigger. |
| `marca_snapshot` | text | no |  | Marca del repuesto al momento de cotizar. La llena un trigger. |
| `perfil_snapshot` | tipo_perfil_repuesto | no |  | Perfil del repuesto al momento de cotizar. Lo llena un trigger. |
| `precio_referencia_snapshot` | bigint | no |  | Precio maestro del repuesto al momento de cotizar. Lo llena un trigger. |
| `margen_pct_snapshot` | numeric(5,2) | no |  | Margen del taller al momento de cotizar. Lo llena un trigger. |
| `precio_unitario` | bigint | no |  | Precio de venta unitario = ROUND(precio_referencia_snapshot * (1 + margen_pct_snapshot / 100)). Lo calcula un trigger. |
| `creado_en` | timestamp with time zone | no | `now()` | Fecha de creacion del registro. |

### `dispositivo_diagnostico`

Escaner OBD-II Bluetooth registrado por un taller.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. Nunca se expone por la API. |
| `id_publico` | uuid | no | `gen_random_uuid()` | Identificador publico que expone la API. |
| `taller_id` | bigint | no |  | Taller dueno del dispositivo. |
| `mac` | macaddr | no |  | Direccion MAC Bluetooth. El tipo macaddr la valida y normaliza. Unica por taller. |
| `estado` | tipo_estado_dispositivo | no | `'activo'::tipo_estado_dispositivo` | activo, inactivo o baja. |
| `fabricante` | text | si |  | Fabricante del dispositivo. |
| `modelo` | text | si |  | Modelo del dispositivo. |
| `firmware` | text | si |  | Version de firmware. |
| `creado_en` | timestamp with time zone | no | `now()` | Fecha de creacion del registro. |
| `actualizado_en` | timestamp with time zone | no | `now()` | Fecha de la ultima modificacion. La mantiene un trigger. |

### `falla_sesion`

Relacion N:M: DTC detectados en una sesion. PK compuesta natural (sesion_id, dtc_id).

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `sesion_id` | bigint | no |  | Sesion en la que se detecto la falla. |
| `dtc_id` | bigint | no |  | DTC detectado. |
| `taller_id` | bigint | no |  | Taller de la sesion (desnormalizacion protegida por FK compuesta; simplifica RLS). |
| `severidad` | tipo_severidad | no |  | Severidad observada en esta sesion; puede diferir de la sugerida por el catalogo. |
| `freeze_frame` | jsonb | si |  | Datos de freeze frame del escaner, opcional. Objeto JSON opaco para el modelo. Excluido de la auditoria. |
| `creado_en` | timestamp with time zone | no | `now()` | Fecha de creacion del registro. |

### `sesion_diagnostico`

Atencion: un diagnostico de un vehiculo en un taller. Lleva el estado de la atencion.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. Nunca se expone por la API. |
| `id_publico` | uuid | no | `gen_random_uuid()` | Identificador publico que expone la API. |
| `taller_id` | bigint | no |  | Taller donde se realiza la atencion. |
| `vehiculo_id` | bigint | no |  | Vehiculo diagnosticado. |
| `usuario_id` | bigint | no |  | Mecanico que realiza la atencion. |
| `dispositivo_id` | bigint | si |  | Dispositivo usado. Obligatorio si y solo si el metodo es obd_bluetooth. |
| `metodo_ingreso` | tipo_metodo_ingreso | no |  | Como se ingresaron los DTC: obd_bluetooth o manual. |
| `kilometraje` | integer | no |  | Kilometraje del vehiculo al momento de la atencion. |
| `estado` | tipo_estado_atencion | no | `'pendiente'::tipo_estado_atencion` | pendiente, cotizado, completado o cancelado. Las transiciones las valida un trigger. |
| `iniciada_en` | timestamp with time zone | no | `now()` | Momento de inicio de la sesion. Clave del historial y de la paginacion. |
| `cotizada_en` | timestamp with time zone | si |  | Momento en que paso a cotizado. Lo fija el trigger de estados. |
| `completada_en` | timestamp with time zone | si |  | Momento en que paso a completado. Lo fija el trigger de estados. |
| `cancelada_en` | timestamp with time zone | si |  | Momento en que paso a cancelado. Lo fija el trigger de estados. |
| `version` | integer | no | `1` | Contador para control optimista de concurrencia. Lo incrementa un trigger en cada UPDATE. |
| `actualizado_en` | timestamp with time zone | no | `now()` | Fecha de la ultima modificacion. La mantiene un trigger. |

### `vehiculo`

Vehiculo atendido por un taller. El mismo vehiculo fisico en dos talleres son dos filas.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno. Nunca se expone por la API. |
| `id_publico` | uuid | no | `gen_random_uuid()` | Identificador publico que expone la API. |
| `taller_id` | bigint | no |  | Taller que registro el vehiculo. |
| `titular_id` | bigint | si |  | Titular del vehiculo. Opcional. |
| `modelo_vehiculo_id` | bigint | no |  | Modelo del vehiculo; la marca se obtiene del modelo. |
| `anio` | smallint | no |  | Anio del vehiculo, entre 1981 y 2100. |
| `motor` | text | si |  | Descripcion del motor. Obligatorio si no hay VIN. |
| `vin` | text | si |  | Numero de identificacion del vehiculo (17 caracteres, sin I, O ni Q). Opcional. Dato personal indirecto: excluido de la auditoria. |
| `patente` | text | si |  | Patente chilena en mayusculas (AA1234 o BBBB12). Obligatoria salvo anonimizado. Dato personal indirecto: excluido de la auditoria. |
| `anonimizado_en` | timestamp with time zone | si |  | Momento en que se anonimizo: patente y VIN pasan a nulo. |
| `creado_en` | timestamp with time zone | no | `now()` | Fecha de creacion del registro. |
| `actualizado_en` | timestamp with time zone | no | `now()` | Fecha de la ultima modificacion. La mantiene un trigger. |

## Seguridad

### `auditoria_operacion`

Bitacora append-only de operaciones. Sin claves foraneas. No contiene datos personales ni secretos.

| Columna | Tipo | Nulo | Valor por defecto | Descripcion |
|---|---|---|---|---|
| `id` | bigint | no | identidad | Identificador interno, correlativo. |
| `ocurrido_en` | timestamp with time zone | no | `clock_timestamp()` | Momento real de la operacion (clock_timestamp). |
| `taller_id` | bigint | si |  | Taller afectado. Valor, no FK. Nulo si no se conoce (login de email inexistente, catalogos). |
| `usuario_id` | bigint | si |  | Usuario de la aplicacion que origino la operacion (app.usuario_id). Valor, no FK. |
| `rol` | text | no |  | Rol PostgreSQL efectivo de la peticion (el asumido con SET LOCAL ROLE o, si no hay, el de sesion). |
| `operacion` | tipo_operacion_auditoria | no |  | INSERT, UPDATE, DELETE, LOGIN o LOGIN_FALLIDO. |
| `tabla` | text | si |  | Tabla afectada. Nulo en operaciones de login. |
| `registro_id` | bigint | si |  | id de la fila afectada. Nulo en tablas de clave compuesta (la clave va en los datos). |
| `datos_anteriores` | jsonb | si |  | Fila antes de la operacion, sin las columnas sensibles excluidas. |
| `datos_nuevos` | jsonb | si |  | Fila despues de la operacion, sin las columnas sensibles excluidas. |
| `ip_origen` | inet | si |  | IP del cliente informada por el backend (app.ip_origen). |
| `resultado` | tipo_resultado_auditoria | no |  | exito, fallo o denegado. |
| `request_id` | text | si |  | Identificador de la peticion para correlacionar con los logs de la API (app.request_id). |

## Tipos enumerados

| Tipo | Valores | Descripcion |
|---|---|---|
| `tipo_estado_atencion` | pendiente, cotizado, completado, cancelado | Estado de una sesion de diagnostico. completado y cancelado son terminales. |
| `tipo_estado_dispositivo` | activo, inactivo, baja | Estado operativo de un dispositivo de diagnostico. baja reemplaza al borrado fisico. |
| `tipo_estado_solicitud` | recibida, en_proceso, resuelta, rechazada | Estado de tramitacion de una solicitud de derechos. |
| `tipo_estado_tratamiento` | activo, bloqueado, anonimizado | Estado del tratamiento de los datos personales de un titular. |
| `tipo_finalidad_tratamiento` | prestacion_servicio, contacto_seguimiento, marketing | Finalidad para la que se otorga un consentimiento. |
| `tipo_metodo_ingreso` | obd_bluetooth, manual | Como se ingresaron los DTC de una sesion. |
| `tipo_nivel_riesgo` | bajo, medio, alto | Riesgo estimado de usar un repuesto. |
| `tipo_operacion_auditoria` | INSERT, UPDATE, DELETE, LOGIN, LOGIN_FALLIDO | Tipo de operacion registrada en la auditoria. |
| `tipo_perfil_repuesto` | genuino, oem, generico | Perfil comercial del repuesto. Orden de presentacion fijo: genuino, oem, generico. |
| `tipo_resultado_auditoria` | exito, fallo, denegado | Resultado de la operacion auditada. |
| `tipo_rol_usuario` | admin, mecanico, auditor | Rol de un usuario dentro de su taller; determina el rol de grupo PostgreSQL que asume el backend. |
| `tipo_severidad` | baja, media, alta, critica | Severidad de una falla. |
| `tipo_solicitud_derecho` | acceso, rectificacion, supresion, oposicion, portabilidad, bloqueo | Derecho que ejerce el titular en una solicitud. |
| `tipo_tema_visual` | claro, oscuro | Tema de la interfaz configurado por el taller. |

# 1. Análisis del dominio y reglas de negocio

## 1.1 Problema

En un taller, quien diagnostica sabe más que quien paga. **Repuestos Exactos** reduce esa asimetría:
traduce los códigos de falla OBD-II (DTC) a componentes, y para cada componente muestra las alternativas
de repuesto comparables —genuino, OEM y genérico— con precio, durabilidad y riesgo, de las que sale una
cotización trazable.

## 1.2 Flujo y datos que toca

| Paso | Qué ocurre | Entidades |
|---|---|---|
| 1 | El mecánico se autentica | `usuario`, `usuario_credencial`, `auditoria_operacion` |
| 2 | Identifica el vehículo por VIN o por marca + modelo + año | `vehiculo`, `modelo_vehiculo`, `marca_vehiculo`, `titular` |
| 3 | Abre una sesión de diagnóstico (OBD-II Bluetooth o manual) | `sesion_diagnostico`, `dispositivo_diagnostico` |
| 4 | Registra los DTC detectados | `falla_sesion`, `dtc_catalogo` |
| 5 | El sistema arma la matriz comparativa | `dtc_componente`, `componente_repuesto`, `repuesto`, `compatibilidad_repuesto`, `taller_configuracion` |
| 6 | Genera y cierra la cotización | `cotizacion`, `cotizacion_detalle` |
| 7 | La atención avanza de estado | `sesion_diagnostico` |
| 8 | Historial y dashboard | lectura de todo lo anterior |

## 1.3 Actores

| Actor | Es usuario del sistema | Rol de BD | Qué hace |
|---|---|---|---|
| Administrador de taller | sí | `taller_admin` | gestiona usuarios, dispositivos y configuración de su taller; lee su auditoría |
| Mecánico operador | sí | `taller_mecanico` | registra vehículos, sesiones, fallas y cotizaciones |
| Auditor | sí | `taller_auditor` | solo lectura de su taller, sin identidad del titular |
| Titular del vehículo | **no** | — | persona natural cuyos datos se tratan; ejerce derechos mediante solicitudes |
| Plataforma | no (operación) | `app_owner` | mantiene los catálogos globales y las migraciones |

## 1.4 Entidades por grupo

| Grupo | Entidad | Propósito | Ámbito |
|---|---|---|---|
| Multi-taller | `taller` | Inquilino: unidad de aislamiento de datos | global |
| | `taller_configuracion` | Parámetros del taller: moneda, tema, margen, retención | 1:1 con taller |
| | `usuario` | Persona que opera el sistema | por taller |
| | `usuario_credencial` | Hash y control de intentos, separado por mínimo privilegio | 1:1 con usuario |
| Privacidad | `titular` | Persona natural asociada a vehículos | por taller |
| | `consentimiento_titular` | Registro de consentimientos por finalidad | por taller |
| | `solicitud_derecho_titular` | Ejercicio de derechos (acceso, supresión, …) | por taller |
| Catálogo global | `marca_vehiculo`, `modelo_vehiculo` | Marcas y modelos normalizados | global |
| | `dtc_catalogo` | Códigos de falla OBD-II | global |
| | `componente_repuesto` | Pieza funcional que se reemplaza (bujía, catalizador) | global |
| | `dtc_componente` | Qué componentes pueden causar un DTC (N:M) | global |
| | `repuesto` | Producto concreto de un componente, con perfil y precio maestro | global |
| | `compatibilidad_repuesto` | Con qué modelos y años sirve un repuesto | global |
| Operación | `vehiculo` | Vehículo atendido por un taller | por taller |
| | `dispositivo_diagnostico` | Escáner OBD-II Bluetooth del taller | por taller |
| | `sesion_diagnostico` | Atención: un diagnóstico de un vehículo | por taller |
| | `falla_sesion` | DTC detectados en una sesión (N:M) | por taller |
| | `cotizacion` | Revisión numerada de una cotización | por taller |
| | `cotizacion_detalle` | Líneas de la cotización con *snapshot* de precios | por taller |
| Seguridad | `auditoria_operacion` | Bitácora *append-only* | por taller, sin FK |
| Vista | `v_dtc_repuesto` | DTC ↔ repuesto, derivada | global |

**Entidades descartadas** (y por qué): *marca de repuesto* como catálogo (no hay atributo que dependa de
ella, ver normalización §4.6); *motor* como catálogo y *compatibilidad por motor* (**[AVANZADA]**);
*lista de precios por taller* (**[AVANZADA]**, decisión 6); *historial de propiedad* del vehículo
(**[AVANZADA]**, decisión 13); *documento tributario* (el sistema solo cotiza, decisión abierta f);
*RUT del titular* (decisión 16).

## 1.5 Cardinalidades

| Relación | Cardinalidad | Lectura |
|---|---|---|
| taller — taller_configuracion | 1 : 1 | todo taller tiene exactamente una configuración |
| taller — usuario | 1 : N | un usuario pertenece a un solo taller |
| usuario — usuario_credencial | 1 : 0..1 | la credencial no existe sin su usuario |
| taller — titular / vehiculo / dispositivo / sesión | 1 : N | datos propios de cada taller |
| titular — vehiculo | 0..1 : N | un vehículo puede no tener titular registrado |
| titular — consentimiento_titular | 1 : N | uno por finalidad y por cada otorgamiento |
| titular — solicitud_derecho_titular | 1 : N | |
| usuario — solicitud_derecho_titular | 0..1 : N | responsable asignado, opcional |
| marca_vehiculo — modelo_vehiculo | 1 : N | |
| modelo_vehiculo — vehiculo | 1 : N | todo vehículo tiene modelo |
| vehiculo — sesion_diagnostico | 1 : N | historial del vehículo |
| usuario — sesion_diagnostico | 1 : N | mecánico que atiende |
| dispositivo_diagnostico — sesion_diagnostico | 0..1 : N | obligatorio solo con `obd_bluetooth` |
| sesion_diagnostico — dtc_catalogo | N : M | resuelta por `falla_sesion` |
| dtc_catalogo — componente_repuesto | N : M | resuelta por `dtc_componente` |
| componente_repuesto — repuesto | 1 : N | las alternativas comparables de la matriz |
| repuesto — modelo_vehiculo | N : M | resuelta por `compatibilidad_repuesto` (con rango de años) |
| sesion_diagnostico — cotizacion | 1 : N | revisiones; a lo más una vigente y un borrador |
| cotizacion — repuesto | N : M | resuelta por `cotizacion_detalle` (con cantidad y *snapshot*) |

## 1.6 Reglas de negocio

Cada regla indica **cómo se hace cumplir**. Los identificadores `RN-xx` se usan después en las pruebas.

### Multi-taller y usuarios
| Id | Regla | Mecanismo |
|---|---|---|
| RN-01 | Todo dato operativo pertenece a exactamente un taller | `taller_id NOT NULL` + FK |
| RN-02 | Ningún registro referencia datos de otro taller | FK compuesta `(padre_id, taller_id)` → `UNIQUE (id, taller_id)` |
| RN-03 | Un usuario pertenece a un solo taller; el email es único global y se guarda en minúsculas | FK + `UNIQUE (email)` + CHECK |
| RN-04 | El margen del taller está entre 0 y 200 % | CHECK |
| RN-05 | Los talleres no modifican catálogos ni precios maestros | privilegios (sin `INSERT/UPDATE/DELETE`) |

### Vehículo
| Id | Regla | Mecanismo |
|---|---|---|
| RN-10 | VIN opcional; si existe cumple `^[A-HJ-NPR-Z0-9]{17}$` (sin I, O, Q) | CHECK |
| RN-11 | Patente en mayúsculas, formato `AA1234` o `BBBB12` | CHECK |
| RN-12 | Patente obligatoria mientras el vehículo no esté anonimizado | CHECK |
| RN-13 | Sin VIN, el motor es obligatorio (modelo + año + motor identifican técnicamente) | CHECK |
| RN-14 | Año entre 1981 y 2100 | CHECK con límites fijos |
| RN-15 | VIN y patente no se repiten dentro de un taller | índices únicos parciales |
| RN-16 | Un vehículo anonimizado no tiene patente ni VIN | CHECK |

### Diagnóstico
| Id | Regla | Mecanismo |
|---|---|---|
| RN-20 | `dispositivo_id` es obligatorio si y solo si el método es `obd_bluetooth` | CHECK |
| RN-21 | `kilometraje >= 0` | CHECK |
| RN-22 | Un DTC aparece una sola vez por sesión | PK `(sesion_id, dtc_id)` |
| RN-23 | El código DTC cumple `^[PCBU][0-3][0-9A-F]{3}$` y existe en el catálogo | CHECK + FK |
| RN-24 | La MAC del dispositivo es válida y única en el taller | tipo `macaddr` + UNIQUE |
| RN-25 | La sesión queda a nombre del usuario que la crea | política RLS `WITH CHECK` (`usuario_id` = contexto) |

### Estados de atención
| Id | Regla | Mecanismo |
|---|---|---|
| RN-30 | Transiciones válidas: pendiente→cotizado, pendiente→cancelado, cotizado→completado, cotizado→cancelado | trigger `BEFORE UPDATE OF estado` |
| RN-31 | `completado` y `cancelado` son terminales | mismo trigger |
| RN-32 | `cotizado` y `completado` exigen una cotización vigente cerrada | mismo trigger |
| RN-33 | Los timestamps de estado son coherentes con el estado y solo los fija el trigger | CHECK + privilegios por columna |
| RN-34 | Una sesión terminal no admite cotizaciones nuevas | trigger en `cotizacion` |

### Repuestos y matriz
| Id | Regla | Mecanismo |
|---|---|---|
| RN-40 | Un repuesto pertenece a un único componente | FK `NOT NULL` |
| RN-41 | `durabilidad_estimada_km > 0`, `precio_referencia >= 0` | CHECK |
| RN-42 | No se repite `(componente, marca, codigo_fabricante)` | UNIQUE |
| RN-43 | La matriz compara repuestos **del mismo componente**, ordenados genuino → oem → generico, precio, `id` | consulta |
| RN-44 | Con vehículo, solo se muestran repuestos compatibles con su modelo y año | consulta sobre `compatibilidad_repuesto` |
| RN-45 | `precio_venta = ROUND(precio_referencia × (1 + margen_pct / 100))` | consulta y trigger del detalle |
| RN-46 | En compatibilidad, `anio_desde <= anio_hasta` | CHECK |

### Cotizaciones
| Id | Regla | Mecanismo |
|---|---|---|
| RN-50 | Las revisiones de una sesión se numeran sin repetir | `UNIQUE (sesion_id, numero_revision)` |
| RN-51 | A lo más una cotización vigente por sesión | índice único parcial `WHERE vigente` |
| RN-52 | A lo más un borrador (abierta) por sesión | índice único parcial `WHERE cerrada_en IS NULL` |
| RN-53 | Solo una cotización cerrada puede ser vigente | CHECK |
| RN-54 | El total existe si y solo si la cotización está cerrada | CHECK `(cerrada_en IS NULL) = (total IS NULL)` |
| RN-55 | Una cotización cerrada y su detalle son inmutables | triggers |
| RN-56 | Los precios del detalle los fija el sistema, no el cliente | trigger `BEFORE INSERT` (*snapshot*) |
| RN-57 | Reintentar con la misma clave de idempotencia devuelve la misma cotización | `UNIQUE (taller_id, clave_idempotencia)` + `ON CONFLICT` |
| RN-58 | `cantidad > 0`; un repuesto aparece una vez por cotización | CHECK + PK `(cotizacion_id, repuesto_id)` |
| RN-59 | Cambiar el precio maestro no altera cotizaciones existentes | *snapshot* en el detalle |

### Privacidad
| Id | Regla | Mecanismo |
|---|---|---|
| RN-60 | No se almacena RUT; el identificador es un HMAC de 32 bytes | diseño + CHECK de largo |
| RN-61 | Supresión con atenciones dentro del plazo de retención → `bloqueado` hasta una fecha | `fn_solicitar_supresion_titular` |
| RN-62 | Supresión sin retención pendiente, o bloqueo vencido → anonimización irreversible | `fn_anonimizar_titular`, `fn_anonimizar_vencidos` |
| RN-63 | Un titular anonimizado no conserva nombre, contacto ni HMAC; sus vehículos pierden patente y VIN | función + CHECK |
| RN-64 | El mecánico no ve titulares ni vehículos bloqueados o anonimizados | políticas RLS |
| RN-65 | A lo más un consentimiento activo por titular y finalidad | índice único parcial |

### Auditoría y borrado
| Id | Regla | Mecanismo |
|---|---|---|
| RN-70 | La auditoría solo admite inserciones | `REVOKE` + trigger |
| RN-71 | La auditoría no contiene datos personales ni secretos | lista de columnas excluidas (`TG_ARGV`) |
| RN-72 | No se borran historiales: se cancela, se desactiva o se anonimiza | sin privilegio `DELETE` + `ON DELETE RESTRICT` |

## 1.7 Operaciones atómicas

| Operación | Por qué debe ser una transacción |
|---|---|
| Crear sesión con sus fallas | una sesión sin DTC, o DTC sin sesión, no tiene sentido |
| Cerrar cotización | sumar detalle, congelar total, encender la vigente y apagar la anterior: todo o nada |
| Cambiar estado | validar la transición, fijar el timestamp y auditar |
| Supresión / anonimización | titular y todos sus vehículos cambian juntos; a medias quedaría un dato personal expuesto |

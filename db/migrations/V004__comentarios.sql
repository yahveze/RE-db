-- =============================================================================
-- V004 - Diccionario de datos: COMMENT ON TABLE / COLUMN para todas las tablas.
-- docs/modelo/05_diccionario_datos.md se GENERA desde estos comentarios
-- (db/scripts/diccionario.sh), de modo que no puede desalinearse del esquema.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Tipos
-- ----------------------------------------------------------------------------
COMMENT ON TYPE tipo_rol_usuario IS 'Rol de un usuario dentro de su taller; determina el rol de grupo PostgreSQL que asume el backend.';
COMMENT ON TYPE tipo_estado_atencion IS 'Estado de una sesion de diagnostico. completado y cancelado son terminales.';
COMMENT ON TYPE tipo_severidad IS 'Severidad de una falla.';
COMMENT ON TYPE tipo_perfil_repuesto IS 'Perfil comercial del repuesto. Orden de presentacion fijo: genuino, oem, generico.';
COMMENT ON TYPE tipo_nivel_riesgo IS 'Riesgo estimado de usar un repuesto.';
COMMENT ON TYPE tipo_metodo_ingreso IS 'Como se ingresaron los DTC de una sesion.';
COMMENT ON TYPE tipo_resultado_auditoria IS 'Resultado de la operacion auditada.';
COMMENT ON TYPE tipo_operacion_auditoria IS 'Tipo de operacion registrada en la auditoria.';
COMMENT ON TYPE tipo_estado_dispositivo IS 'Estado operativo de un dispositivo de diagnostico. baja reemplaza al borrado fisico.';
COMMENT ON TYPE tipo_tema_visual IS 'Tema de la interfaz configurado por el taller.';
COMMENT ON TYPE tipo_estado_tratamiento IS 'Estado del tratamiento de los datos personales de un titular.';
COMMENT ON TYPE tipo_finalidad_tratamiento IS 'Finalidad para la que se otorga un consentimiento.';
COMMENT ON TYPE tipo_solicitud_derecho IS 'Derecho que ejerce el titular en una solicitud.';
COMMENT ON TYPE tipo_estado_solicitud IS 'Estado de tramitacion de una solicitud de derechos.';

-- ----------------------------------------------------------------------------
-- Catalogos globales
-- ----------------------------------------------------------------------------
COMMENT ON TABLE marca_vehiculo IS 'Catalogo global de marcas de vehiculos. Solo lectura para los talleres.';
COMMENT ON COLUMN marca_vehiculo.id IS 'Identificador interno. Nunca se expone por la API.';
COMMENT ON COLUMN marca_vehiculo.id_publico IS 'Identificador publico que expone la API.';
COMMENT ON COLUMN marca_vehiculo.nombre IS 'Nombre de la marca. Unico.';
COMMENT ON COLUMN marca_vehiculo.creado_en IS 'Fecha de creacion del registro.';

COMMENT ON TABLE modelo_vehiculo IS 'Catalogo global de modelos. Normaliza la dependencia modelo -> marca.';
COMMENT ON COLUMN modelo_vehiculo.id IS 'Identificador interno. Nunca se expone por la API.';
COMMENT ON COLUMN modelo_vehiculo.id_publico IS 'Identificador publico que expone la API.';
COMMENT ON COLUMN modelo_vehiculo.marca_vehiculo_id IS 'Marca a la que pertenece el modelo.';
COMMENT ON COLUMN modelo_vehiculo.nombre IS 'Nombre del modelo. Unico dentro de su marca.';
COMMENT ON COLUMN modelo_vehiculo.creado_en IS 'Fecha de creacion del registro.';

COMMENT ON TABLE dtc_catalogo IS 'Catalogo global de codigos de falla OBD-II (DTC).';
COMMENT ON COLUMN dtc_catalogo.id IS 'Identificador interno. La API identifica el DTC por su codigo.';
COMMENT ON COLUMN dtc_catalogo.codigo IS 'Codigo DTC, por ejemplo P0301. Formato ^[PCBU][0-3][0-9A-F]{3}$. Unico.';
COMMENT ON COLUMN dtc_catalogo.descripcion IS 'Descripcion de la falla.';
COMMENT ON COLUMN dtc_catalogo.severidad_sugerida IS 'Severidad propuesta por el catalogo; valor inicial de falla_sesion.severidad.';
COMMENT ON COLUMN dtc_catalogo.creado_en IS 'Fecha de creacion del registro.';

COMMENT ON TABLE componente_repuesto IS 'Catalogo global de componentes (pieza funcional que se reemplaza). La matriz compara repuestos del mismo componente.';
COMMENT ON COLUMN componente_repuesto.id IS 'Identificador interno. Nunca se expone por la API.';
COMMENT ON COLUMN componente_repuesto.id_publico IS 'Identificador publico que expone la API.';
COMMENT ON COLUMN componente_repuesto.nombre IS 'Nombre del componente, por ejemplo Bujia. Unico.';
COMMENT ON COLUMN componente_repuesto.descripcion IS 'Descripcion opcional del componente.';
COMMENT ON COLUMN componente_repuesto.creado_en IS 'Fecha de creacion del registro.';

COMMENT ON TABLE dtc_componente IS 'Relacion N:M: que componentes pueden causar un DTC. PK compuesta natural.';
COMMENT ON COLUMN dtc_componente.dtc_id IS 'DTC del catalogo.';
COMMENT ON COLUMN dtc_componente.componente_id IS 'Componente asociado al DTC.';

COMMENT ON TABLE repuesto IS 'Catalogo global de repuestos. Cada repuesto pertenece a un componente y tiene un perfil y un precio maestro.';
COMMENT ON COLUMN repuesto.id IS 'Identificador interno. Nunca se expone por la API.';
COMMENT ON COLUMN repuesto.id_publico IS 'Identificador publico que expone la API.';
COMMENT ON COLUMN repuesto.componente_id IS 'Componente al que pertenece el repuesto.';
COMMENT ON COLUMN repuesto.perfil IS 'Perfil comercial: genuino, oem o generico.';
COMMENT ON COLUMN repuesto.marca IS 'Marca del repuesto. Texto y no catalogo: no existe atributo que dependa de la marca.';
COMMENT ON COLUMN repuesto.nombre IS 'Nombre comercial del repuesto.';
COMMENT ON COLUMN repuesto.codigo_fabricante IS 'Numero de parte del fabricante. Unico junto con componente y marca.';
COMMENT ON COLUMN repuesto.durabilidad_estimada_km IS 'Durabilidad estimada en kilometros. Mayor que cero.';
COMMENT ON COLUMN repuesto.riesgo IS 'Nivel de riesgo estimado del repuesto.';
COMMENT ON COLUMN repuesto.precio_referencia IS 'Precio maestro (costo) en la unidad minima de la moneda. Lo mantiene solo la plataforma.';
COMMENT ON COLUMN repuesto.disponible IS 'Si puede cotizarse. Un repuesto no se borra: se marca no disponible.';
COMMENT ON COLUMN repuesto.creado_en IS 'Fecha de creacion del registro.';
COMMENT ON COLUMN repuesto.actualizado_en IS 'Fecha de la ultima modificacion. La mantiene un trigger.';

COMMENT ON TABLE compatibilidad_repuesto IS 'Relacion N:M: con que modelos y rango de anios es compatible un repuesto.';
COMMENT ON COLUMN compatibilidad_repuesto.repuesto_id IS 'Repuesto compatible.';
COMMENT ON COLUMN compatibilidad_repuesto.modelo_vehiculo_id IS 'Modelo de vehiculo con el que es compatible.';
COMMENT ON COLUMN compatibilidad_repuesto.anio_desde IS 'Primer anio del rango de compatibilidad (inclusive).';
COMMENT ON COLUMN compatibilidad_repuesto.anio_hasta IS 'Ultimo anio del rango de compatibilidad (inclusive).';

COMMENT ON VIEW v_dtc_repuesto IS 'Relacion DTC <-> repuesto derivada de dtc_componente y repuesto. Es vista para evitar redundancia y anomalias de actualizacion.';
COMMENT ON COLUMN v_dtc_repuesto.dtc_id IS 'DTC del catalogo.';
COMMENT ON COLUMN v_dtc_repuesto.componente_id IS 'Componente que vincula el DTC con el repuesto.';
COMMENT ON COLUMN v_dtc_repuesto.repuesto_id IS 'Repuesto que resuelve el DTC a traves de su componente.';

-- ----------------------------------------------------------------------------
-- Multi-taller
-- ----------------------------------------------------------------------------
COMMENT ON TABLE taller IS 'Taller mecanico: unidad de aislamiento de datos (inquilino). Agregar un taller es un INSERT.';
COMMENT ON COLUMN taller.id IS 'Identificador interno. Es el valor de app.taller_id en el contexto de la peticion.';
COMMENT ON COLUMN taller.id_publico IS 'Identificador publico que expone la API.';
COMMENT ON COLUMN taller.nombre IS 'Nombre del taller.';
COMMENT ON COLUMN taller.activo IS 'Baja logica del taller. Un taller inactivo no puede autenticar usuarios.';
COMMENT ON COLUMN taller.creado_en IS 'Fecha de creacion del registro.';
COMMENT ON COLUMN taller.actualizado_en IS 'Fecha de la ultima modificacion. La mantiene un trigger.';

COMMENT ON TABLE taller_configuracion IS 'Parametros del taller (1:1). Separada de taller por privilegios: el administrador la modifica.';
COMMENT ON COLUMN taller_configuracion.taller_id IS 'Taller al que pertenece la configuracion. Es la clave primaria.';
COMMENT ON COLUMN taller_configuracion.moneda IS 'Codigo ISO 4217 de la moneda del taller. Por defecto CLP.';
COMMENT ON COLUMN taller_configuracion.tema IS 'Tema visual de la interfaz.';
COMMENT ON COLUMN taller_configuracion.margen_pct IS 'Margen (markup sobre costo) en porcentaje, de 0 a 200. precio_venta = ROUND(precio_referencia * (1 + margen_pct / 100)).';
COMMENT ON COLUMN taller_configuracion.retencion_anios IS 'Anios de conservacion de datos tras la ultima atencion antes de anonimizar. Supuesto a validar con asesoria legal.';
COMMENT ON COLUMN taller_configuracion.actualizado_en IS 'Fecha de la ultima modificacion. La mantiene un trigger.';

COMMENT ON TABLE usuario IS 'Persona que opera el sistema. Pertenece a un solo taller.';
COMMENT ON COLUMN usuario.id IS 'Identificador interno. Es el valor de app.usuario_id en el contexto de la peticion.';
COMMENT ON COLUMN usuario.id_publico IS 'Identificador publico que expone la API.';
COMMENT ON COLUMN usuario.taller_id IS 'Taller al que pertenece el usuario.';
COMMENT ON COLUMN usuario.email IS 'Email de inicio de sesion, en minusculas. Unico global. Dato personal: excluido de la auditoria.';
COMMENT ON COLUMN usuario.nombre IS 'Nombre del usuario. Dato personal: excluido de la auditoria.';
COMMENT ON COLUMN usuario.rol IS 'Rol del usuario: admin, mecanico o auditor.';
COMMENT ON COLUMN usuario.activo IS 'Baja logica. Un usuario inactivo no puede iniciar sesion.';
COMMENT ON COLUMN usuario.creado_en IS 'Fecha de creacion del registro.';
COMMENT ON COLUMN usuario.actualizado_en IS 'Fecha de la ultima modificacion. La mantiene un trigger.';

COMMENT ON TABLE usuario_credencial IS 'Credencial del usuario (1:1). Ningun rol de grupo tiene acceso: solo funciones SECURITY DEFINER. Sin trigger de auditoria.';
COMMENT ON COLUMN usuario_credencial.usuario_id IS 'Usuario dueno de la credencial. Es la clave primaria.';
COMMENT ON COLUMN usuario_credencial.hash_contrasena IS 'Hash bcrypt de la contrasena (crypt con gen_salt bf, costo 10). Nunca sale de la base.';
COMMENT ON COLUMN usuario_credencial.intentos_fallidos IS 'Intentos fallidos consecutivos de inicio de sesion.';
COMMENT ON COLUMN usuario_credencial.bloqueado_hasta IS 'Momento hasta el que la cuenta rechaza inicios de sesion por exceso de intentos.';
COMMENT ON COLUMN usuario_credencial.ultimo_login_en IS 'Momento del ultimo inicio de sesion exitoso.';
COMMENT ON COLUMN usuario_credencial.actualizado_en IS 'Fecha de la ultima modificacion. La mantiene un trigger.';

-- ----------------------------------------------------------------------------
-- Privacidad
-- ----------------------------------------------------------------------------
COMMENT ON TABLE titular IS 'Persona natural titular de vehiculos. Dato personal, no es usuario del sistema. Pertenece a un taller. Sin RUT.';
COMMENT ON COLUMN titular.id IS 'Identificador interno. Nunca se expone por la API.';
COMMENT ON COLUMN titular.id_publico IS 'Identificador publico que expone la API.';
COMMENT ON COLUMN titular.taller_id IS 'Taller responsable de los datos del titular.';
COMMENT ON COLUMN titular.nombre IS 'Nombre del titular. Obligatorio salvo anonimizado. Dato personal: excluido de la auditoria.';
COMMENT ON COLUMN titular.telefono IS 'Telefono de contacto, opcional. Dato personal: excluido de la auditoria.';
COMMENT ON COLUMN titular.email IS 'Email de contacto, opcional. Dato personal: excluido de la auditoria.';
COMMENT ON COLUMN titular.identificador_hmac IS 'HMAC-SHA-256 (32 bytes) de un identificador del titular, calculado por el backend con un secreto que nunca llega a la base. Excluido de la auditoria.';
COMMENT ON COLUMN titular.estado_tratamiento IS 'activo, bloqueado (conservado solo por retencion legal) o anonimizado.';
COMMENT ON COLUMN titular.bloqueado_hasta IS 'Fecha en que vence la retencion y corresponde anonimizar. Solo en estado bloqueado.';
COMMENT ON COLUMN titular.anonimizado_en IS 'Momento de la anonimizacion irreversible.';
COMMENT ON COLUMN titular.creado_en IS 'Fecha de creacion del registro.';
COMMENT ON COLUMN titular.actualizado_en IS 'Fecha de la ultima modificacion. La mantiene un trigger.';

COMMENT ON TABLE consentimiento_titular IS 'Consentimientos del titular por finalidad. Revocar no borra la fila: queda la evidencia.';
COMMENT ON COLUMN consentimiento_titular.id IS 'Identificador interno.';
COMMENT ON COLUMN consentimiento_titular.taller_id IS 'Taller del titular (desnormalizacion protegida por FK compuesta).';
COMMENT ON COLUMN consentimiento_titular.titular_id IS 'Titular que otorga el consentimiento.';
COMMENT ON COLUMN consentimiento_titular.finalidad IS 'Finalidad consentida.';
COMMENT ON COLUMN consentimiento_titular.version_terminos IS 'Version del texto de terminos que acepto el titular.';
COMMENT ON COLUMN consentimiento_titular.canal IS 'Canal por el que se otorgo: presencial, app, web o telefono.';
COMMENT ON COLUMN consentimiento_titular.otorgado_en IS 'Momento en que se otorgo.';
COMMENT ON COLUMN consentimiento_titular.revocado_en IS 'Momento en que se revoco. Nulo mientras esta activo.';

COMMENT ON TABLE solicitud_derecho_titular IS 'Solicitudes de ejercicio de derechos del titular (acceso, rectificacion, supresion, oposicion, portabilidad, bloqueo).';
COMMENT ON COLUMN solicitud_derecho_titular.id IS 'Identificador interno. Nunca se expone por la API.';
COMMENT ON COLUMN solicitud_derecho_titular.id_publico IS 'Identificador publico que expone la API.';
COMMENT ON COLUMN solicitud_derecho_titular.taller_id IS 'Taller del titular (desnormalizacion protegida por FK compuesta).';
COMMENT ON COLUMN solicitud_derecho_titular.titular_id IS 'Titular que presenta la solicitud.';
COMMENT ON COLUMN solicitud_derecho_titular.tipo IS 'Derecho que se ejerce.';
COMMENT ON COLUMN solicitud_derecho_titular.estado IS 'Estado de tramitacion.';
COMMENT ON COLUMN solicitud_derecho_titular.usuario_responsable_id IS 'Usuario que gestiona la solicitud. Opcional.';
COMMENT ON COLUMN solicitud_derecho_titular.recibida_en IS 'Momento en que se recibio la solicitud.';
COMMENT ON COLUMN solicitud_derecho_titular.resuelta_en IS 'Momento de la resolucion. No nulo si y solo si el estado es resuelta o rechazada.';
COMMENT ON COLUMN solicitud_derecho_titular.actualizado_en IS 'Fecha de la ultima modificacion. La mantiene un trigger.';

-- ----------------------------------------------------------------------------
-- Operacion
-- ----------------------------------------------------------------------------
COMMENT ON TABLE vehiculo IS 'Vehiculo atendido por un taller. El mismo vehiculo fisico en dos talleres son dos filas.';
COMMENT ON COLUMN vehiculo.id IS 'Identificador interno. Nunca se expone por la API.';
COMMENT ON COLUMN vehiculo.id_publico IS 'Identificador publico que expone la API.';
COMMENT ON COLUMN vehiculo.taller_id IS 'Taller que registro el vehiculo.';
COMMENT ON COLUMN vehiculo.titular_id IS 'Titular del vehiculo. Opcional.';
COMMENT ON COLUMN vehiculo.modelo_vehiculo_id IS 'Modelo del vehiculo; la marca se obtiene del modelo.';
COMMENT ON COLUMN vehiculo.anio IS 'Anio del vehiculo, entre 1981 y 2100.';
COMMENT ON COLUMN vehiculo.motor IS 'Descripcion del motor. Obligatorio si no hay VIN.';
COMMENT ON COLUMN vehiculo.vin IS 'Numero de identificacion del vehiculo (17 caracteres, sin I, O ni Q). Opcional. Dato personal indirecto: excluido de la auditoria.';
COMMENT ON COLUMN vehiculo.patente IS 'Patente chilena en mayusculas (AA1234 o BBBB12). Obligatoria salvo anonimizado. Dato personal indirecto: excluido de la auditoria.';
COMMENT ON COLUMN vehiculo.anonimizado_en IS 'Momento en que se anonimizo: patente y VIN pasan a nulo.';
COMMENT ON COLUMN vehiculo.creado_en IS 'Fecha de creacion del registro.';
COMMENT ON COLUMN vehiculo.actualizado_en IS 'Fecha de la ultima modificacion. La mantiene un trigger.';

COMMENT ON TABLE dispositivo_diagnostico IS 'Escaner OBD-II Bluetooth registrado por un taller.';
COMMENT ON COLUMN dispositivo_diagnostico.id IS 'Identificador interno. Nunca se expone por la API.';
COMMENT ON COLUMN dispositivo_diagnostico.id_publico IS 'Identificador publico que expone la API.';
COMMENT ON COLUMN dispositivo_diagnostico.taller_id IS 'Taller dueno del dispositivo.';
COMMENT ON COLUMN dispositivo_diagnostico.mac IS 'Direccion MAC Bluetooth. El tipo macaddr la valida y normaliza. Unica por taller.';
COMMENT ON COLUMN dispositivo_diagnostico.estado IS 'activo, inactivo o baja.';
COMMENT ON COLUMN dispositivo_diagnostico.fabricante IS 'Fabricante del dispositivo.';
COMMENT ON COLUMN dispositivo_diagnostico.modelo IS 'Modelo del dispositivo.';
COMMENT ON COLUMN dispositivo_diagnostico.firmware IS 'Version de firmware.';
COMMENT ON COLUMN dispositivo_diagnostico.creado_en IS 'Fecha de creacion del registro.';
COMMENT ON COLUMN dispositivo_diagnostico.actualizado_en IS 'Fecha de la ultima modificacion. La mantiene un trigger.';

COMMENT ON TABLE sesion_diagnostico IS 'Atencion: un diagnostico de un vehiculo en un taller. Lleva el estado de la atencion.';
COMMENT ON COLUMN sesion_diagnostico.id IS 'Identificador interno. Nunca se expone por la API.';
COMMENT ON COLUMN sesion_diagnostico.id_publico IS 'Identificador publico que expone la API.';
COMMENT ON COLUMN sesion_diagnostico.taller_id IS 'Taller donde se realiza la atencion.';
COMMENT ON COLUMN sesion_diagnostico.vehiculo_id IS 'Vehiculo diagnosticado.';
COMMENT ON COLUMN sesion_diagnostico.usuario_id IS 'Mecanico que realiza la atencion.';
COMMENT ON COLUMN sesion_diagnostico.dispositivo_id IS 'Dispositivo usado. Obligatorio si y solo si el metodo es obd_bluetooth.';
COMMENT ON COLUMN sesion_diagnostico.metodo_ingreso IS 'Como se ingresaron los DTC: obd_bluetooth o manual.';
COMMENT ON COLUMN sesion_diagnostico.kilometraje IS 'Kilometraje del vehiculo al momento de la atencion.';
COMMENT ON COLUMN sesion_diagnostico.estado IS 'pendiente, cotizado, completado o cancelado. Las transiciones las valida un trigger.';
COMMENT ON COLUMN sesion_diagnostico.iniciada_en IS 'Momento de inicio de la sesion. Clave del historial y de la paginacion.';
COMMENT ON COLUMN sesion_diagnostico.cotizada_en IS 'Momento en que paso a cotizado. Lo fija el trigger de estados.';
COMMENT ON COLUMN sesion_diagnostico.completada_en IS 'Momento en que paso a completado. Lo fija el trigger de estados.';
COMMENT ON COLUMN sesion_diagnostico.cancelada_en IS 'Momento en que paso a cancelado. Lo fija el trigger de estados.';
COMMENT ON COLUMN sesion_diagnostico.version IS 'Contador para control optimista de concurrencia. Lo incrementa un trigger en cada UPDATE.';
COMMENT ON COLUMN sesion_diagnostico.actualizado_en IS 'Fecha de la ultima modificacion. La mantiene un trigger.';

COMMENT ON TABLE falla_sesion IS 'Relacion N:M: DTC detectados en una sesion. PK compuesta natural (sesion_id, dtc_id).';
COMMENT ON COLUMN falla_sesion.sesion_id IS 'Sesion en la que se detecto la falla.';
COMMENT ON COLUMN falla_sesion.dtc_id IS 'DTC detectado.';
COMMENT ON COLUMN falla_sesion.taller_id IS 'Taller de la sesion (desnormalizacion protegida por FK compuesta; simplifica RLS).';
COMMENT ON COLUMN falla_sesion.severidad IS 'Severidad observada en esta sesion; puede diferir de la sugerida por el catalogo.';
COMMENT ON COLUMN falla_sesion.freeze_frame IS 'Datos de freeze frame del escaner, opcional. Objeto JSON opaco para el modelo. Excluido de la auditoria.';
COMMENT ON COLUMN falla_sesion.creado_en IS 'Fecha de creacion del registro.';

-- ----------------------------------------------------------------------------
-- Cotizacion
-- ----------------------------------------------------------------------------
COMMENT ON TABLE cotizacion IS 'Revision numerada de la cotizacion de una sesion. Abierta mientras cerrada_en es nulo; cerrada es inmutable.';
COMMENT ON COLUMN cotizacion.id IS 'Identificador interno. Nunca se expone por la API.';
COMMENT ON COLUMN cotizacion.id_publico IS 'Identificador publico que expone la API.';
COMMENT ON COLUMN cotizacion.taller_id IS 'Taller de la sesion (desnormalizacion protegida por FK compuesta).';
COMMENT ON COLUMN cotizacion.sesion_id IS 'Sesion que se cotiza.';
COMMENT ON COLUMN cotizacion.numero_revision IS 'Numero correlativo de la revision dentro de la sesion. Lo asigna un trigger.';
COMMENT ON COLUMN cotizacion.vigente IS 'Si es la cotizacion valida de la sesion. A lo mas una por sesion, y solo si esta cerrada.';
COMMENT ON COLUMN cotizacion.cerrada_en IS 'Momento del cierre. Nulo = abierta (borrador).';
COMMENT ON COLUMN cotizacion.total IS 'Suma de cantidad * precio_unitario del detalle. Se calcula y congela al cerrar; nulo mientras esta abierta.';
COMMENT ON COLUMN cotizacion.moneda IS 'Moneda de la cotizacion, copiada de la configuracion del taller al crearla.';
COMMENT ON COLUMN cotizacion.clave_idempotencia IS 'UUID generado por el cliente; reintentar con la misma clave devuelve la misma cotizacion.';
COMMENT ON COLUMN cotizacion.version IS 'Contador para control optimista de concurrencia. Lo incrementa un trigger en cada UPDATE.';
COMMENT ON COLUMN cotizacion.creado_en IS 'Fecha de creacion del registro.';
COMMENT ON COLUMN cotizacion.actualizado_en IS 'Fecha de la ultima modificacion. La mantiene un trigger.';

COMMENT ON TABLE cotizacion_detalle IS 'Lineas de una cotizacion. Guarda un snapshot del repuesto y del margen: desnormalizacion intencional.';
COMMENT ON COLUMN cotizacion_detalle.cotizacion_id IS 'Cotizacion a la que pertenece la linea.';
COMMENT ON COLUMN cotizacion_detalle.repuesto_id IS 'Repuesto cotizado. Un repuesto aparece una vez por cotizacion.';
COMMENT ON COLUMN cotizacion_detalle.taller_id IS 'Taller de la cotizacion (desnormalizacion protegida por FK compuesta; simplifica RLS).';
COMMENT ON COLUMN cotizacion_detalle.cantidad IS 'Unidades cotizadas. Mayor que cero. Unico dato modificable mientras la cotizacion esta abierta.';
COMMENT ON COLUMN cotizacion_detalle.nombre_snapshot IS 'Nombre del repuesto al momento de cotizar. Lo llena un trigger.';
COMMENT ON COLUMN cotizacion_detalle.marca_snapshot IS 'Marca del repuesto al momento de cotizar. La llena un trigger.';
COMMENT ON COLUMN cotizacion_detalle.perfil_snapshot IS 'Perfil del repuesto al momento de cotizar. Lo llena un trigger.';
COMMENT ON COLUMN cotizacion_detalle.precio_referencia_snapshot IS 'Precio maestro del repuesto al momento de cotizar. Lo llena un trigger.';
COMMENT ON COLUMN cotizacion_detalle.margen_pct_snapshot IS 'Margen del taller al momento de cotizar. Lo llena un trigger.';
COMMENT ON COLUMN cotizacion_detalle.precio_unitario IS 'Precio de venta unitario = ROUND(precio_referencia_snapshot * (1 + margen_pct_snapshot / 100)). Lo calcula un trigger.';
COMMENT ON COLUMN cotizacion_detalle.creado_en IS 'Fecha de creacion del registro.';

-- ----------------------------------------------------------------------------
-- Auditoria
-- ----------------------------------------------------------------------------
COMMENT ON TABLE auditoria_operacion IS 'Bitacora append-only de operaciones. Sin claves foraneas. No contiene datos personales ni secretos.';
COMMENT ON COLUMN auditoria_operacion.id IS 'Identificador interno, correlativo.';
COMMENT ON COLUMN auditoria_operacion.ocurrido_en IS 'Momento real de la operacion (clock_timestamp).';
COMMENT ON COLUMN auditoria_operacion.taller_id IS 'Taller afectado. Valor, no FK. Nulo si no se conoce (login de email inexistente, catalogos).';
COMMENT ON COLUMN auditoria_operacion.usuario_id IS 'Usuario de la aplicacion que origino la operacion (app.usuario_id). Valor, no FK.';
COMMENT ON COLUMN auditoria_operacion.rol IS 'Rol PostgreSQL efectivo de la peticion (el asumido con SET LOCAL ROLE o, si no hay, el de sesion).';
COMMENT ON COLUMN auditoria_operacion.operacion IS 'INSERT, UPDATE, DELETE, LOGIN o LOGIN_FALLIDO.';
COMMENT ON COLUMN auditoria_operacion.tabla IS 'Tabla afectada. Nulo en operaciones de login.';
COMMENT ON COLUMN auditoria_operacion.registro_id IS 'id de la fila afectada. Nulo en tablas de clave compuesta (la clave va en los datos).';
COMMENT ON COLUMN auditoria_operacion.datos_anteriores IS 'Fila antes de la operacion, sin las columnas sensibles excluidas.';
COMMENT ON COLUMN auditoria_operacion.datos_nuevos IS 'Fila despues de la operacion, sin las columnas sensibles excluidas.';
COMMENT ON COLUMN auditoria_operacion.ip_origen IS 'IP del cliente informada por el backend (app.ip_origen).';
COMMENT ON COLUMN auditoria_operacion.resultado IS 'exito, fallo o denegado.';
COMMENT ON COLUMN auditoria_operacion.request_id IS 'Identificador de la peticion para correlacionar con los logs de la API (app.request_id).';

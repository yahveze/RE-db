-- =============================================================================
-- V001 - Tipos enumerados.
-- Se ejecuta con SET ROLE app_owner (propietario de los tipos).
-- Conjuntos cerrados que la app conoce; agregar un valor es
-- ALTER TYPE ... ADD VALUE, quitar o renombrar exige migracion.
-- =============================================================================

CREATE TYPE tipo_rol_usuario AS ENUM ('admin', 'mecanico', 'auditor');

CREATE TYPE tipo_estado_atencion AS ENUM ('pendiente', 'cotizado', 'completado', 'cancelado');

CREATE TYPE tipo_severidad AS ENUM ('baja', 'media', 'alta', 'critica');

-- El orden de declaracion coincide con el de presentacion, pero las consultas
-- ordenan con CASE explicito para no depender de el.
CREATE TYPE tipo_perfil_repuesto AS ENUM ('genuino', 'oem', 'generico');

CREATE TYPE tipo_nivel_riesgo AS ENUM ('bajo', 'medio', 'alto');

CREATE TYPE tipo_metodo_ingreso AS ENUM ('obd_bluetooth', 'manual');

CREATE TYPE tipo_resultado_auditoria AS ENUM ('exito', 'fallo', 'denegado');

CREATE TYPE tipo_operacion_auditoria AS ENUM ('INSERT', 'UPDATE', 'DELETE', 'LOGIN', 'LOGIN_FALLIDO');

CREATE TYPE tipo_estado_dispositivo AS ENUM ('activo', 'inactivo', 'baja');

CREATE TYPE tipo_tema_visual AS ENUM ('claro', 'oscuro');

CREATE TYPE tipo_estado_tratamiento AS ENUM ('activo', 'bloqueado', 'anonimizado');

CREATE TYPE tipo_finalidad_tratamiento AS ENUM ('prestacion_servicio', 'contacto_seguimiento', 'marketing');

CREATE TYPE tipo_solicitud_derecho AS ENUM ('acceso', 'rectificacion', 'supresion', 'oposicion', 'portabilidad', 'bloqueo');

CREATE TYPE tipo_estado_solicitud AS ENUM ('recibida', 'en_proceso', 'resuelta', 'rechazada');

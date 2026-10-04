# 2. Modelo conceptual

Diagramas en Mermaid (se ven en GitHub, VS Code con extensión Mermaid o <https://mermaid.live>).
Notación: `||` exactamente uno · `|o` cero o uno · `o{` cero o muchos · `|{` uno o muchos.

## 2.1 Vista general

```mermaid
erDiagram
    taller ||--|| taller_configuracion : "se configura con"
    taller ||--o{ usuario : "emplea"
    usuario ||--o| usuario_credencial : "se autentica con"
    taller ||--o{ titular : "registra"
    taller ||--o{ vehiculo : "atiende"
    taller ||--o{ dispositivo_diagnostico : "posee"
    taller ||--o{ sesion_diagnostico : "realiza"

    titular |o--o{ vehiculo : "es titular de"
    titular ||--o{ consentimiento_titular : "otorga"
    titular ||--o{ solicitud_derecho_titular : "presenta"
    usuario |o--o{ solicitud_derecho_titular : "gestiona"

    marca_vehiculo ||--o{ modelo_vehiculo : "fabrica"
    modelo_vehiculo ||--o{ vehiculo : "clasifica"

    vehiculo ||--o{ sesion_diagnostico : "es diagnosticado en"
    usuario ||--o{ sesion_diagnostico : "atiende"
    dispositivo_diagnostico |o--o{ sesion_diagnostico : "lee los DTC de"

    sesion_diagnostico ||--o{ falla_sesion : "detecta"
    dtc_catalogo ||--o{ falla_sesion : "se presenta como"

    dtc_catalogo ||--o{ dtc_componente : "apunta a"
    componente_repuesto ||--o{ dtc_componente : "puede causar"
    componente_repuesto ||--o{ repuesto : "se reemplaza con"
    repuesto ||--o{ compatibilidad_repuesto : "sirve en"
    modelo_vehiculo ||--o{ compatibilidad_repuesto : "admite"

    sesion_diagnostico ||--o{ cotizacion : "se cotiza en"
    cotizacion ||--o{ cotizacion_detalle : "se compone de"
    repuesto ||--o{ cotizacion_detalle : "se ofrece en"
```

`auditoria_operacion` no aparece relacionada con nada: es deliberado. Guarda `taller_id`, `usuario_id`,
`tabla` y `registro_id` como **valores**, sin claves foráneas, para sobrevivir a cualquier cambio del
esquema y no bloquear ninguna operación.

## 2.2 Las tres zonas del modelo

```mermaid
flowchart LR
    subgraph G["Catálogo global · solo lectura para los talleres"]
        marca_vehiculo --> modelo_vehiculo
        dtc_catalogo --> dtc_componente
        componente_repuesto --> dtc_componente
        componente_repuesto --> repuesto
        repuesto --> compatibilidad_repuesto
        modelo_vehiculo --> compatibilidad_repuesto
    end
    subgraph T["Datos del taller · taller_id + RLS"]
        taller --> taller_configuracion
        taller --> usuario --> usuario_credencial
        taller --> titular --> vehiculo
        titular --> consentimiento_titular
        titular --> solicitud_derecho_titular
        taller --> dispositivo_diagnostico
        vehiculo --> sesion_diagnostico
        sesion_diagnostico --> falla_sesion
        sesion_diagnostico --> cotizacion --> cotizacion_detalle
    end
    subgraph A["Bitácora · sin FK"]
        auditoria_operacion
    end
    modelo_vehiculo -.-> vehiculo
    dtc_catalogo -.-> falla_sesion
    repuesto -.-> cotizacion_detalle
```

Las flechas punteadas son los únicos tres puntos donde un dato del taller referencia al catálogo global.
Las flechas van de padre a hijo.

## 2.3 Ciclo de vida de la atención

```mermaid
stateDiagram-v2
    [*] --> pendiente : se crea la sesión
    pendiente --> cotizado : existe cotización vigente cerrada
    pendiente --> cancelado
    cotizado --> completado : existe cotización vigente cerrada
    cotizado --> cancelado
    completado --> [*]
    cancelado --> [*]
```

No existe `cotizado → pendiente` ni salida desde un estado terminal. En `cotizado` se pueden crear
revisiones nuevas de la cotización; cada cierre reemplaza a la vigente.

## 2.4 Ciclo de vida de la cotización

```mermaid
stateDiagram-v2
    [*] --> abierta : INSERT (cerrada_en nulo, vigente falso, total nulo)
    abierta --> abierta : agregar, quitar o cambiar cantidad del detalle
    abierta --> vigente : fn_cerrar_cotizacion congela total y cerrada_en
    vigente --> reemplazada : se cierra una revisión posterior
    vigente --> [*]
    reemplazada --> [*]
```

"Abierta", "vigente" y "reemplazada" no son un enum: se deducen de `cerrada_en` y `vigente`
(abierta = `cerrada_en IS NULL`; vigente = cerrada y `vigente`; reemplazada = cerrada y no `vigente`).

## 2.5 Ciclo de vida del tratamiento de datos del titular

```mermaid
stateDiagram-v2
    [*] --> activo
    activo --> bloqueado : supresión solicitada con atenciones dentro del plazo de retención
    activo --> anonimizado : supresión solicitada sin retención pendiente
    bloqueado --> anonimizado : vence bloqueado_hasta
    anonimizado --> [*]
```

La anonimización es irreversible: no hay transición de salida.

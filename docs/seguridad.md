# Seguridad

Todo lo que este documento afirma sobre el comportamiento del motor está respaldado por una ejecución
real: `docs/evidencia/esquema.txt` (catálogo) y `docs/evidencia/fase2_humo.txt` (flujo completo con el
rol del backend). Las referencias `[humo §n]` apuntan a la sección de ese archivo.

## 1. Capas de defensa

| Capa | Qué impide | Dónde |
|---|---|---|
| 1. Red | conexión directa a la base | la app móvil nunca habla con PostgreSQL; puerto solo en loopback |
| 2. Rol de conexión sin privilegios | que un error del backend lea datos "por defecto" | `app_backend_user` |
| 3. RBAC (privilegios) | operaciones que el rol no debe hacer | `V007` |
| 4. RLS (políticas) | filas de otro taller o de titulares bloqueados | `V008` |
| 5. Integridad estructural | referencias cruzadas entre talleres | FK compuestas, `V003` |
| 6. Triggers | reglas de negocio aunque se use SQL directo | `V005` |
| 7. Auditoría | que un cambio no deje rastro | `V005` |

Las capas 3 a 6 son independientes: cada una se sostiene aunque falle otra.

## 2. Roles

| Rol | Login | Atributos | Para qué |
|---|---|---|---|
| `app_owner` | no | — | Propietario de tablas, tipos, vistas e índices. Ejecuta migraciones. **No se usa en ejecución.** |
| `app_funciones` | no | `BYPASSRLS` | Propietario **solo** de las 6 funciones `SECURITY DEFINER`. |
| `taller_admin` | no | — | Grupo: operaciones del administrador. |
| `taller_mecanico` | no | — | Grupo: operaciones del mecánico. |
| `taller_auditor` | no | — | Grupo: solo lectura. |
| `app_backend_user` | **sí** | `NOINHERIT` | Rol de conexión del backend. Sin privilegios sobre tablas. |

Ninguno es superusuario ni puede crear roles o bases.

### Membresías

```sql
GRANT taller_admin, taller_mecanico, taller_auditor TO app_backend_user WITH INHERIT FALSE, SET TRUE;
GRANT app_funciones TO app_owner WITH INHERIT FALSE, SET TRUE;
```

- **`SET TRUE`** permite `SET LOCAL ROLE taller_mecanico`; sin él, el comando falla.
- **`INHERIT FALSE`** hace que el backend **no** tenga los privilegios de los grupos mientras no asuma uno.
  Es lo que convierte "olvidé fijar el rol" en un error y no en una fuga.
- La segunda membresía existe por un requisito de PostgreSQL 16, comprobado en
  `docs/evidencia/fase0_experimentos.txt`: para `ALTER FUNCTION ... OWNER TO app_funciones`, quien lo
  ejecuta debe poder hacer `SET ROLE` al nuevo dueño, y el nuevo dueño debe tener `CREATE` en el esquema.
  La sintaxis `WITH INHERIT ..., SET ...` es de **PostgreSQL 16+** (validar si se cambia de versión).

### Por qué existe `app_funciones`

Con `FORCE ROW LEVEL SECURITY` **también el propietario de la tabla queda sujeto a las políticas**. Una
función `SECURITY DEFINER` propiedad de `app_owner` no podría, por ejemplo, buscar un usuario por email
durante el login: todavía no hay `app.taller_id`, así que no vería ninguna fila.

| Alternativa | Por qué se descarta |
|---|---|
| No usar `FORCE` (propietario exento) | Un despliegue que por error use `app_owner` en ejecución saltaría el aislamiento sin que nada lo advierta. |
| Dar `BYPASSRLS` a `app_owner` | El rol que es dueño de todo además vería todo: demasiado poder en un solo rol. |
| **Rol dedicado `app_funciones`** | El privilegio de saltar RLS queda confinado a 6 funciones auditables, con privilegios de tabla mínimos. |

`BYPASSRLS` no es un `GRANT`: `app_funciones` solo puede tocar las tablas que `V007` le otorga
explícitamente (`esquema.txt` §7). No puede, por ejemplo, leer cotizaciones.

## 3. Patrón de petición del backend

```sql
BEGIN;
SET LOCAL ROLE taller_mecanico;                     -- 1
SELECT set_config('app.taller_id',  $1, true);      -- 2
SELECT set_config('app.usuario_id', $2, true);      -- 3
SELECT set_config('app.ip_origen',  $3, true);      -- 4
SELECT set_config('app.request_id', $4, true);      -- 5 (opcional)
-- ... consultas de la petición ...
COMMIT;                                             -- 6
```

1. **`SET LOCAL ROLE`**: el backend asume el grupo que corresponde al rol del usuario autenticado. Desde
   aquí aplican sus privilegios (RBAC) y sus políticas (RLS).
2. **`app.taller_id`**: lo leen las políticas RLS. El tercer argumento `true` significa *local a la
   transacción*. Se usa `set_config()` y no `SET LOCAL` porque admite parámetros (`$1`).
3. **`app.usuario_id`**: lo usa la auditoría y la política que exige que la sesión quede a nombre de quien la crea.
4. **`app.ip_origen`** y 5. **`app.request_id`**: solo para auditoría.
6. **`COMMIT`** (o `ROLLBACK`): rol y variables **caducan**. La conexión vuelve al pool sin contexto.

Los valores de 2 y 3 salen de `fn_autenticar_usuario` (o del token de sesión que el backend emitió a
partir de ella), **nunca** de lo que envía el cliente.

### Por qué nunca `SET` de sesión

Con PgBouncer en *transaction pooling*, una conexión física atiende a un usuario distinto en cada
transacción. Un `SET` de sesión sobreviviría al `COMMIT` y el siguiente usuario heredaría el taller del
anterior. `SET LOCAL` y `set_config(..., true)` no pueden producir esa fuga.

### Falla cerrado

| Situación | Resultado | Evidencia |
|---|---|---|
| Consulta sin `SET LOCAL ROLE` | `permission denied` (el rol de conexión no tiene privilegios) | [humo §1a] |
| `SET LOCAL ROLE` fuera de un `BEGIN` | aviso `SET LOCAL can only be used in transaction blocks`, el rol no cambia, la consulta falla | [humo §8] |
| Rol fijado pero sin `app.taller_id` | las políticas comparan con `NULL`: cero filas | [humo §6b] |
| `app.taller_id` con texto no numérico | error de conversión: la consulta falla | [humo §6c] |

No existe una combinación de omisiones que devuelva datos de otro taller.

## 4. RBAC frente a RLS

- **RBAC** responde *¿qué operaciones puede ejecutar este rol?* → `GRANT` / `REVOKE`.
- **RLS** responde *¿sobre qué filas?* → `CREATE POLICY`.

**Ejemplo del proyecto.** Un mecánico del Taller A ejecuta `UPDATE repuesto SET precio_referencia = 1`:
lo detiene **RBAC** (`permission denied for table repuesto`, [humo §2l]); ningún mecánico de ningún taller
puede hacerlo, sin importar la fila. El mismo mecánico ejecuta
`UPDATE sesion_diagnostico SET kilometraje = 1 WHERE id = <sesión del Taller B>`: RBAC lo **permite** (los
mecánicos actualizan sesiones), y es **RLS** quien lo detiene: la fila no es visible y el resultado es
`UPDATE 0` ([humo §3a]).

RBAC sin RLS dejaría a todo mecánico ver todos los talleres. RLS sin RBAC dejaría al auditor escribir en
su propio taller. Se necesitan ambos.

## 5. Privilegios por rol

Matriz completa y real en `esquema.txt` §7 (tabla) y §8 (columna). Resumen:

| Objeto | `taller_admin` | `taller_mecanico` | `taller_auditor` |
|---|---|---|---|
| Catálogos y `v_dtc_repuesto` | leer | leer | leer |
| `taller` | leer | leer | leer |
| `taller_configuracion` | leer, modificar | leer | leer |
| `usuario` | leer, crear, modificar | leer (sin email) | leer |
| `usuario_credencial` | — | — | — |
| `titular` | leer, crear, modificar | leer, crear, modificar contacto | leer **sin identidad** |
| `consentimiento_titular` | leer, crear, revocar | leer, crear, revocar | leer |
| `solicitud_derecho_titular` | leer, crear, modificar | — | leer |
| `vehiculo` | leer, crear, modificar | leer, crear, modificar | leer |
| `dispositivo_diagnostico` | leer, crear, modificar | leer | leer |
| `sesion_diagnostico` | leer | leer, crear, modificar estado y km | leer |
| `falla_sesion` | leer | leer, crear, modificar | leer |
| `cotizacion` | leer | leer, crear, cerrar | leer |
| `cotizacion_detalle` | leer | leer, crear, modificar cantidad, **borrar** | leer |
| `auditoria_operacion` | leer | — | leer |

Puntos que merecen explicación:

- **Privilegios por columna como regla de negocio.** El mecánico puede insertar en `cotizacion_detalle`
  solo `(cotizacion_id, repuesto_id, taller_id, cantidad)`. Intentar enviar `precio_unitario` da
  `permission denied` ([humo §2e]): no puede falsear un precio aunque quiera. Igual con `estado` y
  timestamps al crear una sesión, y con `total` en la cotización.
- **Ningún `UPDATE` incluye `taller_id`.** Un registro no puede "mudarse" de taller.
- **Un solo `DELETE` en todo el modelo:** líneas de detalle, y el trigger lo rechaza si la cotización está
  cerrada. **Ningún `TRUNCATE`.** (`esquema.txt` §7, consulta de DELETE/TRUNCATE.)
- **El auditor y `SELECT *`.** Como su privilegio sobre `titular` es por columna, `SELECT * FROM titular`
  falla ([humo §4a]). La API debe pedir columnas explícitas para ese rol.
- **Mecánico y precio maestro.** Tiene lectura de `repuesto.precio_referencia` porque la matriz lo
  necesita; "sin acceso a precios maestros" se interpreta como sin escritura (tema T-11, aprobado).
- **Administrador y catálogos.** No modifica precios maestros ([humo §5e]): afectarían a otros talleres.
- **Extensiones.** Las funciones de `pgcrypto` son ejecutables por `PUBLIC` (valor por defecto de la
  extensión). No es un riesgo: sin acceso a `usuario_credencial` no hay hash contra el cual usarlas.

## 6. Políticas RLS

`ENABLE` + `FORCE` en las 12 tablas con `taller_id`, en `taller` y en `usuario_credencial`
(`esquema.txt` §9 y §13: `tablas_con_taller_id_sin_rls_forzado = 0`). 49 políticas.

Expresión de contexto, igual en todas:

```sql
taller_id = (SELECT NULLIF(current_setting('app.taller_id', true), '')::bigint)
```

| Pieza | Por qué |
|---|---|
| `current_setting(..., true)` | si la variable no existe devuelve `NULL` en lugar de error |
| `NULLIF(..., '')` | tras un `SET LOCAL`, la variable queda como cadena vacía al terminar la transacción |
| `taller_id = NULL` | nunca es verdadero → sin contexto no hay filas |
| `(SELECT ...)` | el planificador lo evalúa **una vez** por consulta (InitPlan), no una vez por fila |

Convención de nombres: `pol_<tabla>_<rol>_<operacion>`; `<rol>` es `miembros` cuando la política aplica
a los tres grupos.

### Reglas que van más allá del taller

| Regla | Política |
|---|---|
| El mecánico solo ve titulares en estado `activo` | `pol_titular_mecanico_*` |
| El mecánico no ve vehículos anonimizados ni de titulares que no puede ver | `pol_vehiculo_mecanico_*` (subconsulta sobre `titular`, que a su vez está sujeta a la política del mecánico) |
| El mecánico no opera consentimientos de titulares que no ve | `pol_consentimiento_titular_mecanico_*` |
| La sesión queda a nombre de quien la crea | `pol_sesion_diagnostico_mecanico_insert` (`usuario_id = app.usuario_id`) |
| La auditoría la leen solo administrador y auditor | `pol_auditoria_operacion_*` |
| `usuario_credencial`: RLS activo y **ninguna** política | denegado para todos salvo `app_funciones` |

Comprobado en [humo §6]: tras bloquear a un titular, el mecánico ve 0 titulares y 0 vehículos, pero la
sesión sigue en su historial (por eso `/history` usa `LEFT JOIN` hacia `vehiculo`).

**Qué no cubre RLS.** Las comprobaciones de claves foráneas omiten RLS siempre: una FK puede "ver" una
fila que el usuario no ve. Por eso el aislamiento entre talleres no descansa solo en RLS sino en las FK
compuestas (siguiente sección).

## 7. Aislamiento estructural

Las tablas padre (`usuario`, `titular`, `vehiculo`, `dispositivo_diagnostico`, `sesion_diagnostico`,
`cotizacion`) declaran `UNIQUE (id, taller_id)` y las hijas referencian `(padre_id, taller_id)`.

Una sesión del Taller B sobre un vehículo del Taller A es rechazada **por la FK**, no por RLS
([humo §3c]). Esta barrera funciona incluso para un superusuario o un rol con `BYPASSRLS`, que ignoran
las políticas.

## 8. Funciones `SECURITY DEFINER`

Las 6 pertenecen a `app_funciones`, fijan `SET search_path = pg_catalog, public, pg_temp` y no tienen
`EXECUTE` para `PUBLIC` (`esquema.txt` §5 y §6).

| Función | Quién la ejecuta | Qué valida explícitamente |
|---|---|---|
| `fn_autenticar_usuario` | `app_backend_user` | es anterior al contexto; no revela el motivo del fallo |
| `fn_establecer_contrasena` | `taller_admin` | rol = `taller_admin`, contexto presente, usuario del mismo taller |
| `fn_solicitar_supresion_titular` | `taller_admin` | rol = `taller_admin`, contexto presente, titular del mismo taller |
| `fn_anonimizar_titular` | `app_owner` (mantenimiento) | sin `EXECUTE` para roles de taller ([humo §5d]) |
| `fn_anonimizar_vencidos` | `app_owner` (mantenimiento) | sin `EXECUTE` para roles de taller |
| `fn_trg_auditar` | (trigger) | — |

Como saltan RLS, **la función es la política**: por eso cada una comprueba rol y taller a mano
([humo §5a]: fijar la contraseña de un usuario de otro taller devuelve `RE009`).

**`search_path` fijo.** Sin él, quien llama a una función definidora podría anteponer un esquema propio
con una función `crypt()` falsa y ejecutarla con los privilegios del dueño.

**`pg_temp` explícito y al final (`V010`).** Fijar el `search_path` no basta si no nombra `pg_temp`: en ese
caso PostgreSQL lo busca **primero** para tablas y tipos, y una tabla temporal con el nombre de una real la
suplanta dentro de la función. El dictamen de cierre lo comprobó (`docs/evidencia/fase7_antes.txt` B5): con
el privilegio `TEMPORARY`, un mecánico creaba una tabla temporal `auditoria_operacion` y sus escrituras
dejaban de llegar a la auditoría real. No era explotable —ningún rol de la aplicación tiene `TEMPORARY`
sobre la base—, pero era la única barrera y nadie la vigilaba. Ahora son dos y ambas están en la suite:
`pg_temp` al final en las 21 funciones (`ESQ-30`, y la prueba de sombra de `07_auditoria.sql`) y ausencia del
privilegio (`ESQ-31`). **Otorgar `TEMPORARY` a un rol de taller sigue siendo una decisión a revisar**: sin
V010 habría bastado para evadir la auditoría.

**Dentro de una función definidora `current_user` es el dueño.** El rol real de la petición se lee con
`current_setting('role')`, que conserva el valor de `SET LOCAL ROLE` (verificado en
`fase0_experimentos.txt` E2). De ahí sale la columna `rol` de la auditoría.

Las demás funciones (`fn_crear_cotizacion`, `fn_cerrar_cotizacion`, `fn_cambiar_estado_sesion`) son
`SECURITY INVOKER`: corren con los privilegios y las políticas del mecánico. No necesitan confianza.

## 9. Autenticación

Hay **dos** autenticaciones distintas que no deben mezclarse:

| | Cuenta PostgreSQL | Usuario de la app |
|---|---|---|
| Quién | `app_backend_user` | administradores, mecánicos, auditores |
| Mecanismo | SCRAM-SHA-256 (`password_encryption`) | `fn_autenticar_usuario` |
| Dónde vive el secreto | `pg_authid` | `usuario_credencial.hash_contrasena` |

### 9.1 Prototipo: `crypt()` en la base

`fn_autenticar_usuario(email, contraseña)`:

- compara con `hash = crypt(contraseña, hash)`; **nunca devuelve el hash**;
- ante credenciales inválidas **devuelve** `autenticado = false` en lugar de lanzar una excepción (una
  excepción revertiría el contador de intentos y el registro de auditoría);
- no informa el motivo (email inexistente, clave errónea, cuenta bloqueada o inactiva se ven igual) ([humo §1c]);
- si el email no existe ejecuta igualmente un `crypt()` del mismo costo, para que el tiempo de respuesta
  no delate qué emails existen;
- tras 5 fallos consecutivos bloquea la cuenta 15 minutos (constantes de la función);
- registra `LOGIN` y `LOGIN_FALLIDO` en la auditoría, sin contraseña ni email.

### 9.2 bcrypt

`crypt(contraseña, gen_salt('bf', 10))` aplica bcrypt:

- **Salt:** valor aleatorio distinto por contraseña, guardado dentro del propio hash. Dos usuarios con la
  misma contraseña tienen hashes distintos y las tablas precalculadas no sirven.
- **Costo ajustable:** `10` significa 2¹⁰ iteraciones de la derivación de clave. Subirlo en uno duplica el
  trabajo del atacante (y el del servidor en cada login). Se sube con los años a medida que el hardware mejora.
- **Límite de 72 bytes:** bcrypt ignora lo que pase del byte 72. Por eso `fn_establecer_contrasena`
  **rechaza** contraseñas más largas en vez de truncarlas en silencio.

### 9.3 Limitación honesta del prototipo

Con `crypt()` en la base, **la contraseña viaja en claro dentro de la consulta** hasta el motor. TLS la
protege en la red, pero no de los registros del propio servidor.

| Parámetro | Valor | Qué evita |
|---|---|---|
| `log_statement` | `none` | que toda sentencia se escriba en el log |
| `log_min_error_statement` | `panic` | que una sentencia que **falla** se registre con su texto |
| `log_parameter_max_length` | `0` | que los parámetros se registren junto a la sentencia |
| `log_parameter_max_length_on_error` | `0` (su valor por defecto) | lo mismo en los mensajes de error |
| `log_min_duration_statement` | `-1` (apagado) | que una consulta lenta se registre con su texto y sus literales |

Los cinco están aplicados en `docker-compose.yml` desde la Fase 6 y los vigila la suite (`OPE-02`,
`OPE-03`). Antes solo lo estaba el primero, y se comprobó la fuga: una sentencia fallida dejaba su texto
completo, con la clave literal, en el log (`docs/evidencia/fase6_antes.txt` §A4). El detalle, incluido por
qué el log de sentencias lentas queda apagado, está en `docs/operacion.md` §5.

Dos matices que la ejecución mostró:

- `pg_stat_statements` normaliza las constantes de `SELECT`, `INSERT`, `UPDATE` y `DELETE`, pero **guarda
  tal cual el texto de las sentencias de utilidad**: el `CREATE ROLE ... PASSWORD '...'` de `V000` quedaba
  legible para un superusuario (`fase6_antes.txt` §A5). Los scripts que envían claves como literal vacían
  esas estadísticas al terminar (`OPE-07`), y ningún rol de la aplicación puede leer la vista (`OPE-06`).
- Un `SELECT fn_autenticar_usuario('a@b', 'clave')` escrito con literales en vez de parámetros puede verse
  en `pg_stat_activity` mientras se ejecuta. **El backend debe usar siempre parámetros (`$1`, `$2`).**

Ninguna configuración elimina el problema de fondo: el motor recibe la contraseña. Por eso el diseño de
producción es otro.

### 9.4 Producción **[AVANZADA, solo documentado]**

El backend calcula y verifica el hash (Argon2id, o bcrypt); la base solo lo almacena y **nunca recibe la
contraseña**.

| Función | Firma | Qué hace |
|---|---|---|
| `fn_credencial_para_login(p_email text)` | devuelve `usuario_id`, `taller_id`, `rol`, `hash_contrasena`, `bloqueado_hasta`, `activo` | `SECURITY DEFINER`; `EXECUTE` **solo** para `app_backend_user`. Única vía por la que un hash sale de la base. |
| `fn_registrar_intento_login(p_usuario_id bigint, p_exito boolean)` | `void` | Actualiza `intentos_fallidos`, `bloqueado_hasta`, `ultimo_login_en` y escribe `LOGIN` o `LOGIN_FALLIDO` en la auditoría. |

Trade-off: el hash sale de la base hacia el backend (antes no salía nunca), a cambio de que la contraseña
no entre. Es el intercambio correcto: un hash Argon2id filtrado es costoso de atacar; una contraseña en un
log no lo es. Migrar no exige cambiar tablas: bcrypt y Argon2id caben en `hash_contrasena TEXT`, y los
hashes antiguos se reemplazan en el siguiente login exitoso de cada usuario.

## 10. Auditoría

`auditoria_operacion` es *append-only* y **no tiene claves foráneas**: guarda `taller_id`, `usuario_id` y
`registro_id` como valores. Un registro de auditoría debe sobrevivir a cualquier cambio del esquema y no
puede bloquear ni ser bloqueado por otra tabla.

- **Captura:** trigger genérico `fn_trg_auditar` (`AFTER INSERT OR UPDATE OR DELETE`) en 13 tablas, con
  `to_jsonb(OLD)` y `to_jsonb(NEW)`.
- **Enmascarado:** los argumentos del trigger son las columnas que se **excluyen** (ver
  `docs/privacidad.md` §7). Verificado en [humo §4e]: 0 registros con datos personales.
- **Sin trigger en `usuario_credencial`:** un hash nunca debe copiarse. El cambio de contraseña deja un
  registro manual sin datos.
- **Contexto vacío:** en semillas y migraciones no hay `app.usuario_id`; se registra el rol de sesión
  ([humo §4d], filas con rol `postgres`).
- **Sin `INSERT` directo:** ningún rol de taller puede escribir en la tabla; solo `app_funciones`.

### Inmutabilidad en dos capas

1. **Privilegios:** nadie tiene `UPDATE`, `DELETE` ni `TRUNCATE` ([humo §4f]).
2. **Triggers** `BEFORE UPDATE OR DELETE` (por fila) y `BEFORE TRUNCATE` (por sentencia) que lanzan `RE005`
   incluso para un superusuario ([humo §7a]).

### Limitaciones

- **(a) Lo denegado o revertido no deja rastro.** El trigger escribe dentro de la misma transacción: si
  la operación falla por permisos, por RLS o por un `ROLLBACK`, el registro desaparece con ella. Los
  intentos fallidos de autorización deben registrarse **desde el backend** o con `pgaudit` / logs del
  servidor. La excepción es el login, que por diseño no lanza error y sí queda registrado.
- **(b) El propietario o un superusuario pueden alterar la tabla** (`ALTER TABLE ... DISABLE TRIGGER`).
  La inmutabilidad protege contra los roles de ejecución, no contra quien administra el servidor. La única
  vía prevista para borrar es la purga por retención (`docs/operacion.md` §6), que solo puede ejecutar un
  superusuario, archiva antes de eliminar y deja su propio registro (`OPE-09` a `OPE-17`, `OPE-29` a `OPE-31`).
- **(c) [AVANZADA]** Envío a almacenamiento externo WORM o a un SIEM, y encadenamiento de hashes (cada
  registro incluye el hash del anterior) para que una alteración sea detectable.
- Un `LOGIN_FALLIDO` de un email inexistente queda con `taller_id` nulo: ningún taller lo ve.

## 11. Códigos de error

Las funciones y triggers usan `SQLSTATE` propios para que la API los traduzca sin analizar el texto:

| Código | Significado | HTTP sugerido |
|---|---|---|
| `RE001` | transición de estado inválida | 409 |
| `RE002` | falta una cotización vigente cerrada | 409 |
| `RE003` | la cotización está cerrada (inmutable) | 409 |
| `RE004` | la sesión está en estado terminal | 409 |
| `RE005` | la auditoría es inmutable | 403 |
| `RE006` | contexto o rol no autorizado | 403 |
| `RE007` | conflicto de versión (control optimista) | 409 |
| `RE008` | cotización sin detalle | 422 |
| `RE009` | registro inexistente o no visible | 404 |
| `RE010` | repuesto no disponible | 422 |
| `RE011` | contraseña fuera de los límites | 422 |
| `RE012` | columna no modificable | 422 |

`RE009` no distingue "no existe" de "existe en otro taller": no se confirma la existencia de datos ajenos.

## 12. Secretos

- Las claves viven en `.env` (ignorado por Git); `.env.example` solo tiene placeholders.
- Llegan al SQL como variables de `psql` (`:'clave_backend'`, `:'clave_demo'`), nunca escritas en un archivo.
- La contraseña de `app_backend_user` se almacena como verificador SCRAM, no en claro.
- La evidencia no contiene claves: se comprueba que estén definidas, no su valor.
- Dentro del contenedor toda conexión exige clave, también por el socket local (`pg_hba.conf` sin `trust`,
  tema T-43): los scripts la toman de las variables de entorno del contenedor, nunca de la línea de comandos.
- Ni el log del servidor ni `pg_stat_statements` contienen las claves de `.env` (`OPE-07`, `OPE-32`).
- Los respaldos se generan sin claves de roles (`pg_dumpall --no-role-passwords`), pero contienen los
  hashes bcrypt de los usuarios y datos personales: se guardan cifrados (`docs/operacion.md` §2).

## 13. Límites del modelo

1. **El backend es de confianza.** Es quien fija `app.taller_id`. Si se compromete, puede fijar el taller
   que quiera y RLS no lo detiene. RLS es **defensa en profundidad** contra errores del backend (una
   consulta sin `WHERE taller_id`), **no** un sustituto de la autorización de la API.
2. **El superusuario y `app_funciones` ignoran RLS.** Por eso las pruebas de seguridad usan
   `app_backend_user`, y por eso `app_funciones` no tiene `LOGIN`.
3. **PgBouncer no está en el prototipo.** El patrón es compatible con *transaction pooling* por
   construcción, pero no se probó contra un PgBouncer real.
4. **Sin TLS en el contenedor de desarrollo.** El puerto solo se publica en loopback; en producción la
   conexión backend → base debe exigir TLS (`hostssl` en `pg_hba.conf`). Lo que sí está aplicado es la
   autenticación: todas las reglas de `pg_hba.conf` exigen `scram-sha-256` (`docs/operacion.md` §4).
5. **Sin límite de tasa en el login** más allá del bloqueo por cuenta: el *rate limiting* por IP es del backend.
6. **Cerrar una cotización por `UPDATE` directo** (en vez de `fn_cerrar_cotizacion`) es válido y seguro
   para los datos, pero toma los bloqueos en orden cotización → sesión. Si coincide con un cambio de estado
   puede producir un *deadlock*, que PostgreSQL resuelve abortando una de las dos transacciones. La vía
   soportada es la función.

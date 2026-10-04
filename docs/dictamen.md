# Dictamen de cierre

Revisión final de la base de datos **Repuestos Exactos**, hecha con el criterio de un DBA que recibe el
proyecto para ponerlo en operación: qué se sostiene, qué no, y qué falta. Como en el resto del proyecto,
nada de lo que aquí se afirma sobre el comportamiento del motor es una opinión: sale de una ejecución.

| Evidencia | Contenido |
|---|---|
| `docs/evidencia/fase7_cierre.txt` | `make all` desde una base vacía, estado final del esquema, suite repetida, búsqueda de secretos |
| `docs/evidencia/fase7_dictamen.txt` | comprobaciones de catálogo (A1–A7) y experimentos con el rol del backend (B1–B5) |
| `docs/evidencia/fase7_antes.txt` | los mismos experimentos sobre `V000`–`V009`, antes de la corrección (captura única) |

Se regenera con `bash db/scripts/evidencia_fase7.sh` (**elimina el volumen**: empieza por `reset`). Las
referencias **[A1]**, **[B5]**… apuntan a las secciones del guion `db/tests/humo/fase7_dictamen.sql`.

## 1. Veredicto

**Apto para la entrega.** El criterio de aceptación se cumple: `reset → migrate → seed → test` termina con
código 0 sobre una base vacía, con **518 pruebas y 0 fallos**, y vuelve a pasar repetido sobre la misma
base y sobre una base reconstruida desde un respaldo.

**No apto para producción tal como está**, y el proyecto no lo pretende: es un prototipo. Lo que separa una
cosa de la otra está enumerado en §6 y ya estaba declarado en cada documento; el dictamen no encontró
ninguna limitación oculta de ese tipo.

La revisión encontró **un defecto técnico**, que se corrigió y quedó cubierto por pruebas (`V010`, §4.1), y
**cuatro reglas que la base no hace cumplir**, que no se corrigieron porque decidirlas es del negocio y no
de la base (§4.2 a §4.5). Quedaron resueltas como responsabilidad de la API y de la configuración de
producción (`docs/decisiones.md` §12.6): la base sigue aceptando esas operaciones por SQL directo.

## 2. Alcance y método

| Qué | Cómo se revisó |
|---|---|
| Migraciones `V000`–`V003`, `V005`–`V009` | leídas completas, línea por línea |
| `V004` (comentarios) | no leída; la cubre `ESQ-05` (ninguna tabla ni columna sin comentario) |
| Sentencias de `db/queries/` | leídas `q01`, `t02` y la parte de sesiones de `t01`; el resto, por la suite |
| Catálogo del motor | consultas de salud **[A1–A7]** |
| Reglas que el código no hace cumplir | experimentos con `app_backend_user` + `SET LOCAL ROLE` **[B1–B5]** |
| Documentos | cifras contrastadas con el código y con la evidencia regenerada (§7) |

La lectura produjo hipótesis; cada una se convirtió en un experimento antes de escribirla aquí. Las que
no se pudieron ejecutar están marcadas **(deducido)**.

## 3. Lo que se sostiene

**Cumplimiento de las reglas del proyecto**, comprobado en la corrida de cierre:

| Regla | Comprobación |
|---|---|
| Sin `SERIAL`; `id BIGINT GENERATED ALWAYS AS IDENTITY` | `ESQ-02`, `ESQ-03` |
| Todo tiempo es `TIMESTAMPTZ` | `ESQ-04` |
| Ningún CHECK con `now()` ni con subconsulta | `ESQ-20` |
| `SECURITY DEFINER` siempre con `search_path` fijo, y ahora con `pg_temp` al final | `ESQ-10`, `ESQ-11`, `ESQ-30` |
| Sin `SET` de sesión para el contexto del taller | búsqueda en `db/`: 0 apariciones; solo `set_config(..., true)` |
| RLS con `FORCE` en las 14 tablas que lo requieren | `ESQ-06` |
| `app_backend_user` y `PUBLIC` sin privilegios de tabla | `ESQ-15`, `ESQ-17` |
| FK compuestas `(padre_id, taller_id)` en las 10 relaciones entre tablas de taller | `ESQ-21` |
| Ningún secreto en archivos versionados ni en la evidencia | `fase7_cierre.txt` §5: ningún archivo contiene un valor de `.env` |
| Todo comentado | `ESQ-05` |

**Salud del catálogo [A2, A3]:** ningún índice duplicado, ningún índice inválido, ninguna restricción sin
validar, ninguna tabla sin clave primaria, ningún trigger deshabilitado.

**Lo que está bien resuelto y conviene saber defender:**

1. **El aislamiento no depende de una sola barrera.** Una sesión del taller B sobre un vehículo del taller
   A la rechaza la FK compuesta, no la política: funciona también para un superusuario. RLS con `FORCE`
   es la segunda capa y los privilegios por columna la tercera. Las tres se prueban por separado (`04`,
   `05`).
2. **El modelo de roles falla cerrado.** El rol de conexión no hereda nada (`INHERIT FALSE`): olvidar el
   `SET LOCAL ROLE` es un error, no una fuga. `BYPASSRLS` está confinado a un rol sin `LOGIN` que solo es
   dueño de seis funciones.
3. **La concurrencia se probó, no se razonó.** El defecto de T-8 (una línea que entra en una cotización ya
   cerrada) se reproduce quitando el `FOR SHARE` y la prueba lo detecta (`fase4_control_negativo.txt`).
4. **El dinero no se puede falsear desde el cliente.** El mecánico no tiene privilegio sobre las columnas
   de precio; el trigger las copia del catálogo y un CHECK verifica la fórmula.
5. **Los índices están medidos.** La Fase 5 midió con volumen y con el rol real, y encontró lo que con
   semillas o como superusuario no se ve (un enum no puede ser clave de búsqueda bajo RLS).
6. **El respaldo se restauró de verdad**, sobre un clúster vacío, y la suite completa pasó después.

**Claves foráneas sin índice [A1].** Son 11: cinco declaradas como deliberadas en la cabecera de `V006`,
tres que perdieron su índice en `V009` con medición (E6 y E7 de `fase5_indices.txt`), una cubierta por un
índice parcial (`vehiculo → titular`) y dos `taller_id → taller` en tablas hoja. Un índice sobre la columna de una FK solo sirve al borrar el padre o cambiar su
clave, y aquí ningún rol de ejecución puede borrar un padre ni modificar un `id` (decisión abierta g:
`RESTRICT` + estado de baja). No es un hallazgo; lo sería si se habilitara el borrado físico de usuarios,
dispositivos o repuestos.

## 4. Hallazgos

| # | Hallazgo | Gravedad | Estado |
|---|---|---|---|
| H-1 | Una tabla temporal podía suplantar a una real dentro de las funciones definidoras | alta en potencia; no explotable hoy | **corregido** (`V010`) |
| H-2 | Una sesión `completado` o `cancelado` sigue admitiendo cambios en su diagnóstico | media | en la API (T-63) |
| H-3 | El mecánico puede fijar la fecha de inicio de una sesión | media | en la API (T-64) |
| H-4 | El rol de conexión no tiene tiempos de espera ni límite de conexiones | media (operación) | configuración de producción (T-65) |
| H-5 | El administrador puede anular la retención y dejar al taller sin administrador | baja | en la API (T-66) |

### 4.1 H-1: sombra de `pg_temp` en las funciones definidoras (corregido)

Las 21 funciones fijaban `SET search_path = pg_catalog, public`, que es lo que pide la regla del proyecto.
No basta. Cuando `pg_temp` no se nombra, PostgreSQL lo busca **primero** para tablas y tipos: una tabla
temporal con el nombre de una real la reemplaza dentro de la función, sea o no `SECURITY DEFINER`.

Experimento **[B5]** sobre `V000`–`V009` (`fase7_antes.txt`): con el privilegio `TEMPORARY`, un mecánico
crea la tabla temporal `auditoria_operacion`, le otorga `INSERT` a `PUBLIC` y actualiza una sesión.

| | Registros en la tabla temporal | Registros en la auditoría real |
|---|---:|---:|
| Antes (`V009`) | 1 | **0** |
| Después (`V010`) | 0 | 1 |

La escritura quedaba "auditada" en una tabla que desaparece al cerrar la sesión. Por el mismo camino
podían suplantarse `usuario` o `usuario_credencial` ante el login **(deducido: no se ejecutó ese caso)**.

**Por qué no era explotable.** Ningún rol de la aplicación tiene `TEMPORARY` sobre la base **[A5, B5a]**,
consecuencia del `REVOKE ALL ON DATABASE ... FROM PUBLIC` de `V000`. Pero era la única barrera, ninguna
prueba la vigilaba, y la propia suite la levanta dentro de una transacción (`09_consultas.sql`, tema
T-47). Un `GRANT TEMPORARY` futuro —razonable para un reporte— habría abierto el camino sin que nada
fallara.

**Corrección.** `V010` fija `search_path = pg_catalog, public, pg_temp` en las 21 funciones: nombrado de
forma explícita y al final, `pg_temp` pierde frente a `public`. Lo vigilan cuatro pruebas nuevas: `ESQ-30` (las 21 funciones), `ESQ-31` (ningún rol de la aplicación tiene `TEMPORARY`)
y las dos pruebas de sombra de `07_auditoria.sql`, que repiten el experimento y exigen que el registro
llegue a la auditoría real.

### 4.2 H-2: una sesión terminal sigue admitiendo cambios (T-63)

RN-31 declara terminales `completado` y `cancelado`, y el trigger lo hace cumplir para el **estado**. Nada
protege el resto. Experimento **[B1]**, como mecánico, sobre una sesión completada:

| Operación | Resultado |
|---|---|
| cambiar el kilometraje | aceptada |
| agregar un DTC nuevo con severidad `critica` | aceptada |
| cambiar la severidad de sus tres fallas | aceptada |

La cotización cerrada es inmutable, pero el diagnóstico que la justifica no. Los cinco cambios quedan en
la auditoría, así que son detectables, no invisibles.

No se corrigió porque es una regla de negocio que el enunciado no fija: puede ser legítimo corregir un
DTC mal digitado después de entregar el vehículo. **Propuesta:** un trigger en `falla_sesion` y en
`sesion_diagnostico` que rechace con `RE004` todo cambio cuando la sesión está en estado terminal.

### 4.3 H-3: el cliente puede fijar fechas (T-64)

`V007` otorga `INSERT (… iniciada_en)` al mecánico. Experimento **[B2]**: una sesión con
`iniciada_en = 2099-01-01` se acepta. Esa fecha no es decorativa:

- ordena el historial y decide las cifras del período del dashboard;
- **decide la retención**: `fn_solicitar_supresion_titular` calcula el bloqueo desde la última
  `iniciada_en` no cancelada. Una fecha futura alarga el bloqueo de un titular; una antigua lo acorta.

Lo mismo ocurre con `consentimiento_titular.otorgado_en` y `solicitud_derecho_titular.recibida_en`
**[A7]**. El privilegio existe porque las semillas antedatan atenciones asumiendo el rol del taller
(T-34); las sentencias del backend (`tx_crear_sesion`) no envían la fecha.

**Propuesta para producción:** quitar esas columnas de los `GRANT INSERT` y cargar los datos históricos
como plataforma. No se aplicó: obliga a reescribir las semillas y a decidir si se admiten cargas
retroactivas.

### 4.4 H-4: sin tiempos de espera en el rol de conexión (T-65)

**[A6]** `app_backend_user` no tiene configuración propia ni límite de conexiones, y el servidor tiene
`statement_timeout`, `lock_timeout` e `idle_in_transaction_session_timeout` en 0 (sin límite). El diseño
se apoya en bloqueos de fila (`FOR UPDATE`, `FOR SHARE`): un backend que abra una transacción, bloquee una
sesión y no la cierre deja esperando, sin plazo, a todo el que toque esa atención. Con un *pool* en modo
transacción además retiene una conexión.

**Propuesta:** `ALTER ROLE app_backend_user SET idle_in_transaction_session_timeout`, `lock_timeout` y
`statement_timeout`, más un `CONNECTION LIMIT`. Los valores dependen del backend y del *pool*, que no
existen todavía: por eso no se fijaron. Deben elegirse por encima de los 4 segundos que la prueba de
concurrencia retiene sus transacciones.

### 4.5 H-5: el administrador como único control (T-66)

- **[B3]** Con una atención reciente, la supresión deja al titular `bloqueado`. Si el mismo administrador
  pone antes `retencion_anios = 0`, la misma solicitud lo anonimiza de inmediato. La retención "legal" la
  hace cumplir quien tiene interés en no cumplirla. El cambio de configuración queda auditado.
- **[B4]** El administrador puede desactivarse a sí mismo y dejar al taller sin ningún administrador
  activo; recuperarlo exige a la plataforma.

Ambos son coherentes con el modelo (el taller es el responsable de sus datos y la configuración es suya).
Se anotan porque conviene decidirlos a sabiendas: si la retención es una obligación legal y no una
preferencia, el plazo mínimo debería fijarlo la plataforma.

### 4.6 Observaciones menores

- **El precio maestro no tiene moneda (deducido de `V002` y `V003`).** `repuesto.precio_referencia` es
  global y sin moneda; `taller_configuracion.moneda` es por taller. Un taller con otra moneda vería los
  mismos importes con otra etiqueta. Es el supuesto 2 de `decisiones.md` (sin conversión); el
  multi-moneda es nominal mientras no exista una lista de precios por taller (**[AVANZADA]**, decisión 6).
- **`ck_sesion_diagnostico_estado_timestamps` usa un `CASE` sin `ELSE` (deducido).** Si se agregara un
  valor a `tipo_estado_atencion`, el `CASE` devolvería `NULL` y el CHECK lo aceptaría sin validar nada.
  Hoy los cuatro valores están cubiertos.
- **El bloqueo por intentos fallidos lo puede provocar un tercero** que conozca el email: cinco intentos
  bloquean 15 minutos a un administrador. Es el intercambio habitual de este control; el límite por IP es
  del backend (`docs/seguridad.md` §13).

## 5. Estado de la entrega

Cifras de `fase7_cierre.txt` §3:

| | |
|---|---|
| Servidor | PostgreSQL 16.15 |
| Migraciones | 11 (`V000`–`V010`) |
| Tablas / vistas / enums | 21 / 1 / 14 |
| Funciones (definidoras) / triggers / políticas | 21 (6) / 32 / 49 |
| Índices (de rendimiento `ix_`) | 68 (14) |
| Sentencias del backend | 43 (28 de lectura, 15 de escritura) |
| Pruebas | 518 en 12 archivos, 0 fallos |

## 6. Lo que falta para producción

Nada de esto es nuevo; cada punto está declarado en el documento que se indica. Se reúne aquí porque es
la pregunta que hará quien reciba el proyecto.

| Falta | Dónde está declarado |
|---|---|
| La contraseña llega en claro al motor (`crypt()` en la base) | `seguridad.md` §9.3, §9.4 |
| TLS y regla `hostssl` | `seguridad.md` §13, `operacion.md` §4 |
| PgBouncer real | `seguridad.md` §13, `pruebas.md` §6 |
| Recuperación a un punto en el tiempo; respaldos cifrados y fuera del equipo | `operacion.md` §2, §10 |
| Tareas periódicas programadas (respaldo, anonimización de vencidos) | `operacion.md` §7, §9 |
| Control de migraciones aplicadas | `operacion.md` §9 (T-21) |
| Particionado y plazo de retención de la auditoría | `operacion.md` §6 (T-58) |
| Validación legal: Ley N° 21.719, plazos, patente y VIN como dato personal | `privacidad.md` |
| Tiempos de espera del rol de conexión | este documento, §4.4 |

## 7. Coherencia entre documentos

Se contrastaron las cifras que más de un documento cita. Correcciones hechas en esta fase:

| Documento | Corrección |
|---|---|
| `pruebas.md` | 518 pruebas; `01_esquema.sql` 31, `07_auditoria.sql` 26 |
| `operacion.md` | cifras de la evidencia de la Fase 6, regenerada sobre el esquema final |
| `seguridad.md` §8 | el `search_path` real y por qué lleva `pg_temp` |
| `seguridad.md` §6, `consultas.md` §2 | frases en futuro sobre fases ya terminadas |
| `modelo/03_modelo_logico.md` | ya no es un borrador: remite al diccionario generado |
| `README.md` | versión final |

Coinciden con el código sin cambios: 43 sentencias (28 + 15), 21 tablas, 14 enums, 50 reglas RN, 12
códigos `RE0xx`. **Las tablas "Verificación de la Fase n" de `decisiones.md` no se tocaron**: registran lo
que se midió en cada fase (468, 484, 514 pruebas) y son historia, no estado.

## 8. Lo que este dictamen no verificó

- **`make` literal.** No está instalado (T-1). `evidencia_fase7.sh` lee del `Makefile` las dependencias de
  `all` y la receta de cada una y las ejecuta tal como están escritas; lo que no se probó es el programa
  `make`. Si se instala, el mismo script ejecuta `make all`.
- **La medición de rendimiento no se repitió.** `V010` solo cambia la configuración de las funciones; los
  `fase5_*.txt` y `fase6_perf.txt` son de corridas anteriores (T-60).
- **Suplantación de `usuario` ante el login** por una tabla temporal: deducida del mismo mecanismo que
  [B5], no ejecutada.
- **Los diagramas Mermaid** siguen sin renderizarse en este equipo.
- **Revisión por un tercero.** Este dictamen lo escribió quien construyó la base: es una revisión
  adversarial hecha con método, no una auditoría independiente.

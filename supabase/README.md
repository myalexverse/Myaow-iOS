# Myaow en Supabase — piloto iOS y adjuntos privados desplegados

Proyecto `your-project-ref`, organización **Odiseo Labs**, plan **Free**. Verificado el 1 de octubre de 2026. No se activaron complementos, ramas ni planes de pago.

## Estado real

- Catorce migraciones aplicadas: esquema privado con 17 tablas, controles de entrega/acceso, grupos, tareas, programación y correcciones verificadas.
- Función `myaow-api` activa (versión 5), en `https://your-project-ref.supabase.co/functions/v1/myaow-api`.
- HTTPS, prueba de posesión X25519 compatible con iOS, sesiones revocables, mensajes cifrados persistentes y confirmaciones verificados contra el servicio desplegado.
- Registro **cerrado**, límite de 30 cuentas. Con autorización del usuario se habilitó temporalmente una invitación de un uso, se completó el registro desde la pantalla del piloto y se volvió a cerrar. No quedó registro libre.
- La app habitual instalada conserva el backend Node anterior y sus datos. El código ahora admite Supabase y existe una compilación de prueba separada (`com.ScendLabs.Myaow.SupabasePilot`), con URL e invitación configuradas. El piloto está instalado y probado en el simulador iPhone 17 Pro; conserva su cuenta e historial al actualizar. No se migraron datos de la app habitual.
- Grupos privados, invitaciones dirigidas, roles, tareas/asignaciones/avances y programación cifrada ya operan en este endpoint. Se probaron en SQL y con un cliente Swift/CryptoKit real. Los servicios iOS de directorio, grupos, tareas, programación y bloqueos ya eligen este adaptador cuando la dirección incluye `/functions/v1/myaow-api`. Falta la prueba interactiva completa en simulador y teléfonos.
- Tres trabajos internos: envío programado cada minuto, mantenimiento cada hora y revisión de la cola push cada cinco segundos. La revisión push no realiza llamadas externas mientras está desactivada o no hay trabajo. Se verificó un envío real a dos destinatarios después de cerrar la sesión del remitente; no depende de que su teléfono permanezca abierto.
- Registro de dispositivos y cola push por instalación implementados. Servicio `myaow-push` v1 desplegado; envío desactivado (`push_enabled=false`) hasta configurar y verificar APNs. La API principal es `myaow-api` v6.
- Storage privado ya está conectado para fotos, audios y archivos cifrados de los chats. Realtime ya está conectado mediante avisos privados por sesión. APNs y TURN siguen pendientes. El envío programado lo ejecuta PostgreSQL; no genera todavía notificaciones de Apple.

## Endpoints actuales

Todos los endpoints salvo `/health` usan POST; `/media/upload/<uuid>` recibe bytes cifrados y los demás JSON. Los datos requieren `Authorization: Bearer <sesión Myaow>`; los tokens expiran a las 24 horas y se almacenan solo como hash.

| Ruta | Función |
| --- | --- |
| GET `/health` | Estado básico del servicio |
| `/register` | Alta por invitación; actualmente cerrada |
| `/auth/challenge`, `/auth/proof` | Prueba de posesión de la identidad local; desafío de un solo uso, 30 segundos |
| `/profile`, `/logout` | Perfil propio y revocación inmediata de sesión |
| `/directory/check-username` | Disponibilidad pública limitada por tasa; sin datos del perfil |
| `/directory/lookup` | Búsqueda exacta autenticada por usuario o identidad, única sin distinguir mayúsculas; respeta bloqueos |
| `/contacts/block`, `/contacts/unblock`, `/contacts/blocked` | Bloqueos de la sesión actual |
| `/messages/sync` | Pendientes del receptor y hasta 100 confirmaciones de mensajes del remitente autenticado |
| `/messages/send` | Aceptación persistente de sobre HPKE v2; reintentos idempotentes |
| `/messages/pending` | Hasta 50 mensajes del receptor; revalida bloqueos y pertenencia al grupo |
| `/messages/acknowledge` | Solo el receptor confirma almacenamiento; no equivale a lectura |
| `/messages/batch` | Entrega cifrada atómica a todos los miembros actuales del grupo |
| `/groups/create`, `/groups/list`, `/groups/members` | Crear y consultar solo grupos propios |
| `/groups/invite`, `/groups/accept` | Invitación dirigida a una identidad concreta, caduca a los 7 días |
| `/groups/info`, `/groups/leave`, `/groups/kick`, `/groups/promote`, `/groups/demote` | Cambios con permisos de miembro, administrador o propietario |
| `/tasks/create`, `/tasks/list`, `/tasks/update`, `/tasks/delete` | Asignación a miembros, avance 0–100 y autoría de finalización |
| `/schedules/create`, `/schedules/list`, `/schedules/cancel` | Programación cifrada privada y cancelación antes de entrar en la cola |
| `/media/prepare`, `/media/upload/<uuid>`, `/media/download`, `/media/delete` | Reserva idempotente, subida cifrada, descarga autorizada y eliminación por el autor |

El adaptador iOS traduce las rutas de grupos, tareas y programación existentes a estos endpoints y conserva el prefijo de la función. El transporte Node/WebSocket continúa disponible. Las rutas todavía no migradas fallan explícitamente; no envían la solicitud a otro backend.

## Cliente iOS de prueba

`Scripts/build-supabase-pilot.sh` compila para simulador con identificador separado y registro por invitación. No instala ni modifica la aplicación habitual; el servidor continúa con altas cerradas. La URL se incorpora como configuración pública, sin claves de servicio. Los archivos de la copia quedan en `/private/tmp/myaow-supabase-pilot/Build/Products/Debug-iphonesimulator/Myaow.app`.

`SupabaseClient` es el cliente HTTPS utilizado tanto por la app como por las pruebas nativas remotas. Autentica con la identidad X25519 guardada, conserva el formato HPKE, traduce las rutas y devuelve errores comprensibles. La búsqueda inicial es exacta, no expone un listado general de usuarios. Las invitaciones de grupo requieren el destinatario y solo esa identidad puede aceptarlas.

El piloto recibe avisos por un canal privado de Supabase Realtime mientras está abierto. La sesión Myaow viaja en el encabezado del WebSocket; RLS verifica su hash, vencimiento y coincidencia con el canal. Solo el servidor publica un evento vacío. Después, la app descarga los sobres con la API autenticada. Los disparadores solo notifican sesiones vigentes, incluso si Realtime conserva permisos de una conexión anterior. No hay claves privilegiadas en la app.

La reconciliación HTTP comprueba cada 60 segundos con Realtime conectado y sin pendientes; drena pendientes cada 3 segundos. Si el canal falla, vuelve a consultar cada 3 segundos en un chat o 15 en reposo. Los fallos usan espera progresiva hasta 60 segundos; un límite de tasa impone 60 segundos. En segundo plano detiene el canal y las consultas; al volver sincroniza de nuevo. Los avisos recibidos durante una petición se conservan para el siguiente ciclo. Grupos, tareas y programados se refrescan con estos avisos. La cola cifrada queda aislada por servidor y cuenta y conserva mensajes hasta confirmar la entrega. Las confirmaciones grupales mantienen los identificadores por destinatario y solo marcan entrega completa al confirmar todos.

Se probaron registro, recepción de texto/foto/audio/archivo, reproducción de audio, apertura del documento, envío de texto y persistencia tras actualizar desde las pantallas. También se completó envío de foto, grabación/envío de audio y selección/envío de archivo; el usuario operó las celdas de Fotos y Archivos que la herramienta no podía controlar. El 2 de octubre se crearon grupo, invitación, tarea asignada, mensaje y programación desde el piloto. Un cliente Swift separado aceptó la invitación, actualizó la tarea y descifró los mensajes. El programado llegó con el proceso del piloto terminado. Véase `Review/2026-10-02/Realtime-Grupos/REVISION.md`. Faltan APNs real y mediciones de carga y consumo; estas pruebas no validan un millón de conexiones. Registro abierto, llamadas de Internet, APNs y funciones sociales no se habilitan por el mero hecho de compilar el piloto. Radio local mantiene su transporte propio.

## Adjuntos privados del piloto

El dispositivo cifra fotos, audios y archivos antes de subirlos. Storage solo recibe bytes opacos; el nombre del archivo y la clave viajan dentro del mensaje HPKE. La URL por sí sola no permite descargarlos. Cada descarga comprueba sesión, propietario/destinatario, bloqueos y, para grupos, la pertenencia actual y la lista original de receptores. Un miembro nuevo no recibe acceso retroactivo a esos archivos.

Límites propios del piloto: 10 MiB por archivo, 40 MiB reservados por autor y 200 MiB globales. Las reservas también cuentan; no confundirlos con las cuotas comerciales de Supabase. El servidor verifica tamaño y SHA-256 antes de confirmar. El cliente conserva una reserva cifrada por mensaje para reutilizar identificador y contenido después de reiniciar, y la retira cuando el sobre queda guardado en la cola local. Falta automatizar la limpieza de reservas abandonadas y archivos huérfanos antes de ampliar la beta.

`supabase/tests/media.sql` comprueba permisos, grupos, bloqueos, reservas, límites y revocación con rollback. `Server/test_supabase_media.mjs` comprueba autorización, hash, tamaños y errores de Storage. `Scripts/Tests/PendingMediaChecks.swift` verifica persistencia cifrada y aislamiento entre cuentas. `Scripts/Tests/SupabaseMediaChecks.swift` realiza subida/descarga real con CryptoKit, reintento idempotente, rechazo de extraños y bloqueos, y limpieza usando la API de Storage. `--chat` y `--ping` usan únicamente cuentas ficticias para probar el simulador; sus claves temporales nunca deben entrar en Git.

La recepción y apertura de adjuntos se comprobó desde el piloto. En la revisión del 1–2 de octubre se completaron desde la interfaz los tres envíos: foto elegida en Fotos, audio grabado en el chat y TXT elegido en Archivos, con asistencia del usuario para los selectores nativos. El receptor Swift descargó, descifró y confirmó los tres. Se corrigieron reintentos automáticos tras reconectar, unificación de la cola y estados visibles. Las pruebas de interrupción usan el cliente HTTP real con respuestas interceptadas antes y después del commit; no sustituyen un corte de red físico entre teléfonos. [Evidencias de adjuntos](../Review/2026-10-01/Adjuntos/REVISION.md).

## Frontera de acceso

Las tablas están en `myaow_private`, sin acceso para `anon` ni `authenticated`, con RLS y políticas explícitas que rechazan acceso directo. La función SQL pública solo es ejecutable por el rol de servidor. Es `SECURITY INVOKER`, con nombres de esquema explícitos y sin SQL dinámico basado en datos del usuario. La función de borde usa su clave de servidor suministrada por Supabase; nunca se incluye en iOS.

`verify_jwt=false` es intencional: el protocolo de Myaow no usa el JWT de Supabase Auth. La función verifica el desafío X25519 existente y cada operación de datos comprueba una sesión Myaow revocable. Las operaciones previas al inicio de sesión están limitadas y no permiten elegir acciones SQL arbitrarias. La autorización de datos reside en las operaciones SQL privadas y la sesión comprobada, no en `user_metadata` ni en un identificador enviado por el cliente.

Se conservan las claves y el formato de cifrado de la app. No se afirma compatibilidad con el protocolo Signal ni cifrado de extremo a extremo para metadatos de tareas/grupos: esos campos operativos no están cifrados en este esquema. Antes de abrir la beta falta completar recuperación y borrado de cuentas, además de la retención y limpieza de adjuntos huérfanos. Los límites de adjuntos ya se aplican en el servidor. La limpieza horaria elimina sesiones/desafíos vencidos, mensajes confirmados de más de 7 días y programaciones entregadas/canceladas de más de 30 días; no elimina mensajes pendientes ni cambia permisos.

## Verificación

- Compilaciones Debug y Release para simulador aprobadas; paquete del piloto, URL e invitación comprobados en la app generada. La última compilación Debug del piloto fue instalada y probada. No se afirma prueba de interfaz completa ni entrega APNs real.

- `Scripts/Tests/SupabaseRouteChecks.swift`: comprueba HTTPS, conservación de la URL de la función, rutas/métodos, invitaciones y rechazo de funciones no migradas; se ejecuta en la validación crítica.
- `Server/test_supabase_gateway.mjs`: prueba de posesión, rechazo de claves de bajo orden, identidad falsa, acceso sin sesión, tamaño y límites, ocultación de errores y compatibilidad sin Buffer global de Node.
- `supabase/tests/private_backend.sql`: pruebas con datos ficticios dentro de una transacción revertida; invitaciones atómicas, acceso entre cuentas, duplicados, bloqueos, grupos y revocación.
- `supabase/tests/collaboration.sql`: permisos de grupos y tareas, invitaciones dirigidas, avance, cancelación, programación tras caducar la sesión, bloqueos, expulsión, duplicados y recuperación de cola llena sin entrega parcial. Todos los datos se revierten.
- `Scripts/Tests/SupabaseNativeChecks.swift`: cliente Swift real con CryptoKit que autentica y envía/descifra HPKE contra la función desplegada; además crea grupo/tarea, comprueba permisos y recibe un envío automático del cron tras cerrar sesión del remitente. Requiere preparar tres identidades temporales, dar de alta solo sus claves públicas mediante la integración y retirar después sus mensajes, perfiles y claves locales. No usa contactos reales ni deja credenciales en Git.
- Asesor de seguridad: sin avisos después de las catorce migraciones. Asesor de rendimiento: avisos informativos de índices aún sin uso, esperables en una base recién creada; revisar con carga real antes de retirarlos.
- Las pruebas anteriores del 30 de septiembre retiraron todas sus identidades. El 1 de octubre quedan dos perfiles ficticios: `pruebapiloto` en el simulador y su contacto de demostración `Prueba Media A`, con tres adjuntos (153.795 bytes cifrados). Se retiraron las otras dos cuentas auxiliares, sesiones remotas de prueba y claves temporales. La identidad del piloto se conserva en su Keychain. El contacto de demostración queda sin cliente conectado. La revisión posterior de adjuntos conserva además el perfil ficticio Prueba Adjuntos y tres archivos salientes; retiró las otras dos cuentas auxiliares y sus claves temporales.

## Programación y límites de esta etapa

Los sobres se cifran en el cliente para cada destinatario. El servidor guarda también una vista previa cifrada que solo debe abrir su autor. Al ejecutar el envío se vuelven a comprobar los bloqueos y la pertenencia al grupo; si cambiaron, la programación pasa a `attention` y no se envía parcialmente. Una cola llena conserva el estado `pending` y reintenta. `queued` significa guardado para los destinatarios; `delivered` exige sus confirmaciones, no solo aceptación del servidor. El registro público permanece cerrado.

El proceso despacha hasta 50 programaciones por minuto. Una beta sin congestión puede tener aproximadamente un minuto de retraso respecto de la hora seleccionada; pausas del proyecto, fallos o saturación pueden aumentarlo. La cola por receptor admite hasta 1.000 sobres pendientes y 8 MiB; los grupos, 30 miembros. Cada identidad puede tener 20 grupos propios y 100 programaciones activas de hasta 30 días. Estos son límites de piloto, no una validación de un millón de usuarios simultáneos. La entrega no implica que llegue una alerta con el iPhone bloqueado: APNs sigue pendiente.

Los RPC de datos mantienen `SECURITY INVOKER` y rechazan acceso `anon` y `authenticated`. La excepción privada `can_receive_wakeup` es un predicado `SECURITY DEFINER` que solo devuelve un booleano después de validar sesión, vencimiento y canal; no concede acceso a tablas privadas. Las pruebas HTTP ejercen el rol real de servidor y las pruebas SQL verifican los casos de error con rollback. El historial de migraciones conserva las correcciones a las ambigüedades SQL detectadas; los últimos trabajos automáticos terminaron correctamente.

## Comunicación sin Internet

`MeshNetworkService` y `LocalRadioTransport` permanecen en el dispositivo. No se sustituyeron por Supabase, ni dependen de esta API. El radio conserva contactos autorizados, claves guardadas, invitación aceptada y cifrado local. La primera verificación del contacto puede requerir Internet; conviene hacerla antes del evento.

El radio actual es privado entre dos contactos, con la pantalla de Radio abierta. Al salir o bloquear el teléfono se desconecta. No ofrece una red de radio de largo alcance ni cobertura garantizada de todo un recinto. Wi-Fi/Bluetooth, permisos de red local, interferencias y distancia afectan a la conexión. Se deben probar dos iPhone reales sin salida a Internet, con distintas distancias y obstáculos, y repetir en el lugar del evento.

`Scripts/validate-radio-local.sh` pasó con peers de prueba en el Mac: descubrimiento, rechazo de autorización unilateral, consentimiento explícito, PCM cifrado, aislamiento de canal y desconexión por revocación. Esto no sustituye una prueba de alcance con teléfonos.

## Dominio

Por ahora se usa la dirección gratuita de Supabase. No se necesita acceso a GoDaddy ni cambiar DNS para continuar la migración. `odisseolabs.com` queda disponible para la web y los servicios que realmente necesiten un dominio propio.

## Notificaciones preparadas; activación pendiente

El registro `push/device` usa la sesión X25519 existente, valida entorno/identificador de aplicación y limita cada cuenta a cinco instalaciones. La cola se crea por dispositivo, sin texto, nombre del remitente ni archivos. El cierre explícito de sesión elimina sus registros; la expiración natural permite mantener avisos mientras el teléfono está cerrado, hasta 90 días desde la última actualización del dispositivo.

El servicio interno usa una credencial independiente, valida los permisos justo antes del envío, cancela avisos de mensajes ya recibidos, invalida tokens rechazados por Apple y conserva trabajos tras fallos. Cada trabajo tiene exclusión temporal de dos minutos, hasta ocho intentos y expiración de 24 horas. Aceptación de APNs no equivale a entrega del mensaje. El contenido visible es solo «Myaow · Tienes un mensaje nuevo».

Configuración completada el 3 de octubre de 2026: `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPICS`, `MYAOW_APNS_ENABLED=true` y `MYAOW_PUSH_WORKER_SECRET` están en los secretos del proyecto Myaow. La credencial interna también está en Vault como `myaow_push_worker_secret`, con coincidencia verificada por huella. La clave APNs `YOUR_APNS_KEY_ID` pertenece al equipo `YOUR_TEAM_ID`, está limitada a `com.ScendLabs.Myaow` y a **producción**. No sirve para el piloto `com.ScendLabs.Myaow.SupabasePilot` en sandbox.

`myaow-push` v3 responde 401 sin credencial y 200 con `processed: 0` con la credencial correcta; se comprobó la firma dentro del runtime desplegado, sin enviar alertas a Apple. Corregida la validación de P-256: Node usa `prime256v1` y el runtime de Supabase puede usar `p256` para la misma curva. La cola continúa desactivada (`push_enabled=false`), sin trabajos. Antes de habilitarla falta preparar la compilación de producción conectada a Supabase y verificar su registro; separar los dispositivos sandbox de los destinos soportados por esta clave. Después probar entrega real con iPhone bloqueado. Evidencia: [configuración APNs](../Review/2026-10-03/APNs/CONFIGURACION.md).

Pruebas: `supabase/tests/push_delivery.sql` revierte los datos ficticios; `Server/test_supabase_push.mjs` comprueba autenticación interna, firma ES256, privacidad del aviso y respuestas de APNs mediante transporte simulado. No constituyen una entrega real de Apple. Consulte [APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns), [HTTP/2 de Deno](https://docs.deno.com/api/deno/fetch/) y [programación segura en Supabase](https://supabase.com/docs/guides/functions/schedule-functions).

# Despliegue de beta cerrada — Myaow

Estado: configuración preparada, **no desplegada**. Docker/Caddy/coturn no están instalados en el entorno de revisión; aún hay que construir las imágenes y validar la configuración en el host Linux elegido. La app y el servidor se han probado por separado en este Mac. No se ha contratado ningún servicio ni cambiado DNS.

Dominio confirmado por el usuario: **odisseolabs.com**, comprado en GoDaddy. La plantilla propone `api-beta.myaow.odisseolabs.com` y `turn-beta.myaow.odisseolabs.com`; ver [registros y activación](DOMINIO.md). No están activos todavía.

## Arquitectura inicial

- Primera cohorte propuesta: 10–20 personas, tope configurado de 30 cuentas. Esto es una restricción de acceso; no es una medición de capacidad.
- Un servidor Linux para Caddy y el relay Node/SQLite, con disco persistente. Propuesta inicial de recursos: 2 CPU / 4 GB RAM; ajustar con medidas reales de memoria, disco y tráfico.
- `api-beta.myaow.odisseolabs.com`: HTTPS para la API y WSS para mensajes. Caddy termina TLS y mantiene WebSocket. El puerto 8080 del relay NO se publica.
- `turn-beta.myaow.odisseolabs.com`: coturn, preferentemente en otra IP/instancia si se requiere TURN/TLS por puerto 443 para redes restrictivas. Estos subdominios están propuestos sobre el dominio existente; los registros todavía no se crearon.
- APNs: el backend envía alertas de mensaje o avisos VoIP a Apple. La app conserva el contenido del mensaje fuera de la notificación.
- Una instancia del relay: SQLite no se comparte entre varias réplicas. Un millón de conexiones simultáneas requiere otra arquitectura y pruebas de carga.

## Datos que faltan

1. Acceso del titular al DNS de odisseolabs.com en GoDaddy para crear los registros cuando existan las IP del alojamiento. El dominio ya está identificado.
2. Proveedor y acceso al servidor Linux (si existe); si no, elegir uno antes de contratarlo.
3. Credenciales APNs de la cuenta Apple que firma `com.ScendLabs.Myaow`: Team ID, Key ID y archivo privado `.p8`. El archivo no se envía por chat ni se guarda en Git.
4. IP de TURN, certificado válido y secreto compartido entre coturn y el relay. El secreto no aparece en la app.
5. Destino externo y cifrado para los respaldos; propietario de las alertas operativas.

Lo encontrado localmente: la copia de revisión apunta a `localhost:18090`; el valor de desarrollo por defecto es `localhost:8080`. No hay `MYAOW_RELAY_URL` de producción configurada en el proyecto. El diagnóstico de presencia de configuración APNs/TURN dio todos los valores pendientes. Esto no demuestra que no exista algún servidor contratado fuera del proyecto.

## Preparación del servidor

1. Instalar Docker Engine + Compose desde su distribución oficial. Publicar solo 80/443 para Caddy; restringir SSH a la administración. No publicar SQLite, Docker, ni el puerto 8080.
2. Copiar el código y los archivos de `deploy`. El contexto de construcción excluye claves, bases de datos, uploads, `.env` y dependencias locales.
3. Copiar `.env.beta.example` a `.env.beta` en el host y completar datos reales. Guardar secretos fuera del checkout, legibles únicamente para el operador y el UID 1000 del contenedor. Los secretos de Compose son archivos montados; requieren protección del disco/host.
4. Fijar `CADDY_IMAGE` a una versión/digest validada al desplegar. La base Node es 24.21.0; construir y escanear esa imagen antes de abrir acceso externo. No programar actualizaciones ciegas durante el piloto.
5. Con las dependencias de `Server` instaladas, ejecutar la comprobación local antes de construir. Desde `Server/deploy`:

```sh
node ../check_beta_configuration.js --env .env.beta
docker compose --env-file .env.beta config --quiet
docker compose --env-file .env.beta build relay
docker compose --env-file .env.beta up -d
# Solo imprime presencia de configuración, nunca valores privados.
docker compose --env-file .env.beta exec relay node check_call_configuration.js
```

La comprobación rechaza dominios de ejemplo, una versión de Caddy sin fijar, claves Apple ilegibles o que no sean EC P-256, TURN incompleto y registros abiertos. Solo muestra estados y correcciones; nunca imprime claves ni ejecuta el archivo como un script. No consulta DNS ni verifica que Apple autorice la clave: estas pruebas siguen siendo necesarias al desplegar. El arranque del relay en Compose vuelve a validar claves, TURN, rutas persistentes y acceso por invitación (o cerrado), y termina antes de abrir el servidor si faltan datos. El servidor de desarrollo conserva su arranque habitual.

`/health` comprueba la base de datos y solo publica estado básico. Un estado saludable no verifica la entrega de Apple ni el transporte de audio. Configurar un monitor externo HTTPS y avisos por reinicios, disco bajo y errores; los logs de producción omiten nombres, identificadores y contenidos. Caddy no registra URLs de archivos privados.

## TURN

`turnserver.conf.example` debe convertirse en una configuración real del servidor coturn. No es un servicio desplegado ni un certificado emitido.

- Sustituir dominio, rutas de certificado y secreto. `static-auth-secret` debe coincidir con el archivo `TURN_SECRET_FILE` montado en el relay; generar un secreto aleatorio de al menos 32 caracteres.
- Abrir 3478 UDP/TCP, 5349 TCP y 49160–49260 UDP, además de configurar la IP pública si existe NAT. El rango de puertos y las cuotas son de beta, no para un millón de usuarios.
- El nombre TURN debe resolver directamente a su IP; un proxy HTTP convencional no transporta TURN UDP.
- Instalar certificado válido con renovación automática y recarga de coturn. Probar TURN/TLS; para redes que solo acepten 443, usar una IP/servidor separado y un endpoint `turns:...:443?transport=tcp`.
- No habilitar peers loopback ni acceso a redes privadas. La plantilla bloquea rangos internos y limita asignaciones. Verificar las restricciones con la versión de coturn instalada.
- El endpoint autenticado `/api/v1/webrtc/ice-servers` devuelve credenciales temporales de 4 horas. La app usa solo candidatos relay para evitar exponer directamente direcciones de red entre contactos. Sin TURN configurado no se inicia una llamada que parezca conectada.

## Invitaciones y versión iOS

El relay utiliza `BETA_REGISTRATION_MODE=invite` y `BETA_MAX_USERS=30`. Cada código dura siete días por defecto, solo sirve para crear una cuenta y se almacena como hash. La creación de cuenta y el consumo del código ocurren en una misma transacción. Un reintento idéntico después de crear la cuenta no consume otro código.

```sh
# Ejecutar únicamente por el operador. Imprime un código para entregar al invitado.
docker compose --env-file .env.beta exec relay node beta_invite.js 7
```

Para pausar nuevos registros, cambiar `BETA_REGISTRATION_MODE=closed` y recrear el relay. Las cuentas existentes siguen entrando. Sin un modo explícito, producción mantiene los registros cerrados.

Compilar la versión de TestFlight con:

- `MYAOW_RELAY_URL=https://api-beta.myaow.odisseolabs.com` (solo después de activar y comprobar el servidor)
- `MYAOW_BETA_INVITE_REQUIRED=YES`
- Release: `MYAOW_PUSH_ENVIRONMENT=production`, `MYAOW_APNS_ENVIRONMENT=production`.
- Bundle, perfil firmado y tópico APNs coincidentes. El tópico VoIP agrega `.voip` automáticamente.

El registro muestra el campo de invitación y oculta el inicio sin conexión en la beta cerrada. La cuenta registrada mantiene radio y funciones locales cuando pierde Internet. Para una beta inicial, validar una cuenta por iPhone; la coordinación de llamadas entre varios dispositivos de la misma cuenta todavía está pendiente.

## Respaldos y recuperación

La copia SQLite usa la API de backup online, que incluye transacciones confirmadas del WAL. No copiar únicamente el archivo `.db` de una base en ejecución. La carpeta de uploads también se guarda; el manifiesto se escribe al finalizar y permite verificar la integridad de la base.

```sh
# Usar un nombre distinto en cada ejecución. Nunca sobreescribe otra copia.
docker compose --env-file .env.beta exec relay node backup.js create /backups/beta-AAAA-MM-DD-HHMM
docker compose --env-file .env.beta exec relay node backup.js verify /backups/beta-AAAA-MM-DD-HHMM
```

Automatizar una copia diaria y otra antes de cada actualización. El volumen `backups` está en el mismo servidor: **no protege frente a perder el host**. Transferir las copias cifradas a un destino externo, proponer retención de 7 diarias y 4 semanales, y comprobar una restauración en un entorno aislado antes de invitar usuarios. La programación del backup y la copia externa aún no están activadas.

Para restaurar: detener el relay, conservar el volumen actual como rollback, verificar una copia y recuperar base + uploads en un volumen nuevo con propietario UID 1000. Las sesiones de conexión se renegocian al iniciar. Documentar fecha y responsables; probar envío, recepción y programación antes de volver a abrir acceso. Los tokens de Apple e invitaciones son datos privados presentes en el respaldo: cifrarlo y restringir acceso.

## Puerta de entrada a usuarios reales

- Registro con código, rechazo de código usado/vencido y pausa de altas.
- Texto, grupo y mensaje programado con emisor cerrado; receptor bloqueado y conexión cambiando entre Wi-Fi/datos.
- APNs tanto Debug/sandbox como Release/production. Aceptado por Apple no equivale a mostrado ni leído.
- Llamada entrante desde app terminada, aceptada/rechazada desde pantalla bloqueada; contacto eliminado/bloqueado no debe sonar. Micrófono/cámara deben estar autorizados previamente.
- TURN UDP y TLS con dos iPhone en redes distintas. Verificar audio bidireccional, silencio, altavoz, auriculares, finalización y reconexión.
- Respaldo restaurado, alarma de caída y espacio de disco comprobados.

La interfaz de llamada se integra con CallKit/PushKit; la prueba real en este simulador iOS 26.5 encontró un límite del runtime: `callservicesd` no pudo abrir `facetime://?launchForIncomingCall=1` y ordenó terminar la llamada por falta de interfaz anfitriona. No se ha validado aceptación en pantalla bloqueada ni audio/video real. La notificación de texto sí se inyectó y apareció visualmente con la copia de la app terminada; esta prueba omite APNs y no certifica entrega de Apple.

Referencias: [CallKit/PushKit de Apple](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit), [configuración oficial de coturn](https://github.com/coturn/coturn/blob/master/examples/etc/turnserver.conf), [secretos de Compose](https://docs.docker.com/reference/compose-file/secrets/), [HTTPS automático de Caddy](https://caddyserver.com/docs/automatic-https), [WebSocket en Caddy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy), [ciclo de Node](https://github.com/nodejs/Release).

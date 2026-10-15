# Dominio de la beta: odisseolabs.com

El usuario confirmó que ya compró odisseolabs.com en GoDaddy y quiere aprovecharlo para ahorrar la compra de otro dominio. No hace falta tener una web publicada para usar sus subdominios.

Consulta pública del 30 de septiembre de 2026: los servidores DNS son `ns07.domaincontrol.com` y `ns08.domaincontrol.com`. Los dos subdominios propuestos no devolvieron registros A. No se modificó ningún registro ni se accedió a la cuenta.

## Direcciones preparadas

| Uso | Dirección | Nombre del registro A en la zona odisseolabs.com | Valor pendiente |
| --- | --- | --- | --- |
| API y mensajes | api-beta.myaow.odisseolabs.com | api-beta.myaow | IPv4 pública del servidor de la API |
| Llamadas TURN | turn-beta.myaow.odisseolabs.com | turn-beta.myaow | IPv4 pública del servidor TURN |

El dominio principal y `www` quedan disponibles para la web del laboratorio. Estos nombres están en la plantilla de configuración, pero todavía no están activos ni incluidos como dirección de producción en la app instalada.

## Activación cuando tengamos servidor

1. Elegir/provisionar el alojamiento y obtener las IP públicas estables. Comprar el dominio no incluye la infraestructura del backend.
2. En GoDaddy, abrir el dominio → DNS → Añadir registro. Crear únicamente los dos registros A de la tabla con las IP reales. Usar el TTL predeterminado. Revisar que no existan registros con esos mismos nombres antes de añadirlos; no sustituir los del dominio principal ni los de correo.
3. Confirmar resolución pública de ambos nombres. No crear registros AAAA hasta tener conectividad IPv6 funcional.
4. Completar `.env.beta`, credenciales Apple, secreto TURN, correo operativo para certificados y versión de Caddy. La plantilla usa los nombres de arriba.
5. Validar el archivo con `node ../check_beta_configuration.js --env .env.beta` desde `Server/deploy`, construir e iniciar los servicios siguiendo `BETA.md`.
6. Para coturn, usar `turn-beta.myaow.odisseolabs.com` en realm, server-name y las rutas del certificado. Emitir y renovar su certificado en ese host; el certificado automático de Caddy para la API no cubre automáticamente TURN. Si se usa TURN/TLS por 443, reservar otra IP/servidor para evitar colisión con HTTPS.
7. Comprobar HTTPS, WebSocket, TURN y entrega real de Apple. Después compilar TestFlight con `MYAOW_RELAY_URL=https://api-beta.myaow.odisseolabs.com`.

No es necesario transferir el dominio ni contratar una web en GoDaddy para enlazarlo a un servidor externo. La elección del alojamiento, el presupuesto y la compra siguen pendientes.

Referencia: [Añadir un subdominio — GoDaddy](https://www.godaddy.com/help/create-a-subdomain-4080).

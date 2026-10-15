# Mensajería fiable y objetivo de 1.000.000 de conexiones

Estado: 22 de septiembre de 2026. El relay ejecutable sigue siendo una instancia Node con SQLite. **No está validado ni desplegado para un millón de conexiones simultáneas.** Las pruebas locales verifican corrección, no capacidad de producción.

## Contrato implementado

1. El cliente guarda el mensaje localmente. El texto se mantiene como borrador si esa escritura falla.
2. CryptoKit crea un sobre HPKE autenticado v2. El cuerpo, respuestas, instrucciones de edición/eliminación, reacciones, recibos de lectura y enlaces con claves de adjuntos quedan dentro del cifrado.
3. Antes de transmitir, el cliente guarda el paquete cifrado en una cola de archivos atómicos por cuenta. Los reintentos reutilizan el mismo identificador y sobre.
4. El servidor valida la identidad de la conexión y el enrutamiento del sobre; guarda el paquete y responde `queued_on_server`. Esto significa «enviado», no «entregado».
5. El destinatario verifica, descifra y guarda el contenido; los adjuntos deben descargarse y descifrarse antes de confirmar. Entonces envía `message_received`, con `messageId` y `originalSenderId`.
6. Solo esa identidad destinataria puede confirmar la entrega. El servidor responde al emisor `delivery_ack/delivered`. Un envío duplicado conserva la aceptación o entrega anterior.

`DurableRelay` concentra aceptación idempotente, consulta de pendientes y confirmación. El adaptador actual usa transacciones SQLite, WAL y sincronización FULL. La tabla anterior `offline_messages` se conserva; no se retransmiten como mensajes v2 los cuerpos antiguos sin cifrado. El despliegue requiere actualizar cliente y servidor juntos.

El transporte hace entrega **al menos una vez**. El cliente deduplica por identificador y comprueba el emisor antes de modificar un registro existente. No se promete entrega exactamente una vez en cualquier circunstancia, sincronización de historial entre dispositivos ni recibos de entrega recuperados por el emisor después de toda desconexión.

Las cuentas nuevas usan identificadores derivados de UUID completos, conservando los identificadores anteriores durante la migración. Se eliminó la generación de IDs de cuatro caracteres, cuyo espacio era demasiado pequeño para este objetivo.

### Límites actuales

- WebSocket: 256 KiB por trama; sobre cifrado: máximo 192 KiB en el relay.
- Texto del compositor: 64 KiB; contenido cifrado nativo: 128 KiB. Los archivos se suben por HTTP cifrados, no como tramas de vídeo.
- Recuperación: lotes de 50 mensajes; consumidor con más de 1 MiB de datos pendientes se desconecta para reanudar después.
- Autenticación: máximo 15 segundos antes de cerrar una conexión sin autenticar.
- Cola por destinatario: 10.000 mensajes o 64 MiB; si está llena el emisor conserva el pendiente y recibe un error.
- Confirmaciones del servidor conservadas siete días; mensajes pendientes sin expiración automática. Falta política operativa de almacenamiento, retención y borrado.
- Reintento del cliente con espera creciente y variación aleatoria, sin abandonar permanentemente después de ocho intentos.

Estos límites protegen el entorno actual; no son un dimensionamiento para producción. Tampoco bastan para controlar carga distribuida, tráfico abusivo o el consumo global de disco.

## Arquitectura siguiente

| Capa | Responsabilidad | Cambio respecto al código actual |
|---|---|---|
| Balanceador regional TLS | WSS/HTTPS, límites de conexión, drenado de nodos | Dominio, certificado y proveedor pendientes |
| Gateways WebSocket sin estado duradero | Autenticar, mantener sockets locales, aplicar límites, reenviar paquetes | Varias instancias; no usar mapas locales como directorio global |
| Directorio de sesiones compartido | Propietario de cada conexión, caducidad y revocación | Redis particionado con arrendamientos; no escribir PostgreSQL en cada latido |
| Almacenamiento de mensajes | Aceptación transaccional, idempotencia, pendientes y recibos | Adaptador asíncrono PostgreSQL particionado por destinatario y réplicas; sustituir SQLite |
| Despacho | Avisar al gateway tras confirmar la transacción | Outbox transaccional y trabajadores; recuperar de la base cuando se pierde un aviso |
| Archivos | Subida directa de contenido cifrado, descargas y cuotas | URLs temporales, almacenamiento de objetos/CDN; sacar buffers grandes de Node |
| Operación | Métricas, trazas sin contenido, alertas, copias y restauración | Verificación de fallos, límites de costo y capacidad |

Redis Pub/Sub no debe ser la única copia del mensaje: su entrega es como máximo una vez y una desconexión puede perder el aviso. El diseño propuesto lo usa únicamente para despertar al gateway; los mensajes siguen en el almacenamiento duradero. [Documentación de Redis](https://redis.io/docs/latest/develop/pubsub/).

Una confirmación de aceptación debe esperar el commit duradero. En PostgreSQL, el commit asíncrono puede perder transacciones recientes ante una caída; para la política de supervivencia a la pérdida de un nodo también habrá que configurar y probar replicación síncrona y failover. [Documentación de PostgreSQL](https://www.postgresql.org/docs/current/wal-async-commit.html).

## Carga que hay que medir

Un millón de conexiones con un latido cada 25 segundos equivale a 40.000 latidos por segundo, más sus respuestas. Si el 10% envía un mensaje cada diez segundos, son 10.000 mensajes por segundo antes de contar grupos, archivos, recibos o reintentos. Son **supuestos de planificación**, no resultados medidos.

No fijar número de servidores por intuición. Medir memoria por conexión autenticada, CPU para autenticaciones, descriptores disponibles, caudal de escritura, latencia p95/p99, buffers, retraso de cola y ancho de banda TLS. Separar conexiones ociosas, usuarios escribiendo, fanout de grupos y llamadas.

Validación por etapas: 1.000 → 10.000 → 100.000 → 1.000.000 conexiones reales, con generadores distribuidos, subida gradual y carga sostenida. En cada etapa comprobar:

- Cero pérdida de mensajes cuya aceptación se haya confirmado; comparar IDs enviados, persistidos y recibidos.
- Reintentos, destinatarios lentos, reinicio de gateways, pérdida de un nodo de datos y reconexión masiva.
- Ausencia de duplicados visibles, uso de memoria estable, colas con límite y recuperación tras saturación.
- Latencia objetivo y tasa de errores acordadas antes de ejecutar la prueba.
- Presupuesto de infraestructura y tráfico aprobado para el entorno de carga.

No ejecutar carga de este tamaño sobre producción ni anunciar esa capacidad antes de completar estas mediciones.

## Límites funcionales y de seguridad pendientes

El primer contacto confía en el directorio servido por TLS; después se fija la clave y se rechazan cambios inesperados. HPKE autenticado no es Signal Double Ratchet y no ofrece recuperación posterior al compromiso de la clave privada del destinatario. La experiencia de verificar huellas y recuperar/rotar claves requiere revisión independiente.

Quedan por cerrar: grupos e invitaciones protegidos, programación cifrada, comportamiento completo multidispositivo, llamadas y walkie-talkie auditados, APNs real, eliminación de cuenta, declaración de privacidad y prueba en dos iPhone físicos. El servidor conserva rutas heredadas de señalización y de grupos; no presentar todo el producto como auditado de extremo a extremo.

Para conectar producción se necesita el dominio y proveedor que el titular indicó que compartirá. Los cambios actuales no se han publicado ni han modificado servidores públicos.

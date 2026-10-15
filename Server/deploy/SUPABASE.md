# Supabase: conexión de desarrollo de Myaow

Actualizado: 3 de octubre de 2026. Están desplegadas identidad, entrega cifrada, grupos, tareas, programación y adjuntos privados: 17 tablas privadas, catorce migraciones, myaow-api v6 y myaow-push v3 (credenciales configuradas; cola desactivada hasta probar la build de producción). Myaow Pilot está instalado en el simulador y se probó desde sus pantallas. El plan continúa gratuito. Estado detallado y límites: [supabase/README.md](../../supabase/README.md).

## Proyecto confirmado mediante la integración

- Organización: **Odiseo Labs** (`exiuxfzrlxxvphulzbcg`).
- Plan: **Free** (`tier_free`).
- Proyecto: **Myaow** (`your-project-ref`).
- Estado: **ACTIVE_HEALTHY**.
- Región: `us-east-1`.
- API: `https://your-project-ref.supabase.co`.
- Panel: https://supabase.com/dashboard/project/your-project-ref
- Tablas de aplicación: 17 en `myaow_private`; ninguna expuesta directamente a clientes.
- Edge Functions: `myaow-api` v6 activa y `myaow-push` v3 desplegada, con credenciales configuradas y la cola de envíos todavía desactivada hasta verificar la build de producción.
- Asesor de seguridad: sin avisos tras aplicar migraciones y políticas. Esto no equivale a una auditoría completa de la app.

La URL y las referencias anteriores son identificadores públicos, no secretos. No se copiaron claves privadas al repositorio.

## Usar la conexión correcta

La CLI local consultada anteriormente listaba otro proyecto, **Mytu**, inactivo (`yixazzzllzdencgasaud`). No asumir que esa sesión corresponde a esta conexión. Usar la integración y el identificador de Myaow indicado arriba. Antes de usar CLI para desplegar, verificar su cuenta y destino; no reactivar ni modificar Mytu como parte de este trabajo.

## Trabajo pendiente para completar la migración

La app habitual mantiene su configuración Node/SQLite. La copia `com.ScendLabs.Myaow.SupabasePilot` ya está instalada con cuenta y datos separados. El registro se abrió por invitación de un uso con autorización del usuario y volvió a cerrarse tras probarlo.

1. Probar con dos iPhone y reconexión física. El 1–2 de octubre se completaron foto, audio y documento desde las pantallas del piloto, con asistencia del usuario en los selectores nativos y descifrado confirmado por el receptor de prueba. Ya se verificaron desde pantalla registro, recepción de texto/foto/audio/archivo, reproducción de audio, apertura de documento, envío de texto y conservación del historial tras actualizar. La subida cifrada y el reintento idempotente pasaron contra el backend con el cliente Swift compartido; las interrupciones de conexión se comprobaron con el cliente HTTP y respuestas interceptadas antes y después del commit.
2. Grupos, tareas y programación probados desde las pantallas del piloto el 2–3 de octubre, incluyendo recepción en tiempo real, avances, entrega con el proceso cerrado y cancelación. La aceptación de invitaciones se probó con el cliente Swift compañero; falta completar ambos lados desde dos iPhone y verificar bloqueos desde sus pantallas. Faltan borrado/recuperación de cuenta y limpieza automática de reservas/adjuntos huérfanos. Los adjuntos grupales siguen deshabilitados.
3. Realtime integrado y probado el 2 de octubre: avisos privados por sesión, descarga autenticada, reconexión y respaldo HTTP. Faltan mediciones de carga y consumo; esto no valida mensajería a gran escala. Véase `Review/2026-10-02/Realtime-Grupos/REVISION.md`.
4. Activar y probar APNs real: secretos de Apple y credencial interna/Vault ya configurados; worker autenticado verificado. Faltan una compilación firmada de producción, separación de destinos sandbox y prueba de entrega en iPhone bloqueado. La programación cifrada se despacha mediante cron cada minuto, incluso con la sesión del remitente cerrada; no genera todavía alertas de Apple. Ver `Review/2026-10-03/APNs/CONFIGURACION.md`.
5. Integrar TURN con credenciales temporales y validar llamadas entre redes distintas.
6. Preparar una compilación de distribución conectada a Supabase, firmarla y verificarla en TestFlight. La instalación Debug del piloto no acredita la configuración de la aplicación habitual ni la distribución a testers.

Storage es privado y los adjuntos se cifran en el cliente. Límite por archivo: 10 MiB; por autor: 40 MiB; global del piloto: 200 MiB. Las reservas cuentan en esas cuotas. El servidor exige sesión, destinatario y permisos actuales; compartir la URL no concede acceso. Radio local conserva su transporte propio.

Se usará inicialmente la URL gratuita del proyecto. El dominio odisseolabs.com permanece en GoDaddy y sus DNS no han cambiado. La configuración Docker de BETA.md describe la alternativa anterior de servidor propio; no es una configuración ya desplegada ni un requisito para usar Supabase.

No activar planes de pago, ramas de pago ni complementos al avanzar sobre este proyecto gratuito. Los límites del plan y el consumo deben verificarse antes de abrir acceso a usuarios.

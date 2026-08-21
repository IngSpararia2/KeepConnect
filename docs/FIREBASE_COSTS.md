# Costos, planes y controles de consumo de Firebase

> Verificado contra documentación oficial el **14 de agosto de 2026**. Firebase y Google Cloud pueden cambiar precios, cuotas y nombres de interfaz; antes de pasar a producción conviene volver a consultar los enlaces oficiales de esta página.

## Decisión para este proyecto

La versión productiva de **Gestión Interna** necesita el plan **Blaze (pago por uso)**. No es una decisión opcional de arquitectura:

- Cloud Functions desplegadas no están disponibles en Spark. Las Functions son el backend confiable que genera códigos, valida transiciones, conserva auditoría y envía FCM.
- Desde el **3 de febrero de 2026**, Cloud Storage for Firebase exige Blaze para todos los proyectos. En Spark, las peticiones al bucket real fallan con HTTP 402/403.
- Blaze no significa que exista un cargo fijo mensual por Firebase. Conserva cuotas sin costo y factura únicamente los excesos y los productos que no tengan cuota gratuita.
- Blaze sí exige enlazar una cuenta de Cloud Billing y, por tanto, permite que un error de programación o un uso inesperado genere cargos. Los presupuestos son avisos; por sí solos no detienen el consumo.

Fuentes: [planes de precios de Firebase](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans), [cambio de facturación de Storage](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024) y [tabla vigente de precios](https://firebase.google.com/pricing).

Durante el desarrollo se puede trabajar con `demo-gestion-interna` y Firebase Emulator Suite sin consumir los servicios reales. FCM no tiene emulador: la prueba push final necesita un proyecto real.

## Qué funciona en Spark y qué exige Blaze

| Capacidad | Spark | Blaze | Aplicación en este proyecto |
|---|---:|---:|---|
| Authentication Email/Password | Sí | Sí | Login, sesión y recuperación de contraseña. |
| Firestore Standard | Sí, dentro de cuota | Sí, cuota sin costo + exceso facturable | Tickets, perfiles, comentarios y auditoría. |
| FCM | Sí, sin costo | Sí, sin costo | La recepción y el compositor de pruebas funcionan; el envío automático de esta app depende de Functions. |
| App Check | Sí | Sí | Capa adicional contra clientes no legítimos; no sustituye Auth ni Rules. |
| Emulator Suite | Sí, local | Sí, local | Auth, Firestore, Functions y Storage locales. |
| Cloud Functions desplegadas | **No** | **Sí** | Obligatorias para callables, triggers y escalamiento automático. |
| Cloud Storage real | **No desde 2026-02-03** | **Sí** | Obligatorio para fotografías/evidencias reales. |
| Cloud Scheduler | No es utilizable sin desplegar Functions | Sí | Ejecuta `checkOverdueTickets` cada cinco minutos. |

No se debe intentar evitar Blaze colocando credenciales administrativas o una FCM Server Key dentro del APK. Eso convertiría cualquier instalación de la app en un servidor privilegiado y comprometería todos los datos.

## Cuotas gratuitas relevantes

Las cifras siguientes son las publicadas el 14 de agosto de 2026. Se aplican al proyecto, no a cada aplicación o usuario.

### Cloud Firestore Standard

- 1 GiB de datos almacenados.
- 50.000 lecturas de documentos por día.
- 20.000 escrituras de documentos por día.
- 20.000 eliminaciones de documentos por día.
- 10 GiB de salida de red al mes.
- Solo una base de datos por proyecto recibe la cuota gratuita.

Las cuotas diarias se reinician aproximadamente a medianoche, hora del Pacífico. TTL, copias de seguridad, restauraciones, PITR y clonación no tienen cuota gratuita de Firestore y requieren facturación. Fuente: [precios de Cloud Firestore](https://firebase.google.com/docs/firestore/pricing).

### Authentication

- Los servicios habituales, incluido Email/Password sin Identity Platform, aparecen como disponibles sin costo en ambos planes.
- Si se actualiza el proyecto a **Identity Platform**, la tabla vigente incluye 50.000 usuarios activos mensuales sin costo para proveedores habituales y 50 MAU para SAML/OIDC; después se factura.
- El envío de correos tiene límites operativos. La documentación vigente indica, entre otros, 150 correos de restablecimiento de contraseña por día en Spark y 10.000 por día en Blaze. No se deben usar estas cifras como un servicio de correo masivo.
- La autenticación telefónica/SMS se factura aparte y no se utiliza en este MVP.

Fuentes: [precios de Firebase Authentication](https://firebase.google.com/pricing) y [límites de Authentication](https://firebase.google.com/docs/auth/limits).

### Cloud Functions

Blaze incluye actualmente:

- 2 millones de invocaciones al mes.
- 400.000 GB-segundo al mes.
- 200.000 CPU-segundo al mes.
- 5 GB de red saliente al mes.
- 120 minutos de Cloud Build por día.
- 500 MB de almacenamiento de contenedores en Artifact Registry.

Sobrepasar cualquiera de esos conceptos puede producir cargos aunque los demás permanezcan dentro de cuota. Desplegar repetidamente crea imágenes en Artifact Registry; por ello se debe conservar la política de limpieza y vigilar sus 500 MB. Fuente: [precios de Firebase](https://firebase.google.com/pricing) y [administración de Functions](https://firebase.google.com/docs/functions/manage-functions).

Configuración de ahorro adoptada:

- Node.js 22 y Cloud Functions de segunda generación.
- Región única `us-central1`, junto a Firestore y Storage.
- `minInstances` no se establece y conserva el valor predeterminado cero; no se pagan instancias calientes ociosas.
- `maxInstances: 30` y `concurrency: 40` se fijan globalmente para frenar el escalado accidental.
- Triggers idempotentes y `notification_jobs/{eventId}` para no enviar dos veces el mismo evento.
- Consultas del programador limitadas a tickets candidatos; no recorre toda la colección.

### Cloud Scheduler

`checkOverdueTickets` usa un solo trabajo programado, cada cinco minutos y con zona horaria `America/Bogota`. Cloud Scheduler cobra USD 0,10 por trabajo/mes y ofrece tres trabajos sin costo por cuenta de facturación; por tanto, este único trabajo debería entrar en esa franquicia si la cuenta no la ha consumido con otros proyectos. La ejecución de la Function se contabiliza además en Cloud Functions. Fuente: [precios de Cloud Scheduler](https://cloud.google.com/scheduler/pricing) y [Functions programadas](https://firebase.google.com/docs/functions/schedule-functions).

### Cloud Storage

Un bucket nuevo usa el nombre `PROJECT_ID.firebasestorage.app`. Para obtener la capa Always Free de Google Cloud Storage se debe crear en `us-central1`, `us-east1` o `us-west1`. Este proyecto estandariza **`us-central1`** para evitar tráfico entre regiones.

Cuota publicada para `*.firebasestorage.app` y buckets adicionales elegibles:

- 5 GB-mes almacenados.
- 100 GB descargados al mes.
- 5.000 operaciones de carga al mes.
- 50.000 operaciones de descarga al mes.

Los buckets heredados `*.appspot.com` conservan en Blaze otra cuota: 5 GB almacenados, 1 GB descargado por día, 20.000 cargas por día y 50.000 descargas por día. No se debe borrar un bucket heredado solo para cambiar el nombre.

Fuentes: [FAQ oficial del cambio de Storage](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024), [precios de Firebase](https://firebase.google.com/pricing), [precios de Cloud Storage](https://cloud.google.com/storage/pricing) y [ubicaciones de Storage](https://firebase.google.com/docs/storage/locations).

Qué aumenta el costo de fotografías:

- Conservar originales grandes.
- Reintentos de carga que crean objetos diferentes.
- Abrir una imagen completa en cada renderizado en lugar de usar caché/miniatura.
- Listar carpetas completas en Storage en lugar de leer metadatos paginados de Firestore.
- Elegir un bucket fuera de una región Always Free.

La selección/captura solicita un máximo aproximado de 1600×1600 y calidad 75 cuando el codec de Android lo permite; después aplica un límite duro de 5 MiB, valida tipo/tamaño mediante Rules y registra la ruta en `tickets/{ticketId}/attachments/{attachmentId}`. HEIC y otros formatos pueden comportarse de forma distinta según el dispositivo, por lo que el hard cap es la protección definitiva. La imagen nunca se almacena en Base64 dentro de Firestore.

Las Storage Rules consultan el perfil y el ticket mediante `firestore.get()`/`exists()` para autorizar cada objeto. Esas lecturas cuentan para cuota/facturación de Firestore incluso si la petición se deniega; Firebase limita además a dos documentos Firestore por evaluación de Storage Rules. Fuente: [condiciones de Cloud Storage Security Rules](https://firebase.google.com/docs/storage/security/rules-conditions#enhance_with_cloud_firestore).

### Firebase Cloud Messaging

FCM no tiene costo. La cuota predeterminada de envío downstream publicada es 600.000 **mensajes** por minuto y por proyecto; la cuota mide mensajes, no peticiones, y es una restricción técnica, no una tarifa. Una respuesta HTTP 429 indica limitación y debe respetarse `retry-after`. El costo asociado en este sistema proviene de la Function que lee destinatarios y envía el mensaje, no del mensaje FCM. Fuentes: [Firebase Cloud Messaging](https://firebase.google.com/products/cloud-messaging) y [cuotas de FCM](https://firebase.google.com/docs/cloud-messaging/throttling-and-quotas).

### App Check

App Check es un producto sin costo, sujeto a las cuotas del proveedor de certificación. En Android, Play Integrity Standard tiene una cuota diaria publicada de 10.000 solicitudes. El SDK renueva el token aproximadamente a la mitad de su TTL; acortar el TTL incrementa certificaciones y puede agotar cuota. Fuente: [App Check](https://firebase.google.com/docs/app-check) y [configuración Flutter](https://firebase.google.com/docs/app-check/flutter/default-providers).

## Cómo consume Firestore esta app

### Lecturas

Se factura una lectura por cada documento que una consulta devuelve, con un mínimo de una lectura incluso si no devuelve resultados. Algunas consultas también cobran lecturas de entradas de índice; el detalle depende de los campos de rango. Las reglas que consultan otros documentos mediante `get()`/`exists()` pueden sumar lecturas.

Un listener en tiempo real cobra los documentos añadidos o actualizados y los que salen del resultado por un cambio. Si el cliente se reconecta después de más de 30 minutos con persistencia offline habilitada, normalmente la consulta se factura como nueva; sin persistencia, cada reconexión se trata como consulta nueva.

Medidas del proyecto:

- Consultas por rol y estado, nunca un listener global a todos los tickets.
- Límites y paginación para historial/listados.
- El detalle escucha un único ticket y sus subcolecciones relevantes.
- Filtros respaldados por `firestore.indexes.json`.
- Búsqueda MVP por campos normalizados; no se escanea toda la colección como un buscador de texto completo.
- Cursores (`startAfter`) en vez de offsets, porque los documentos omitidos por un offset también se cobran.

### Escrituras

Una acción puede producir varias escrituras legítimas: cambio del ticket, evento de auditoría, comentario o attachment y trabajo de notificación. No se debe actualizar `lastSeenAt` en cada reconstrucción de pantalla ni escribir contadores visuales continuamente. Los timestamps críticos los fija el servidor.

### Índices y almacenamiento

Cada índice consume almacenamiento. Solo se versionan los índices de consultas reales. Documentos con arreglos grandes o texto duplicado pueden multiplicar entradas; comentarios, eventos y adjuntos son subcolecciones paginables en vez de arreglos crecientes dentro del ticket.

Fuente para el modelo completo: [precios de Cloud Firestore](https://firebase.google.com/docs/firestore/pricing).

## Presupuesto y alertas: configuración obligatoria

1. En [Firebase Console](https://console.firebase.google.com/), abra el proyecto real.
2. Pulse el engranaje **Project settings / Configuración del proyecto**.
3. Entre en **Usage and billing / Uso y facturación** y luego **Details & settings / Detalles y configuración**.
4. En **Budgets & Alerts / Presupuestos y alertas**, pulse **Create first budget / Crear primer presupuesto**. Se abrirá Cloud Billing.
5. Elija la cuenta de facturación, limite el alcance al proyecto de Gestión Interna y, para la primera alerta, seleccione todos los servicios.
6. Defina un monto fijo mensual pequeño que Samuel considere aceptable. No se incluye una cifra universal porque depende de la moneda, tolerancia y otros proyectos de la misma cuenta.
7. Para desarrollo inicial, Google recomienda probar varios umbrales de consumo real, por ejemplo 1 %, 2 %, 5 % y 50 %. Para producción, recomienda hitos como 50 % y 100 % real, y 150 % previsto. Para este MVP también es razonable añadir 75 % y 90 % si no genera fatiga de alertas.
8. Añada como destinatarios al propietario técnico y a quien administre la facturación. Para correos ajenos a los roles de Billing se puede configurar un canal de notificación de Cloud Monitoring.
9. Cree, si está disponible para la cuenta, un **budget spend cap** específico para Cloud Run functions. En 2026 los spend caps solo cubren servicios seleccionados; no son un límite global para Firestore y Storage.
10. Compruebe que llega un correo de prueba o que el destinatario aparece correctamente.

**Advertencia:** los presupuestos y alertas no detienen uso ni cargos y pueden llegar con horas o días de demora. Los spend caps tampoco actúan instantáneamente y no cubren todos los productos. Fuente: [evitar facturas inesperadas](https://firebase.google.com/docs/projects/billing/avoid-surprise-bills) y [presupuestos de Cloud Billing](https://cloud.google.com/billing/docs/how-to/budgets).

## Controles técnicos antes de producción

- [ ] Proyecto real enlazado a Blaze con un presupuesto y destinatarios verificados.
- [ ] Firestore, Functions y Storage en `us-central1`.
- [ ] Emuladores usados para seed, reglas y pruebas repetitivas.
- [ ] `minInstances` permanece en su valor predeterminado cero.
- [ ] `maxInstances: 30` y `concurrency: 40` siguen configurados y revisados.
- [ ] `checkOverdueTickets` consulta por `isOpen` y `nextAutomaticEscalationAt`, limita a 100 candidatos y valida estado/prioridad dentro de cada transacción.
- [ ] Fotografías reducidas cuando el codec lo permita y siempre limitadas a 5 MiB por configuración y Rules.
- [ ] Listas y subcolecciones paginadas.
- [ ] Tokens/FIDs inválidos se eliminan; no se reintenta eternamente.
- [ ] Triggers idempotentes; una entrega duplicada de Firestore no duplica notificaciones.
- [ ] No hay bucles donde una Function actualice un documento y se vuelva a disparar sin condición.
- [ ] Artifact Registry tiene política de limpieza y menos de 500 MB si se desea permanecer en cuota.
- [ ] Dashboard de **Usage and billing** y logs revisados después de cada despliegue.

## Señales que requieren investigación inmediata

- Crecimiento de lecturas sin crecimiento similar de usuarios.
- Muchas invocaciones de `onTicketUpdated` para una sola acción.
- Escrituras repetidas en `notification_jobs` o escaladas duplicadas.
- FCM con gran cantidad de destinatarios inválidos.
- Egreso de Storage alto respecto al número de adjuntos.
- Cloud Scheduler ejecutándose pero sin tickets candidatos y aun así generando muchas lecturas.
- Imágenes de Functions acumuladas en Artifact Registry.

El procedimiento de alta y despliegue está en [FIREBASE_SETUP.md](FIREBASE_SETUP.md). La justificación de colecciones, índices e idempotencia está en [ARCHITECTURE.md](ARCHITECTURE.md).

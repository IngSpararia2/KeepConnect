# Plan de pruebas

Este documento separa deliberadamente tres cosas distintas:

1. Pruebas puras y de widgets, rápidas y sin Firebase.
2. Pruebas integradas contra Emulator Suite, sin costo ni datos reales.
3. Pruebas FCM/Android en un proyecto real y teléfonos físicos.

Una notificación simulada o un log local **no demuestra** que FCM real funciona. La aceptación de push requiere la sección “Prueba completa con dos celulares”.

## 1. Preparación

Desde PowerShell:

```powershell
Set-Location 'C:\Users\itopa\Desktop\Proyectos Coding\KeepConnect'
flutter --version
node --version
firebase --version
```

Versiones objetivo: Flutter 3.44.7, Dart 3.12.2 y Node 22.

Instale dependencias:

```powershell
flutter pub get
corepack enable
pnpm --dir functions install --frozen-lockfile
pnpm --dir scripts install --frozen-lockfile
```

No guarde contraseñas ni tokens reales en este archivo, código o capturas públicas.

## 2. Calidad estática y suites automatizadas

Ejecute desde la raíz:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
npm --prefix functions run build
npm --prefix functions run lint
npm --prefix functions test
npm --prefix scripts run build
```

Resultado aceptable:

- Todos los comandos terminan con código 0.
- `flutter analyze` no muestra issues.
- No hay tests omitidos para “hacer pasar” la suite.
- El TypeScript compilado usa Node 22.

### Lógica crítica que debe permanecer cubierta

**Flutter/Dart**

- Sugerencia de prioridad: baja, media, alta y crítica.
- Riesgo de seguridad fuerza crítica.
- Producción detenida + Columbia 21 crítica fuerza crítica.
- Grafo de estados y permisos por rol/relación.
- Parseo de modelos Firestore y valores ausentes.
- Ruta de notificación válida/inválida.
- Widgets de prioridad/estado y pantallas principales.

**Functions/TypeScript**

- La misma política de prioridad; no debe divergir del cliente.
- Validación de payloads y límites.
- Categoría, activo, plantilla activa/versionada y respuestas dinámicas validadas en servidor.
- Transiciones permitidas/denegadas.
- Autorización y timestamps de `updateProductionImpact`.
- Cooldown de escalamiento.
- Cálculo de vencimiento/fecha `America/Bogota`.
- Exclusión del actor y deduplicación de dispositivos.
- Reintentos con el mismo `requestId` y `notification_jobs/{eventId}`.

Si se cambia un peso, estado o nombre persistido, actualice ambas suites y la configuración/seed en el mismo cambio.

## 3. Emulator Suite

### 3.1 Iniciar servicios

Terminal 1:

```powershell
firebase emulators:start --project demo-gestion-interna --only "auth,firestore,functions,storage"
```

Abra [http://127.0.0.1:4000](http://127.0.0.1:4000) y confirme:

| Emulador | Puerto |
|---|---:|
| Auth | 9099 |
| Firestore | 8080 |
| Functions | 5001 |
| Storage | 9199 |
| UI | 4000 |

Auth/Firestore/Functions/Storage escuchan en `0.0.0.0` para clientes Android de la LAN; UI escucha solo en `127.0.0.1`. Pruebe exclusivamente en una red privada, con Firewall restringido y sin port forwarding.

La build debug permite cleartext para alcanzar Functions Emulator por HTTP; la excepción vive solo en `android/app/src/debug/AndroidManifest.xml`. Antes de entregar release, confirme que `src/main` no contiene `usesCleartextTraffic="true"`.

Firestore Emulator se vacía al cerrarlo, pero Android conserva por separado la caché offline. Cuando una prueba requiera un estado realmente limpio, borre los datos de la app/reinstálela además de reiniciar o limpiar el emulador; no confunda un documento cacheado con un documento presente en Emulator UI.

Terminal 2:

```powershell
npm --prefix scripts run seed
```

En Emulator UI deben existir al menos:

- departamentos `production` y `maintenance`;
- módulo `maintenance`;
- activo Columbia 21, `critical=true`;
- categorías;
- plantilla dinámica activa;
- `settings/maintenance` con escalamiento demo.

### 3.2 Ejecutar la aplicación local

Android Emulator:

```powershell
flutter run --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
```

Teléfono físico en la misma LAN, sustituyendo la IP:

```powershell
flutter run --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.25
```

En modo emulador FCM queda deshabilitado/representado por logs. No inyecte credenciales reales para “hacerlo funcionar”.

### 3.3 Usuarios locales

Cree usuarios en la pestaña Auth de Emulator UI o con el script administrativo. Cree después su perfil `users/{uid}` con rol/departamento correspondiente. Necesita al menos:

- Planta: `role=production`, `departmentId=production`, `active=true`.
- Técnico: `role=maintenance`, `departmentId=maintenance`, `active=true`.
- Admin opcional: `role=admin`, uno de los departamentos existentes (`production` o `maintenance`) y `active=true`; no existe un departamento `admin` en el seed.

Use direcciones reservadas como `planta@example.test`; las contraseñas son solo locales y no se documentan.

## 4. Pruebas funcionales locales

### Caso L-01: sesión y perfil

1. Abra sin sesión: debe mostrar Login, no Home.
2. Introduzca credenciales incorrectas: mensaje comprensible, sin stack trace.
3. Inicie sesión con Planta: debe mostrar Home y tarjeta Mantenimiento.
4. Cierre/reabra la app: la sesión debe persistir.
5. Con red, cierre sesión: vuelve a Login y se elimina el device doc de esa instalación cuando FCM está habilitado. Repita sin red: el logout no debe quedar bloqueado; documente que la limpieza es *best effort* y verifique que un siguiente login reasigna instalación/token a un único dueño.
6. Establezca `active=false`: la app debe impedir acceso incluso con Auth válido.

### Caso L-02: creación y código concurrente

1. Cree un ticket normal desde Planta.
2. Confirme que el ID Firestore es interno y `humanCode` sigue `MTTO-YYYYMMDD-NNNN`.
3. Confirme evento `ticketCreated` con actor/timestamp.
4. Lance dos creaciones casi simultáneas desde dos clientes.
5. Los códigos deben ser distintos y consecutivos; no debe existir colisión.
6. Reenvíe la misma petición con igual `requestId`: no debe crear otro ticket.

### Caso L-03: prioridad sugerida

Pruebe al menos:

| Producción detenida | Riesgo | Activo crítico | Resultado esperado demo |
|---:|---:|---:|---|
| No | No | No | Baja salvo afectación adicional. |
| No | No | Sí | Media. |
| Sí | No | No | Alta con afectación menor de 75 %; Crítica desde 75 % en la política demo. |
| No | Sí | Cualquiera | Crítica. |
| Sí | No | Sí (Columbia 21) | Crítica. |

Si el usuario selecciona una prioridad **menor** que la sugerida, debe requerirse motivo. El ticket debe guardar sugerida, elegida, motivo, actor y timestamp; `ticketCreated` registra las prioridades elegida/sugerida. Un cambio posterior mediante `updatePriority` sí exige motivo y crea `priorityChanged`. Estos criterios son demo configurables, no una norma industrial.

### Caso L-04: parada y reanudación de producción

1. Como solicitante de Producción, abra un ticket no terminado con `productionStopped=true`.
2. Pulse **Producción reanudada**, indique un motivo y confirme.
3. Verifique `productionStopped=false`, `productionResumedAt` de servidor y evento `productionImpactChanged`; Mantenimiento debe recibir una notificación normal y el actor no debe auto-notificarse.
4. Pulse **Reportar parada**, indique motivo y confirme.
5. Verifique `productionStopped=true`, un nuevo `productionStoppedAt`, `productionResumedAt=null`, otro evento y notificación urgente.
6. Repita el mismo valor o intente omitir el motivo: debe fallar sin escritura/evento.
7. Un técnico de Mantenimiento o un solicitante ajeno debe recibir denegación; admin sí puede actualizar.
8. En `closed`/`cancelled`, la acción debe estar oculta y la callable debe rechazarla.

Cambiar este impacto no recalcula automáticamente la prioridad existente; pruebe `updatePriority` por separado si operativamente corresponde.

### Caso L-05: flujo de estados y permisos

Secuencia válida:

```text
pending -> acknowledged -> assigned -> inProgress -> waitingParts -> inProgress -> resolved -> closed
```

También pruebe `waitingExternal` y `paused` regresando a `inProgress`.

Intentos que deben fallar:

- Producción cambia `pending` directamente a `resolved`.
- Mantenimiento pasa `pending` directamente a `inProgress`.
- Técnico no participante inicia trabajo de un ticket asignado a otra persona.
- Mantenimiento cierra un ticket resuelto sin confirmación del solicitante.
- Solicitante modifica un ticket `closed`.
- Usuario normal escribe el estado directamente en Firestore.

### Caso L-06: resolución y reapertura

1. En `inProgress`, intente resolver sin diagnóstico/trabajo requerido: debe fallar.
2. Complete diagnóstico, trabajo realizado y observación; pase a `resolved`.
3. Como solicitante, elija solicitar revisión: vuelve a `inProgress`, aumenta `reopenCount` y crea evento `ticketReopened`.
4. Resuelva otra vez y confirme cierre: `closedAt` y `closedByUid` deben quedar.

### Caso L-07: comentarios

1. Planta agrega comentario.
2. Debe aparecer en tiempo real en Mantenimiento.
3. Actor/fecha deben venir del backend; no de texto manipulable.
4. Texto vacío/excesivo debe rechazarse.
5. Usuario no autorizado no puede leer/escribir la subcolección.

### Caso L-08: evidencia

1. Seleccione una imagen normal.
2. El picker solicita máximo aproximado 1600×1600 y calidad 75 cuando Android/codec lo permite.
3. Confirme objeto en `tickets/{ticketId}/{attachmentId}/{fileName}` y metadata en `attachments`.
4. Confirme evento `attachmentAdded` y `attachmentCount`.
5. Una imagen mayor de 5 MiB después del procesamiento debe rechazarse.
6. Un archivo con MIME no imagen, ruta de otro ticket o sobrescritura debe fallar en Rules/backend.
7. HEIC puede no respetar exactamente JPEG quality; el límite de bytes debe seguir bloqueando exceso.

### Caso L-09: búsqueda/filtros

- Código exacto/parcial normalizado.
- Título y equipo según tokens soportados.
- Estado, prioridad, equipo, producción detenida, área y categoría.
- Resultado vacío claro.
- Ninguna consulta carga toda la base sin límite.

La búsqueda MVP no es full-text: documente cualquier palabra que no pueda encontrarse por el esquema de tokens.

## 5. Pruebas de Security Rules

Ejecute tests de reglas contra emuladores cuando estén disponibles mediante el script del repositorio. Como mínimo, automatice o verifique manualmente esta matriz:

| Operación maliciosa | Resultado esperado |
|---|---|
| No autenticado lee tickets/usuarios | Denegado. |
| Production lee ticket de otro solicitante no compartido | Denegado. |
| Production cambia su `role` a `admin` | Denegado. |
| Usuario activo cambia `active`/`departmentId` | Denegado. |
| Cliente crea/actualiza un ticket o escribe directamente comentario/metadata de attachment | Denegado; debe usar callable. |
| Cliente crea/edita/borra evento de auditoría | Denegado. |
| Usuario escribe directamente cualquier device doc, incluso el propio | Denegado; debe usar `registerDevice`/`unregisterDevice`. |
| `registerDevice` autenticado registra una instalación/token ya ligada a otra cuenta de prueba | La asociación anterior se limpia y queda un solo propietario. |
| `unregisterDevice` intenta retirar una instalación ajena | No borra los índices del dueño real. |
| Mantenimiento de otra área lee/gestiona ticket | Denegado. |
| Cliente escribe `_command_receipts`, `notification_jobs` o `counters` | Denegado. |
| Participante carga imagen válida en su ruta | Permitido. |
| No participante carga/lee imagen | Denegado. |
| Archivo mayor de 5 MiB o MIME no imagen | Denegado. |
| Uploader borra su objeto después de fallar `registerAttachment`, sin documento de metadata | Permitido como limpieza huérfana. |
| Uploader intenta borrar el objeto después de existir `attachments/{attachmentId}` | Denegado; evidencia registrada inmutable. |
| Otro usuario intenta borrar la subida huérfana | Denegado. |

Las callables usan Admin SDK y omiten Rules; por eso cada una debe repetir autorización, validación y perfil activo. Una prueba de Rules exitosa no sustituye tests de Functions.

## 6. Prueba completa con dos celulares

### Precondiciones

- Proyecto real en Blaze.
- Auth, Firestore y Storage creados en `us-central1`.
- Rules, índices y Functions desplegados.
- Dos usuarios Auth + perfiles activos.
- APK/build real instalada en dos teléfonos físicos con Internet y Google Play Services.
- Permiso de notificaciones concedido.
- Ambos canales Android habilitados.

No use `USE_FIREBASE_EMULATORS=true` en esta prueba.

### Celular A: Planta

```text
Usuario: role=production
departmentId=production
```

### Celular B: Mantenimiento

```text
Usuario: role=maintenance
departmentId=maintenance
```

### Paso 1: comprobar registro y push directo

1. Inicie sesión en A y B.
2. En Firestore confirme `users/{uid}/devices/{deviceId}` para cada instalación.
3. Copie cada token y use **Firebase Console > Messaging > Send test message**.
4. Pruebe cada teléfono con app abierta, en background y terminada.
5. En foreground debe aparecer notificación local; al tocar en background/terminated debe abrir la app.

Si esto falla, deténgase y use el diagnóstico de [FIREBASE_SETUP.md](FIREBASE_SETUP.md#135-diagnóstico-si-no-llega). No continúe atribuyendo el fallo al ticket.

### Paso 2: crear la emergencia

En Celular A:

1. Home > Mantenimiento > Crear solicitud.
2. Título: `Falla Columbia 21`.
3. Descripción: `La Columbia 21 se detuvo y producción quedó paralizada.`
4. Activo: `Columbia 21`.
5. Producción detenida: **Sí**.
6. Riesgo de seguridad: el valor real de la prueba; no marque Sí si no corresponde.
7. Afectación: 100 %.
8. Compruebe sugerencia **Crítica**.
9. Prioridad final: **Crítica**.
10. Adjunte una foto de prueba sin información sensible.
11. Envíe.

Validar en backend:

- Ticket con código humano, `status=pending`, `priority=critical`, `productionStopped=true`.
- `createdAt` y `productionStoppedAt` de servidor.
- `assetSnapshot` de Columbia 21.
- Evento `ticketCreated` inmutable.
- Un `notification_jobs/{eventId}`, no varios.

Validar en Celular B:

- Recibe notificación urgente/alta: nueva solicitud crítica.
- Título/cuerpo identifican ticket y producción detenida.
- Tocar abre `/maintenance/tickets/<ticketId>` correcto.
- A no recibe una notificación diciendo que él mismo creó el ticket.

### Paso 3: recibir

En B:

1. Abra el ticket.
2. Pulse **Marcar recibido** y confirme.

Validar:

- Estado `acknowledged`.
- `acknowledgedAt`, `acknowledgedByUid`.
- Evento `ticketAcknowledged`.
- Celular A recibe actualización y al tocar abre el mismo ticket.
- B no se auto-notifica por su propia acción.

### Paso 4: asignar e iniciar

En B:

1. Asigne el técnico de Mantenimiento como responsable principal.
2. Confirme `status=assigned` y evento `assignmentChanged`.
3. Pase a **En proceso**.

Validar en A: estado cambia en tiempo real y llega el push que corresponda sin duplicado.

### Paso 5: conversación

En B agregue:

```text
Se inició diagnóstico eléctrico y mecánico de Columbia 21.
```

Validar:

- Comentario visible en A sin reiniciar.
- A recibe notificación; B no recibe la propia.
- Autor y timestamp correctos.

En A responda y confirme la notificación inversa en B.

En A pulse **Producción reanudada**, escriba un motivo y confirme. Valide `productionStopped=false`, `productionResumedAt`, evento `productionImpactChanged` y una notificación normal en B sin auto-notificar A.

### Paso 6: resolver

En B complete:

```text
Diagnóstico: descripción de prueba.
Trabajo realizado: descripción de prueba.
Observaciones/solución: equipo operativo para validación.
```

Opcionalmente adjunte evidencia de resolución. Pulse **Resuelto**.

Validar:

- `status=resolved`, `resolvedAt`, actor y campos de solución.
- Evento `ticketResolved`.
- A recibe “listo para revisión/cierre”.

### Paso 7: confirmar cierre

En A revise y pulse **Confirmar cierre**.

Validar:

- `status=closed`, `isOpen=false`, `closedAt`, `closedByUid`.
- Evento `ticketClosed`.
- Participantes reciben aviso salvo actor cuando corresponda.
- Ya no aparecen acciones propias de ticket abierto.

### Paso 8: solicitar revisión

Repita con otro ticket hasta `resolved`. En A pulse **Solicitar revisión nuevamente**.

Validar:

- Regresa a `inProgress`.
- `reopenCount` aumenta y `lastReopenedAt` se establece.
- Evento `ticketReopened` con motivo.
- Mantenimiento recibe notificación.

## 7. Prueba de ESCALAR URGENCIA

Con un ticket abierto creado por Planta:

1. En A pulse **ESCALAR URGENCIA**.
2. Debe aparecer confirmación explícita.
3. Escriba: `Producción continúa completamente paralizada.`
4. Confirme una sola vez.

Validar:

- Aumento de `escalationCount` y `manualEscalationCount`.
- `lastManualEscalationAt`, actor y motivo.
- Evento `manualEscalation`.
- B recibe por `gestion_interna_urgent_v1`, con sonido/vibración según ajustes Android.
- El payload abre el ticket correcto.
- Repetir inmediatamente produce error de cooldown, no otro evento/push.
- Pasado el cooldown configurable, una nueva escalada válida vuelve a auditarse.

Pulse dos veces rápidamente o simule reintento de red: el mismo `requestId` debe impedir duplicación accidental.

## 8. Prueba de escalamiento automático

FCM real requiere proyecto real, pero la lógica se prueba primero en emulador.

1. En Emulator Suite, reduzca temporalmente `criticalAcknowledgementMinutes` a un valor de prueba y conserve captura del valor anterior.
2. Cree un ticket crítico sin reconocer.
3. Ejecute la suite de Functions o el mecanismo explícito de integración que invoque la lógica de `checkOverdueTickets`; **no espere cinco minutos suponiendo que Emulator Suite reproduce Cloud Scheduler**, porque no existe un emulador de Scheduler con cadencia real.
4. Verifique evento `automaticEscalation`, `automaticEscalationLevel`, `lastAutomaticEscalationAt` y siguiente vencimiento.
5. Ejecute otra revisión antes del siguiente vencimiento: no debe duplicar.
6. Marque el ticket `acknowledged`: `nextAutomaticEscalationAt` debe dejar de generar alertas.
7. Restaure la configuración.

En proyecto real, haga una sola prueba controlada fuera de operación, con destinatarios avisados. Allí sí debe comprobar que Cloud Scheduler dispara aproximadamente cada cinco minutos y que FCM llega por canal urgente. No deje SLA reducido en producción. Referencias: [tipos soportados por Functions Emulator](https://firebase.google.com/docs/functions/local-emulator) y [Functions programadas](https://firebase.google.com/docs/functions/schedule-functions).

## 9. Pruebas de estados Android

Para un mensaje real con `ticketId`/`route`:

| Estado app | Resultado esperado |
|---|---|
| Foreground | `onMessage` + notificación local; tocar abre ticket. |
| Background | Android muestra; `onMessageOpenedApp` abre ticket. |
| Terminada normalmente | Android muestra; `getInitialMessage()` abre después del bootstrap. |
| Pantalla bloqueada | Alerta visible según privacidad configurada por usuario. |
| Permiso denegado | Sin banner; la app muestra estado/guía para habilitar. |
| Sin Internet | No se promete push; al reconectar Firestore muestra verdad actual. |
| Force stop desde Ajustes | No llega hasta abrir la app nuevamente; limitación Android. |

Pruebe canal normal y urgente por separado. Cambiar volumen/sonido desde la app no puede sobreescribir preferencias de un canal ya creado por Android.

## 10. Múltiples dispositivos y limpieza

1. Inicie la misma cuenta en dos teléfonos.
2. Confirme dos device docs con IDs distintos.
3. Genere un evento dirigido a ese usuario: ambos deben recibir una vez.
4. Cierre sesión en uno: solo su documento debe desaparecer.
5. El otro teléfono continúa recibiendo.
6. Desinstale/reinstale: aparece una instalación nueva; el backend debe limpiar el registro viejo cuando FCM lo rechace o por política de antigüedad.
7. Introduzca únicamente en entorno de prueba un token inválido; tras enviar, debe eliminarse/deshabilitarse sin fallar los válidos.

La transición oficial de tokens a FIDs está documentada en [FIREBASE_SETUP.md](FIREBASE_SETUP.md#nota-vigente-sobre-tokens-y-fids). No confunda el UUID local `installationId` de esta app con el FID oficial ni cambie manualmente el esquema.

## 11. Offline, reconexión y errores

1. Abra una lista/ticket con Internet para poblar caché.
2. Active modo avión.
3. La pantalla debe mostrar información cacheada y el banner **Datos locales/cache**, no quedar en blanco. El banner representa `QuerySnapshot.metadata.isFromCache`; no se debe interpretar como detector perfecto de Wi‑Fi/datos.
4. Intente comentario/transición callable: debe mostrar fallo reintentable; no afirmar éxito ni inventar evento local.
5. Restaure Internet y reintente una vez.
6. Verifique una sola mutación/evento por `requestId` repetido.
7. Corte red durante upload: debe presentar error e intentar limpiar el objeto si llegó a subirse antes del fallo de metadata. La limpieza es de mejor esfuerzo; si la red también impide borrar, registre el objeto huérfano para limpieza administrativa posterior.

También pruebe:

- permiso de cámara denegado;
- archivo inválido/mayor de 5 MiB;
- Firebase no configurado;
- usuario desactivado durante la sesión;
- Function no disponible;
- índice aún en construcción;
- documento borrado mientras está abierto.

El usuario ve mensajes accionables; stack traces solo aparecen en logs de desarrollo.

## 12. Auditoría y datos analíticos

Para una ejecución completa confirme que cada hito tiene timestamp y actor:

```text
createdAt
acknowledgedAt
assignedAt
workStartedAt
resolvedAt
closedAt
updatedAt
```

Los tiempos se muestran en `America/Bogota`, pero el Timestamp Firestore debe ser absoluto. Compare eventos con cambios del ticket; no deben faltar ni existir eventos editables desde cliente. Pruebe `productionStoppedAt`/`productionResumedAt` únicamente mediante `updateProductionImpact`; cada parada/reanudación debe producir `productionImpactChanged`, nunca una escritura directa.

## 13. Control de costo durante pruebas

- Use emuladores para iteraciones repetitivas.
- No haga listeners a colecciones completas.
- Revise Functions logs por bucles antes de dejar un test corriendo.
- No suba la misma foto muchas veces al bucket real.
- En Firebase Console revise **Usage and billing** después de la prueba real.
- Confirme un solo job programado y que `minInstances` conserva su valor predeterminado cero.
- No pruebe producción con miles de documentos sintéticos.

## 14. Registro de evidencia de aceptación

Para cada build candidata registre sin secretos:

```text
Fecha/hora (America/Bogota):
Commit o versión:
Project ID de prueba (no credenciales):
Modelo/API Android Celular A:
Modelo/API Android Celular B:
flutter analyze:
flutter test:
Functions build/lint/test:
Rules/emuladores:
FCM foreground A/B:
FCM background A/B:
FCM terminated A/B:
Flujo ticket completo:
Escalamiento manual:
Escalamiento automático:
Adjuntos:
Problemas/limitaciones:
Responsable:
```

No incluya tokens FCM, contraseñas, JSON de Service Account ni fotos operativas sensibles en el informe.

## Criterio de salida

El MVP puede entregarse a usuarios piloto solo si:

- Todas las verificaciones automatizadas pasan.
- Rules rechazan los casos negativos críticos.
- El flujo de dos celulares se completa de creación a cierre.
- FCM funciona en foreground, background y terminated en al menos dos modelos reales.
- El actor no se auto-notifica y no hay duplicados visibles.
- Escalamiento manual respeta confirmación/cooldown/auditoría.
- Escalamiento automático no continúa tras reconocer.
- Parada/reanudación registra timestamps, motivo, auditoría y notificación sin escrituras directas.
- Fotografías respetan ruta/tipo/5 MiB y autorización.
- Presupuesto/alertas están configurados.
- Las limitaciones reales se comunican a los usuarios piloto.

# Configuración de Firebase desde cero

Esta guía conecta la aplicación Android **Gestión Interna** con Firebase, prepara el entorno local, despliega el backend y termina con una prueba real entre dos teléfonos. Está escrita para una persona que nunca ha usado Firebase CLI.

> Procedimiento y enlaces verificados el **14 de agosto de 2026**. La consola puede cambiar ligeramente de lugar o traducir los nombres; se incluyen el nombre inglés y el español cuando ayuda.

## 1. Lo que se va a configurar

La aplicación usa:

- Firebase Authentication con correo y contraseña.
- Cloud Firestore Standard para usuarios, tickets, conversación y auditoría.
- Cloud Functions for Firebase, Node.js 22 y TypeScript, para todas las operaciones privilegiadas.
- Firebase Cloud Messaging (FCM) para push Android.
- Cloud Storage for Firebase para fotografías.
- Procedimiento futuro de App Check con Play Integrity como endurecimiento recomendado; no está activo en el MVP entregado.
- Firebase Emulator Suite para desarrollar sin tocar producción.

El identificador Android de esta app es exactamente:

```text
com.samuelpararia.gestioninterna
```

Es sensible a mayúsculas/minúsculas. Una vez registrada la aplicación Android en Firebase, el package name de ese registro no se puede cambiar; un cambio futuro requiere registrar otra app Android. Consulte [configuración oficial de Firebase Android](https://firebase.google.com/docs/android/setup).

### Dos entornos que no se deben confundir

| Entorno | Identificador | Datos | Push FCM |
|---|---|---|---|
| Local | `demo-gestion-interna` | Se borran al detener el emulador, salvo exportación | No se emula; se usan logs/fakes |
| Real | El `PROJECT_ID` creado por Samuel | Persistentes y potencialmente facturables | Sí, en teléfonos físicos |

Nunca use el proyecto real para ejecutar seeds o pruebas destructivas por comodidad. Los scripts administrativos exigen confirmación doble para producción.

## 2. Requisitos en Windows

Abra **Windows PowerShell** en la raíz del repositorio. En esta guía se asume esta carpeta:

```powershell
Set-Location 'C:\Users\itopa\Desktop\Proyectos Coding\KeepConnect'
```

Si el repositorio está en otra ubicación, sustituya esa ruta absoluta en todos los ejemplos; no cree una segunda copia solo para conservarla.

### 2.1 Flutter, Dart y Android

El proyecto fue preparado para:

- Flutter 3.44.7.
- Dart 3.12.2.
- Android 7.0/API 24 o posterior. El proyecto usa `flutter.minSdkVersion`, que en Flutter 3.44.7 equivale a API 24.
- JDK 17 para la compilación Android y JDK 21 para Firebase CLI 15/Emulator Suite.

Instale Flutter siguiendo la [guía oficial para Windows](https://docs.flutter.dev/get-started/install/windows/mobile). Instale Android Studio, Android SDK, las command-line tools y al menos una imagen de emulador con Google Play. Después acepte licencias:

```powershell
flutter doctor --android-licenses
```

Compruebe el entorno:

```powershell
flutter --version
dart --version
java -version
flutter doctor -v
```

`flutter doctor -v` debe reconocer Android toolchain y, si se usará un emulador, Android Studio. Corrija los elementos marcados con una cruz antes de continuar. Aunque la guía FlutterFire vigente admite Android 6/API 23, esta versión concreta de Flutter eleva el mínimo efectivo del proyecto a API 24. Para probar FCM use una imagen compatible con Google Play: [configuración FlutterFire](https://firebase.google.com/docs/flutter/setup).

### 2.2 Node.js 22, npm y Corepack/pnpm

Instale Node.js 22 desde [nodejs.org](https://nodejs.org/) o con el instalador corporativo aprobado. Cierre y vuelva a abrir PowerShell para actualizar `PATH`, y verifique:

```powershell
node --version
npm --version
corepack --version
```

`node --version` debe comenzar por `v22.`. Firebase soporta Node 22 y 20; Node 18 ya está deprecado y 14/16 fueron retirados. Fuente: [runtimes de Cloud Functions](https://firebase.google.com/docs/functions/manage-functions#set_node.js_version).

Este repositorio entrega `pnpm-lock.yaml` en `functions/` y `scripts/`, por lo que pnpm es el gestor de instalación reproducible. Active el lanzador incluido con Node y compruébelo:

```powershell
corepack enable
pnpm --version
```

Si `corepack enable` requiere una PowerShell elevada, abra una terminal **como administrador solo para ese comando**, ciérrela y continúe en una terminal normal. No sustituya los lockfiles por `package-lock.json`. npm sí se conserva para ejecutar los scripts ya definidos en `package.json`. Referencia: [Corepack en Node.js 22](https://nodejs.org/docs/latest-v22.x/api/corepack.html).

### 2.3 Firebase CLI

Instale la CLI oficial con npm:

```powershell
npm install --global firebase-tools
firebase --version
```

Si PowerShell dice que `firebase` no existe, cierre y abra la terminal. Después ejecute:

```powershell
Get-Command firebase
```

La instalación y comandos vigentes están en [Firebase CLI](https://firebase.google.com/docs/cli).

### PowerShell bloquea `npm.ps1` o `firebase.ps1`

Si aparece `PSSecurityException` porque la ejecución de scripts está
deshabilitada, no use `Bypass` ni `Unrestricted`. Ejecute los lanzadores `.cmd`:

```powershell
npm.cmd --version
pnpm.cmd --version
firebase.cmd --version
firebase.cmd login
```

En el resto de esta guía puede sustituir `npm`, `pnpm` y `firebase` por
`npm.cmd`, `pnpm.cmd` y `firebase.cmd` respectivamente.

### 2.4 FlutterFire CLI

Instale la herramienta que genera la configuración Dart/Android:

```powershell
dart pub global activate flutterfire_cli
flutterfire --version
```

Si `flutterfire` no se reconoce, agregue la carpeta de ejecutables globales de Pub al `PATH` del usuario y abra una terminal nueva:

```text
%LOCALAPPDATA%\Pub\Cache\bin
```

Puede confirmar su ubicación con:

```powershell
Get-Command flutterfire
```

## 3. Crear el proyecto Firebase real

1. Abra [Firebase Console](https://console.firebase.google.com/) con la cuenta que será propietaria.
2. Pulse **Create a project / Crear un proyecto**.
3. Use un nombre visible reconocible, por ejemplo `Gestión Interna`.
4. Firebase propondrá un **Project ID** globalmente único. Anótelo. En los comandos se representa como `<PROJECT_ID>`; no escriba literalmente los signos `< >`.
5. Google Analytics no es necesario para este MVP. Puede dejarlo desactivado para minimizar configuración; FCM directo no depende de Analytics.
6. Finalice y espere a que aparezca la página principal del proyecto.

En PowerShell, guarde temporalmente el ID real para evitar errores de escritura:

```powershell
$FirebaseProjectId = 'REEMPLAZAR-POR-EL-PROJECT-ID-REAL'
```

No use `demo-gestion-interna` como ID de producción. El prefijo `demo-` está reservado en esta guía para Emulator Suite.

### 3.1 Activar Blaze de forma consciente

Este paso es obligatorio para desplegar Functions y usar Storage real:

1. En Firebase Console, abra **Upgrade / Actualizar** o **Usage and billing / Uso y facturación**.
2. Seleccione **Blaze – Pay as you go / Pago por uso**.
3. Enlace o cree una cuenta de Cloud Billing y un método de pago.
4. Cree inmediatamente el presupuesto descrito en [FIREBASE_COSTS.md](FIREBASE_COSTS.md#presupuesto-y-alertas-configuración-obligatoria).

Desde el 3 de febrero de 2026, Storage no permite acceso en Spark y devuelve 402/403. Spark tampoco permite desplegar Cloud Functions. Blaze conserva cuotas sin costo; consulte el detalle y riesgos en [FIREBASE_COSTS.md](FIREBASE_COSTS.md). Fuente primaria: [FAQ oficial de Storage](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024).

## 4. Iniciar sesión y asociar el repositorio

Ejecute:

```powershell
firebase login
```

Qué debe ocurrir:

1. La CLI abre el navegador.
2. Seleccione la misma cuenta de Google propietaria del proyecto.
3. Autorice Firebase CLI.
4. El navegador muestra que el inicio de sesión terminó; vuelva a PowerShell.
5. La terminal debe mostrar un mensaje de acceso correcto.

Compruebe que el proyecto aparece:

```powershell
firebase projects:list
```

Asocie esta carpeta con el proyecto real:

```powershell
firebase use --add
firebase use production
```

En el primer comando seleccione exactamente el proyecto cuyo ID guardó en `$FirebaseProjectId` y, cuando pregunte por un alias, use `production`. El segundo comando deja ese alias activo. La CLI crea o actualiza `.firebaserc`. El repositorio aporta `.firebaserc.example` como referencia, pero nunca se debe dejar un ID inventado en el código. Esta es la sintaxis interactiva documentada por la [referencia oficial de Firebase CLI](https://firebase.google.com/docs/cli#manage_project_aliases).

Compruebe el proyecto activo:

```powershell
firebase use
```

Para cada despliegue es todavía más seguro indicar el proyecto de forma explícita con `--project $FirebaseProjectId`.

### No vuelva a inicializar encima del proyecto preparado

Este repositorio ya incluye `firebase.json`, `firestore.rules`, `firestore.indexes.json`, `storage.rules`, `functions/` y `scripts/`. No ejecute `firebase init` aceptando sobrescrituras. `firebase init` y `firebase init emulators` solo serían necesarios en una copia vacía; aquí podrían reemplazar reglas o configuración probadas.

## 5. Registrar exclusivamente Android con FlutterFire

Primero confirme que `android/app/build.gradle.kts` contiene:

```kotlin
applicationId = "com.samuelpararia.gestioninterna"
```

Desde la raíz ejecute:

```powershell
flutterfire configure --project=$FirebaseProjectId --platforms=android --android-package-name=com.samuelpararia.gestioninterna
```

Durante el asistente:

1. Confirme el proyecto real correcto.
2. Seleccione solo **Android**. No seleccione iOS, Web, Windows ni macOS.
3. Confirme el package `com.samuelpararia.gestioninterna`.
4. Permita que actualice la configuración FlutterFire.

El flujo genera `lib/firebase_options.dart` y registra o enlaza la app Android. Según la versión, también descarga/verifica `android/app/google-services.json` y ajusta plugins Gradle. Vuelva a ejecutar `flutterfire configure` si agrega un producto Firebase que requiera configuración nativa.

Luego instale dependencias y compile una vez:

```powershell
flutter pub get
flutter analyze
flutter build apk --debug
```

### Qué configuraciones pueden ir a Git

Sí pueden versionarse:

- `lib/firebase_options.dart`.
- `android/app/google-services.json`.
- `.firebaserc` si el equipo desea compartir el alias/Project ID.
- `firebase.json`, Rules e índices.

Esos archivos contienen identificadores y API keys de cliente que Firebase trata como información pública, no credenciales administrativas. La seguridad real depende de Rules, IAM y App Check. Aun así, restrinja las API keys a las APIs Firebase necesarias desde Google Cloud cuando corresponda. Fuente: [API keys de Firebase](https://firebase.google.com/docs/projects/api-keys).

Nunca suba:

- JSON de Service Account.
- Claves privadas.
- FCM Server Keys heredadas.
- archivos `.env` con secretos.
- contraseñas de usuarios demo.
- tokens de depuración de App Check.

En Cloud Functions desplegadas, `initializeApp()` usa credenciales predeterminadas del entorno; no hace falta un JSON privado. Fuente: [Firebase Admin SDK setup](https://firebase.google.com/docs/admin/setup).

## 6. Habilitar Authentication

1. En Firebase Console, abra **Security > Authentication**. En algunas variantes de la consola aparece como **Build > Authentication**.
2. Pulse **Get started / Comenzar**.
3. Abra la pestaña **Sign-in method / Método de acceso**.
4. Pulse **Add new provider / Agregar proveedor**.
5. Elija **Email/Password / Correo electrónico/Contraseña**.
6. Active el primer interruptor de Email/Password. No es necesario habilitar “Email link”.
7. Pulse **Save / Guardar**.

Fuente: [Email/Password en Flutter](https://firebase.google.com/docs/auth/flutter/password-auth).

### Crear dos cuentas de prueba

En **Authentication > Users / Usuarios**:

1. Pulse **Add user / Agregar usuario**.
2. Cree un correo controlado para Planta con una contraseña temporal fuerte.
3. Repita para Mantenimiento.
4. Copie el **UID** de cada cuenta. El UID, no el correo, enlaza Auth con Firestore.
5. No escriba las contraseñas en README, código, commits ni capturas públicas.

Crear una cuenta en Authentication no crea automáticamente el perfil de autorización. Después del seed, use el script `manage-user` o cree cuidadosamente `users/{uid}` con:

```text
uid:            el UID exacto de Authentication
name:           nombre visible
email:          correo normalizado
role:           production | maintenance | admin
departmentId:   production | maintenance
active:         true
createdAt:      timestamp
updatedAt:      timestamp
```

El rol se escribe únicamente desde entorno administrativo. Una persona normal no puede ascenderse a `admin`; las Rules bloquean ese cambio aunque se oculte el botón en Flutter.

### Recuperación de contraseña

La pantalla de login usa `sendPasswordResetEmail`. El correo debe existir y el usuario debe revisar spam. Para personalizar remitente/plantilla, vaya a **Authentication > Templates / Plantillas**. Respete los límites de envío descritos en [límites de Authentication](https://firebase.google.com/docs/auth/limits).

## 7. Crear Cloud Firestore

1. Abra **Build > Firestore Database** o **Databases & Storage > Firestore**.
2. Pulse **Create database / Crear base de datos**.
3. Seleccione **Standard edition** y modo nativo.
4. Elija **Production mode / Modo producción**. Las reglas del repositorio se desplegarán inmediatamente; nunca use `allow read, write: if true`.
5. Seleccione la región **`us-central1`**.
6. Confirme. La ubicación de una base no puede cambiarse después.

Se usa `us-central1` para co-localizar Firestore, Functions y Storage, reducir latencia entre backend y datos y mantener el bucket nuevo en una región Always Free. No es la zona horaria de los usuarios: las Functions presentan/calculan horarios con `America/Bogota`, mientras Firestore guarda timestamps absolutos.

Fuentes: [ubicaciones de Firestore](https://firebase.google.com/docs/firestore/locations) y [ubicaciones de Functions](https://firebase.google.com/docs/functions/locations).

## 8. Crear Cloud Storage

1. Confirme que el proyecto ya está en Blaze.
2. Abra **Build > Storage** o **Databases & Storage > Storage**.
3. Pulse **Get started / Comenzar**.
4. Elija **`us-central1`**.
5. Finalice. Los proyectos nuevos usan `PROJECT_ID.firebasestorage.app`.
6. No deje reglas de prueba; despliegue `storage.rules` desde este repositorio.

La ruta real de cada archivo es:

```text
tickets/{ticketId}/{attachmentId}/{fileName}
```

Los metadatos se guardan en:

```text
tickets/{ticketId}/attachments/{attachmentId}
```

Storage Rules exigen usuario autenticado/autorizado, una ruta válida, contenido de imagen y tamaño permitido. El cliente no almacena imágenes Base64 en Firestore ni puede sobrescribir rutas arbitrarias. Si `registerAttachment` falla, solo puede borrar su propia subida huérfana mientras aún no exista `tickets/{ticketId}/attachments/{attachmentId}`; una evidencia ya registrada queda inmutable.

## 9. Preparar Functions y scripts locales

Instale exactamente las dependencias bloqueadas por los dos `pnpm-lock.yaml` entregados:

```powershell
corepack enable
pnpm --dir functions install --frozen-lockfile
pnpm --dir scripts install --frozen-lockfile
```

`--frozen-lockfile` obliga a que cada `package.json` coincida con su lockfile; si no coincide, deténgase y corrija/versione el lockfile en vez de instalar versiones improvisadas. Los comandos siguientes usan npm únicamente como ejecutor de scripts y aprovechan las dependencias que pnpm acaba de instalar.

Compile y valide Functions:

```powershell
npm --prefix functions run build
npm --prefix functions run lint
npm --prefix functions test
npm --prefix scripts run build
```

Functions exporta estos nombres exactos:

| Tipo | Nombre | Responsabilidad principal |
|---|---|---|
| Callable | `createTicket` | Validar entrada, generar código sin colisiones y crear ticket/auditoría. |
| Callable | `transitionTicket` | Aplicar máquina de estados y timestamps. |
| Callable | `assignTicket` | Asignar responsable/participantes con autorización. |
| Callable | `addComment` | Crear comentario con actor de servidor. |
| Callable | `updatePriority` | Cambiar prioridad con trazabilidad. |
| Callable | `updateProductionImpact` | Registrar parada/reanudación, motivo y timestamps de servidor. |
| Callable | `registerAttachment` | Validar y registrar metadatos de una carga autorizada. |
| Callable | `escalateTicket` | Validar rol/estado/cooldown, auditar y alertar. |
| Callable | `registerDevice` | Registrar/renovar token y asegurar un solo propietario por instalación/token. |
| Callable | `unregisterDevice` | Retirar de forma autenticada esta instalación al cerrar sesión. |
| Firestore | `onTicketCreated` | Crear trabajo idempotente y notificar a mantenimiento. |
| Firestore | `onTicketUpdated` | Detectar cambios relevantes sin notificar al actor. |
| Firestore | `onCommentCreated` | Notificar participantes excepto autor. |
| Scheduler | `checkOverdueTickets` | Cada 5 minutos, escalar candidatos vencidos. |

El Scheduler usa `America/Bogota`; las Functions y Firestore están en `us-central1`.

## 10. Ejecutar Firebase Emulator Suite

La instalación validada usa Node 22 y Java JDK 21 para Firebase CLI 15/Emulator
Suite. Flutter/Gradle permanece fijado a JDK 17 mediante `flutter config
--jdk-dir`. Fuente: [instalación de Emulator Suite](https://firebase.google.com/docs/emulator-suite/install_and_configure).

Abra una primera PowerShell en la raíz y ejecute:

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '30'
firebase.cmd emulators:start --project demo-gestion-interna --only "auth,firestore,functions,storage"
```

Puertos configurados:

| Servicio | Puerto |
|---|---:|
| Emulator UI | 4000 |
| Functions | 5001 |
| Firestore | 8080 |
| Authentication | 9099 |
| Storage | 9199 |

Abra [http://127.0.0.1:4000](http://127.0.0.1:4000). Debe ver los cuatro emuladores activos. Mantenga esa terminal abierta.

`firebase.json` enlaza Auth/Functions/Firestore/Storage a `0.0.0.0` para permitir Android Emulator y teléfonos de la LAN. Emulator UI permanece en `127.0.0.1` y solo se abre en el PC. Esta configuración exige usar una red privada y Firewall restringido; nunca reenvíe esos puertos en el router.

### Cargar datos demo

En una segunda PowerShell, desde la raíz:

```powershell
npm --prefix scripts run seed
```

El seed local crea, entre otros, Planta de Producción, Mantenimiento, el módulo, categorías, `Columbia 21`, formulario dinámico y `settings/maintenance`. Puede repetirse de forma idempotente. Revise los documentos en Emulator UI.

Para previsualizar el seed sin escribir:

```powershell
npm --prefix scripts run seed -- --dry-run
```

### Ejecutar en Android Emulator

Liste y arranque un dispositivo:

```powershell
flutter devices
flutter emulators
flutter emulators --launch ID_DEL_EMULADOR
```

Después:

```powershell
flutter run --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
```

`10.0.2.2` es la dirección especial con la que Android Emulator llega al `localhost` del PC. **No use `localhost` dentro del emulador Android**: apuntaría al propio teléfono virtual.

Cloud Functions Emulator sirve HTTP sin cifrar. Android 9+ puede bloquearlo, por eso el repositorio habilita `android:usesCleartextTraffic="true"` **únicamente** en `android/app/src/debug/AndroidManifest.xml`. No mueva esa opción al manifest `main`, no la añada a release y no la use para justificar endpoints HTTP en producción. Fuente: [conectar Android al Functions Emulator](https://firebase.google.com/docs/functions/local-emulator#instrument_your_app_to_talk_to_the_emulators).

### Ejecutar contra emuladores desde un teléfono físico

1. Conecte PC y celular a la misma red privada.
2. En PowerShell, ejecute `ipconfig` y localice la dirección IPv4 del adaptador activo, por ejemplo `192.168.1.25`.
3. Confirme que `firebase.json` mantiene `host: "0.0.0.0"` en Auth, Functions, Firestore y Storage; UI debe permanecer `127.0.0.1`.
4. Autorice Java/Node/Firebase Emulator en Windows Defender Firewall **solo para redes privadas**.
5. Active depuración USB y compruebe `flutter devices`.
6. Sustituya la IP de ejemplo por la IP real:

```powershell
flutter run --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.25
```

No exponga los puertos 5001/8080/9099/9199 a Internet. La UI 4000 es local y no debe abrir desde el teléfono. Si el celular no conecta, pruebe desde su navegador `http://IP_DEL_PC:8080` (un 404/JSON sigue demostrando conexión TCP) y revise red, VPN y firewall.

### Guardar y recuperar datos locales opcionalmente

Para conservar un estado reproducible:

```powershell
firebase emulators:export .\local-emulator-data --project demo-gestion-interna
firebase emulators:start --project demo-gestion-interna --import .\local-emulator-data --export-on-exit .\local-emulator-data
```

Use una carpeta ignorada por Git si contiene datos personales de prueba.

Al detenerse, Firestore Emulator pierde su memoria salvo que se exporte, pero la caché offline del SDK Android no se borra automáticamente. Si reinicia los emuladores desde cero y la app todavía muestra documentos antiguos, cierre sesión, borre los datos de Gestión Interna en Android o reinstale la build antes de concluir que el seed falló. Fuente: [conectar una app al emulador de Firestore](https://firebase.google.com/docs/emulator-suite/connect_firestore#android_apple_platforms_and_web_sdks).

### Importante: FCM no se emula

Auth, Firestore, Functions y Storage sí tienen emuladores. FCM no aparece entre los servicios emulados. Una Function local que intente usar Admin SDK para FCM puede intentar llamar a la API real si recibe credenciales reales. Para desarrollo local:

- Use siempre `demo-gestion-interna`.
- No configure credenciales de producción en la terminal del emulador.
- Verifique la intención de notificación mediante logs/pruebas del gateway.
- Realice la prueba push únicamente con el proyecto real y teléfonos físicos.

Fuente: el emulador de Functions indica que APIs no emuladas como FCM requieren credenciales reales: [Run functions locally](https://firebase.google.com/docs/functions/local-emulator).

## 11. Desplegar Rules, índices y Functions

Antes de desplegar, confirme dos veces el destino:

```powershell
firebase use
firebase projects:list
$FirebaseProjectId
```

### 11.1 Rules e índices

Ejecute cada componente por separado para que un error sea fácil de identificar:

```powershell
firebase deploy --only firestore:rules --project $FirebaseProjectId
firebase deploy --only firestore:indexes --project $FirebaseProjectId
firebase deploy --only storage --project $FirebaseProjectId
```

Estas Storage Rules consultan perfiles, tickets y metadatos en Firestore. En el primer despliegue, Firebase puede pedir habilitar el permiso que permite a Storage Rules consultar Firestore; acepte únicamente después de volver a comprobar `$FirebaseProjectId`. Cada evaluación con `firestore.get()` o `firestore.exists()` cuenta como lectura facturable de Firestore. Fuente: [mejorar Storage Rules con Cloud Firestore](https://firebase.google.com/docs/storage/security/rules-conditions#enhance_with_cloud_firestore).

También puede desplegar Firestore Rules e índices juntos:

```powershell
firebase deploy --only firestore --project $FirebaseProjectId
```

Compruebe en Firebase Console:

- **Firestore Database > Rules**: debe mostrar las reglas versionadas, no una regla abierta de prueba.
- **Firestore Database > Indexes**: los índices pueden mostrar `Building` durante varios minutos. Espere a `Enabled` antes de probar todas las listas.
- **Storage > Rules**: debe coincidir con `storage.rules`.

Las instrucciones oficiales están en [administrar y desplegar Security Rules](https://firebase.google.com/docs/rules/manage-deploy) e [índices de Firestore](https://firebase.google.com/docs/firestore/query-data/indexing).

### 11.2 Functions

Compile y ejecute pruebas antes de cada despliegue:

```powershell
npm --prefix functions run build
npm --prefix functions run lint
npm --prefix functions test
firebase deploy --only functions --project $FirebaseProjectId
```

En el primer despliegue Google puede pedir habilitar APIs como Cloud Functions, Cloud Build, Artifact Registry, Eventarc, Pub/Sub y Cloud Scheduler. Acepte únicamente dentro del proyecto que acaba de verificar. Debe estar en Blaze.

No cierre la terminal hasta ver el resumen de funciones desplegadas. Después, en Firebase Console abra **Build > Functions** o en Google Cloud Console abra **Cloud Run functions**. Verifique región `us-central1`.

Para ver logs recientes:

```powershell
firebase functions:log --project $FirebaseProjectId
firebase functions:log --only createTicket --project $FirebaseProjectId
firebase functions:log --only checkOverdueTickets --project $FirebaseProjectId
```

También puede usar **Google Cloud > Logging > Logs Explorer**. Filtre por severidad `ERROR` y por nombre de Function.

### 11.3 Por qué los triggers deben ser idempotentes

Firestore no garantiza orden de eventos y entrega cada evento **al menos una vez**; un mismo evento puede invocar una Function varias veces. Por eso `notification_jobs/{eventId}` evita notificaciones duplicadas, mientras `_command_receipts/{id}` evita crear dos tickets cuando el cliente reintenta `createTicket` con el mismo `requestId`. Las demás callables también derivan eventos deterministas de `requestId`. Ambas colecciones internas son backend-only. Nunca elimine esa protección solo porque una prueba simple produjo una única invocación. Fuente: [eventos de Firestore en Cloud Functions](https://firebase.google.com/docs/functions/firestore-events#limitations).

## 12. Datos iniciales y administración de usuarios

### 12.1 Seed local recomendado

Con Emulator Suite activo:

```powershell
npm --prefix scripts run seed
```

Este es el modo predeterminado y seguro.

Puede comprobar primero qué haría sin escribir:

```powershell
npm --prefix scripts run seed -- --dry-run
```

### 12.2 Seed del proyecto real

El seed real requiere simultáneamente los tres parámetros siguientes; esto evita escribir en producción por accidente:

```powershell
npm --prefix scripts run seed -- --production --project $FirebaseProjectId --confirm-project $FirebaseProjectId
```

Antes de confirmar, lea en pantalla el ID y asegúrese de que no sea otro proyecto de la empresa. El script carga catálogos/configuración, no debe crear contraseñas conocidas ni sobrescribir tickets.

### 12.3 Crear o actualizar perfiles con `manage-user`

El script puede crear/actualizar conjuntamente la cuenta Auth y su perfil. Para no escribir la contraseña en argumentos o historial, recibe el valor desde una variable de entorno cuyo **nombre** se indica con `--password-env`.

En PowerShell, capture una contraseña sin mostrarla y expóngala temporalmente al proceso:

```powershell
$SecureUserPassword = Read-Host 'Contraseña temporal del usuario' -AsSecureString
$PasswordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureUserPassword)
try {
  $env:GESTION_NEW_USER_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($PasswordPointer)
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($PasswordPointer)
}
```

Crear/actualizar Planta en el emulador:

```powershell
npm --prefix scripts run manage-user -- --action upsert --email planta@example.test --name "Operador Planta" --role production --department production --password-env GESTION_NEW_USER_PASSWORD
```

Crear/actualizar Mantenimiento:

```powershell
npm --prefix scripts run manage-user -- --action upsert --email mantenimiento@example.test --name "Técnico Mantenimiento" --role maintenance --department maintenance --password-env GESTION_NEW_USER_PASSWORD
```

`--password-env` solo se requiere al crear. Para actualizar nombre/rol/departamento de una cuenta existente puede omitirlo. El script no imprime la contraseña. Borre la variable al terminar:

```powershell
Remove-Item Env:\GESTION_NEW_USER_PASSWORD
```

Activar o desactivar por correo:

```powershell
npm --prefix scripts run manage-user -- --action deactivate --email planta@example.test
npm --prefix scripts run manage-user -- --action activate --email planta@example.test
```

También acepta `--uid` en vez de `--email` y `--dry-run` para previsualizar.

Contra el proyecto real agregue obligatoriamente las tres defensas, además de configurar ADC:

```powershell
npm --prefix scripts run manage-user -- --action upsert --email usuario@empresa.example --name "Nombre Apellido" --role production --department production --password-env GESTION_NEW_USER_PASSWORD --production --project $FirebaseProjectId --confirm-project $FirebaseProjectId
```

El script aborta si proyecto/confirmación no coinciden o si detecta variables Emulator junto a `--production`.

Procedimiento recomendado:

1. Ensayar con `--dry-run` y/o Emulator Suite.
2. Verificar correo, nombre, rol y departamento.
3. Para producción, confirmar Project ID y credenciales ADC.
4. Abrir `users/{uid}` en Firestore y verificar `role`, `departmentId` y `active`.

Los roles exactos son:

```text
admin
production
maintenance
```

La acción `deactivate` deshabilita Auth y marca `active=false`; `activate` revierte ambas partes. Desactivar solo en Flutter no sería una medida de seguridad.

### 12.4 Credenciales para scripts de producción

La sesión `firebase login` sirve para CLI/despliegue, pero un script Admin local puede requerir Application Default Credentials (ADC) o un Service Account autorizado.

Opción preferida si la organización tiene Google Cloud CLI:

```powershell
gcloud auth application-default login
```

Si se autoriza excepcionalmente una clave JSON, guárdela fuera del repositorio, por ejemplo en una carpeta privada, y expóngala solo en la terminal actual:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta-segura\service-account.json'
```

Al terminar:

```powershell
Remove-Item Env:\GOOGLE_APPLICATION_CREDENTIALS
```

No copie esa clave a `functions/`, `scripts/`, `android/` ni `lib/`; no la envíe por chat/correo y nunca la empaquete en el APK. Rote/elimine la clave desde IAM si se expone.

## 13. Probar Firebase Cloud Messaging real

FCM es gratuito, pero no tiene emulador. Haga esta prueba después de desplegar Functions y Rules.

### 13.1 Preparar un teléfono

1. Conecte un teléfono Android físico con Google Play Services y acceso a Internet.
2. Active opciones de desarrollador y depuración USB.
3. Confirme que aparece:

```powershell
flutter devices
```

4. Ejecute contra Firebase real, **sin** `USE_FIREBASE_EMULATORS=true`:

```powershell
flutter run --release
```

Para depuración inicial puede usar `flutter run`, pero pruebe también una build release antes de aceptar FCM.

5. Inicie sesión.
6. En Android 13/API 33 o superior, cuando la app lo solicite, pulse **Permitir notificaciones**. Si se deniega, la app funciona pero no puede mostrar alertas; se habilita luego en **Ajustes del teléfono > Apps > Gestión Interna > Notificaciones**.

Android exige permiso runtime `POST_NOTIFICATIONS` desde API 33. Fuente: [permiso de notificaciones Android](https://developer.android.com/develop/ui/views/notifications/notification-permission).

### 13.2 Comprobar el registro del dispositivo

Abra Firestore Console y navegue a:

```text
users/{uid}/devices/{deviceId}
```

Debe existir un documento para **cada instalación**, con datos equivalentes a:

```text
installationId
uid
token
platform = android
applicationId = com.samuelpararia.gestioninterna
notificationsEnabled
permissionStatus
installationCreatedAt
updatedAt
lastSeenAt
```

Un usuario con dos teléfonos debe tener dos documentos. Al renovarse el token, `onTokenRefresh` actualiza el registro. Al cerrar sesión, esta app **intenta** eliminar el documento de esa instalación mediante `unregisterDevice` antes de cerrar Auth; el intento tiene un timeout corto y no bloquea indefinidamente el logout si no hay red. Por eso la operación debe probarse con conectividad: ante un fallo podría quedar un registro temporalmente activo, hasta que otra cuenta reclame de forma exclusiva la misma instalación/token o FCM lo rechace. Desactivar un usuario administrativamente mantiene el documento pero fija `notificationsEnabled=false`. El backend elimina registros rechazados como `UNREGISTERED` o `messaging/registration-token-not-registered`.

El cliente no escribe el documento directamente: invoca `registerDevice`, que valida app/plataforma/permiso y usa los índices internos `device_installations/{installationId}` y `device_tokens/{tokenHash}` para que una instalación o token no quede asignado simultáneamente a dos cuentas. Cuando la llamada llega autenticada, `unregisterDevice` limpia el device doc y sus dos referencias índice al cerrar sesión. Ambas colecciones índice son backend-only y nunca almacenan el token en texto claro fuera del device doc autorizado.

### Nota vigente sobre tokens y FIDs

El 13 de agosto de 2026 Firebase publicó que FCM está migrando de registration tokens a **Firebase Installation IDs (FIDs)**. Ambos esquemas están plenamente soportados durante la transición. La guía FlutterFire vigente todavía expone `getToken()`/`onTokenRefresh`; por eso esta versión conserva el modelo de token detrás del repositorio de dispositivos y registra timestamp. En este repositorio, `installationId` es un UUID local que identifica el documento del dispositivo: **no es el FID oficial** y nunca se debe enviar a FCM como token/FID. Aunque la API de envío acepta temporalmente ambos esquemas durante la migración, no sustituya a mano `token`; una migración futura debe coordinar el callback del SDK, el esquema y el backend.

Las instalaciones inactivas más de un mes se consideran candidatas a limpieza; en Android FCM invalida/recoge registros tras 270 días de inactividad. Fuente: [gestión vigente de registros FCM](https://firebase.google.com/docs/cloud-messaging/manage-tokens) y [guía Flutter de FCM](https://firebase.google.com/docs/cloud-messaging/flutter/get-started).

### 13.3 Enviar una notificación manual desde Firebase Console

Esta prueba valida el teléfono y el token, no la lógica de tickets:

1. Copie el valor `token` completo del documento de dispositivo.
2. En Firebase Console abra **Messaging / Cloud Messaging**. Según el menú vigente puede estar bajo **Run**, **Engage** o **DevOps & Engagement**.
3. Pulse **Create your first campaign**, **New campaign** o **Send your first message** y elija **Firebase Notification messages**.
4. Escriba un título y texto de prueba.
5. Pulse **Send test message / Enviar mensaje de prueba**.
6. Pegue el token y agréguelo.
7. Pulse **Test / Probar**.

Pruebe en tres estados:

- **Foreground (abierta):** `FirebaseMessaging.onMessage` recibe el evento y `flutter_local_notifications` lo muestra.
- **Background (segundo plano):** Android/FCM muestra la notificación; al tocarla, `onMessageOpenedApp` navega.
- **Terminated (cerrada por el sistema/usuario):** al tocarla, `getInitialMessage()` recupera el payload y navega después de inicializar Auth/router.

Si la aplicación fue **Forzar detención / Force stop** desde Ajustes Android, FCM no la reactivará hasta que el usuario la abra de nuevo. Esa es una limitación de plataforma, no un error del backend. Fuente: [recibir mensajes FCM en Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).

### 13.4 Probar el flujo real de ticket

Una notificación generada por Functions incluye ambos datos:

```text
ticketId = ID Firestore del ticket
route = /maintenance/tickets/ID_DEL_TICKET
```

Al tocarla debe abrir `/maintenance/tickets/:ticketId`. Si la sesión expiró, el router muestra login y conserva/redirige a la ruta cuando la sesión queda disponible.

Los canales Android son permanentes desde su creación:

- Canal normal: cambios habituales, comentarios y asignaciones.
- Canal urgente: prioridad alta, sonido/vibración y alertas críticas/escalamientos.

Desde Android 8/API 26, todas las notificaciones deben pertenecer a un canal. El usuario controla sonido/visibilidad y la app no puede cambiar la importancia de un canal ya creado; si en el futuro cambia su comportamiento, cree una nueva versión de ID. Fuente: [notification channels](https://developer.android.com/develop/ui/views/notifications/channels).

El backend usa prioridad FCM alta solo para críticas/escalamientos y siempre muestra una notificación visible. FCM puede degradar mensajes high priority que repetidamente no generan contenido visible. Fuente: [prioridad de mensajes Android](https://firebase.google.com/docs/cloud-messaging/android-message-priority).

### 13.5 Diagnóstico si no llega

Revise en este orden:

1. El teléfono tiene Internet, Google Play Services actualizado y fecha/hora automáticas.
2. Gestión Interna tiene permiso de notificaciones y los dos canales no están silenciados.
3. No se aplicó **Forzar detención**.
4. El usuario está activo y existe `users/{uid}/devices/{deviceId}` con token reciente.
5. `firebase_options.dart`, `google-services.json` y Functions pertenecen al mismo Project ID.
6. La prueba directa de Firebase Console llega. Si llega, el problema está en destinatarios/Function; si no llega, está en cliente/token/permiso.
7. `firebase functions:log --project $FirebaseProjectId` no muestra errores `UNAUTHENTICATED`, `PERMISSION_DENIED`, `UNREGISTERED` o payload inválido.
8. El trigger creó `notification_jobs/{eventId}` una sola vez y no quedó en error.
9. La notificación tiene `ticketId` y una ruta que empieza por `/maintenance/tickets/`.
10. Ahorro de batería/OEM no restringe severamente la app. Una notificación FCM no es garantía absoluta de entrega sin Internet; Firestore sigue siendo la fuente de verdad.

Para ver logs Android:

```powershell
flutter logs
```

No publique el token completo en tickets de soporte; permite dirigir mensajes a esa instalación.

## 14. Probar fotografías reales

1. Confirme Blaze, bucket `*.firebasestorage.app` y Rules desplegadas.
2. Inicie sesión en un teléfono físico.
3. Abra un ticket visible para ese usuario.
4. Añada una imagen desde galería; luego repita con cámara y conceda permiso cuando Android lo pida.
5. Espere confirmación de carga; no cierre la app durante el primer ensayo.
6. En Storage Console, confirme la ruta `tickets/{ticketId}/{attachmentId}/{fileName}`.
7. En Firestore, confirme `tickets/{ticketId}/attachments/{attachmentId}`.
8. Abra el mismo ticket con un usuario autorizado y verifique la imagen.
9. Intente acceder con un usuario no participante o archivo no imagen en pruebas de Rules; debe denegarse.

Un error 402/403 en Storage normalmente indica que el proyecto sigue en Spark, la cuenta de Billing no está activa, el usuario no está autorizado o las Rules no fueron desplegadas.

## 15. App Check con Play Integrity (endurecimiento posterior recomendado)

App Check complementa Auth y Rules; no las sustituye. **El MVP no activa enforcement ni declara `firebase_app_check` por defecto**, para no bloquear los APK internos antes de conocer su método de distribución/firma. Este procedimiento es una fase de endurecimiento deliberada: requiere añadir el plugin/código, publicar una build compatible, observar métricas y solo entonces aplicar enforcement.

### Registrar la huella SHA-256

Desde la raíz:

```powershell
.\android\gradlew.bat signingReport
```

Copie la huella SHA-256 del certificado de la variante usada. En Firebase Console:

1. **Project settings > General > Your apps**.
2. Abra `com.samuelpararia.gestioninterna`.
3. Pulse **Add fingerprint / Agregar huella** y pegue SHA-256.
4. Si la app se publica en Google Play con Play App Signing, agregue también la huella del certificado de firma de Play Console.

### Registrar Play Integrity

1. Abra **Security > App Check**.
2. Seleccione la app Android.
3. Registre **Play Integrity**.
4. Añada el plugin con `flutter pub add firebase_app_check` en una rama/cambio revisado.
5. Inicialice `firebase_app_check` después de `Firebase.initializeApp()` y antes de usar Firestore/Storage/Functions; use Play Integrity en release y debug provider solo en desarrollo.
6. Distribuya la build y observe métricas de solicitudes válidas/no verificadas.
7. Solo entonces habilite enforcement desde **Security > App Check** para Authentication, Firestore y Storage, producto por producto.
8. Cloud Functions callable se endurece en código, no con el mismo botón: añada `enforceAppCheck: true` a sus opciones (o a las opciones globales), confirme el rol **Firebase App Check Token Verifier** de la cuenta de servicio si la consola lo solicita, ejecute las pruebas y vuelva a desplegar Functions. El backend entregado mantiene esa opción desactivada hasta completar esta migración.

Para builds locales use el debug provider y registre el token únicamente en la consola. El token debug es secreto: no lo suba a Git ni lo incluya en una build release. Si la empresa instala APK fuera de Google Play, revise las opciones avanzadas de Play Integrity antes de exigir `PLAY_RECOGNIZED`, porque una política demasiado estricta bloquearía instalaciones legítimas.

Fuentes: [App Check Flutter](https://firebase.google.com/docs/app-check/flutter/default-providers), [Play Integrity provider](https://firebase.google.com/docs/app-check/android/play-integrity-provider), [habilitar enforcement por producto](https://firebase.google.com/docs/app-check/enable-enforcement) y [enforcement en Cloud Functions callable](https://firebase.google.com/docs/app-check/cloud-functions).

## 16. Errores frecuentes

### `flutterfire` o `firebase` no se reconoce

Cierre/reabra PowerShell, revise `PATH` y ejecute `Get-Command flutterfire` o `Get-Command firebase`. No copie ejecutables manualmente dentro del repositorio.

### `FirebaseOptions cannot be null` o no existe `firebase_options.dart`

Ejecute `flutterfire configure --project=$FirebaseProjectId --platforms=android --android-package-name=com.samuelpararia.gestioninterna`, confirme el package y vuelva a compilar desde cero:

```powershell
flutter clean
flutter pub get
flutter run
```

### Android registrado con package incorrecto

No intente editar el registro. Corrija `applicationId` a `com.samuelpararia.gestioninterna`, registre una app Android nueva con ese package y vuelva a ejecutar FlutterFire.

### `PERMISSION_DENIED` en Firestore

Confirme: sesión iniciada, documento `users/{uid}`, `active=true`, rol exacto, departamento válido y Rules desplegadas. Ocultar un botón no concede permisos.

### `FAILED_PRECONDITION: The query requires an index`

Despliegue `firestore.indexes.json` y espere a que el índice quede `Enabled`:

```powershell
firebase deploy --only firestore:indexes --project $FirebaseProjectId
```

No cree un índice manual sin agregarlo después al archivo versionado.

### Functions pide facturación

Confirme Blaze y que la cuenta de Cloud Billing esté activa. Spark no permite desplegar Functions.

### Node runtime inválido

`functions/package.json` debe indicar Node 22 y `node --version` debe ser compatible. Ejecute `pnpm --dir functions install --frozen-lockfile` y vuelva a compilar.

### La app física no conecta a Emulator Suite

Use la IP LAN del PC, no `10.0.2.2`; esa dirección es solo del Android Emulator. Verifique que ambos estén en la misma red privada, que no haya VPN y que Firewall permita los puertos solo en perfil privado.

Si falla específicamente una callable con error de cleartext, confirme que ejecuta una build **debug** y que `android/app/src/debug/AndroidManifest.xml` conserva la excepción local. No habilite cleartext en `src/main` ni en release.

### El teléfono abre la app pero no el ticket

Revise que el payload tenga `ticketId` y `route=/maintenance/tickets/<id>`, que el usuario tenga permiso de lectura y que el documento exista. Pruebe la URL/ruta desde navegación interna antes de culpar a FCM.

### Storage devuelve 402/403

402/403 puede ser Spark/facturación ausente, Rules o autorización. Primero confirme Blaze y bucket, luego identidad/ruta/tipo/tamaño. La [FAQ de Storage](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024) documenta el cambio de 2026.

## 17. Comandos diarios de referencia

### Desarrollo local

Terminal 1:

```powershell
firebase emulators:start --project demo-gestion-interna --only "auth,firestore,functions,storage"
```

Terminal 2, una vez:

```powershell
npm --prefix scripts run seed
```

Terminal 3, Android Emulator:

```powershell
flutter run --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
```

### Calidad antes de desplegar

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
npm --prefix functions run build
npm --prefix functions run lint
npm --prefix functions test
npm --prefix scripts run build
```

### Despliegue real

```powershell
firebase deploy --only firestore:rules --project $FirebaseProjectId
firebase deploy --only firestore:indexes --project $FirebaseProjectId
firebase deploy --only storage --project $FirebaseProjectId
firebase deploy --only functions --project $FirebaseProjectId
```

### Build APK de prueba

```powershell
flutter build apk --release
```

El APK resultante normalmente queda en `build\app\outputs\flutter-apk\app-release.apk`. Antes de distribución real configure firma release propia; no distribuya una build firmada con clave debug.

# CHECKLIST FINAL PARA SAMUEL

Complete la lista en orden. No marque una línea por suposición: compruebe el resultado indicado.

1. [ ] Instalar Flutter 3.44.7 y confirmar `flutter --version`.
2. [ ] Confirmar Dart 3.12.2 con `dart --version`.
3. [ ] Instalar Android Studio, SDK, JDK 17 e imagen con Google Play.
4. [ ] Ejecutar `flutter doctor -v` y corregir errores de Android toolchain.
5. [ ] Instalar Node.js 22; comprobar `node --version` y `npm --version`.
6. [ ] Ejecutar `npm install --global firebase-tools` y comprobar `firebase --version`.
7. [ ] Ejecutar `dart pub global activate flutterfire_cli` y comprobar `flutterfire --version`.
8. [ ] Abrir Firebase Console y crear el proyecto real `Gestión Interna`; anotar el Project ID exacto.
9. [ ] Actualizar el proyecto a Blaze, enlazar Cloud Billing y crear presupuesto/alertas.
10. [ ] En PowerShell definir `$FirebaseProjectId = 'ID-REAL'`.
11. [ ] Ejecutar `firebase login`, autorizar la cuenta y confirmar con `firebase projects:list`.
12. [ ] Ejecutar `firebase use --add`, seleccionar `$FirebaseProjectId`, asignar alias `production` y ejecutar `firebase use production`.
13. [ ] Confirmar que `applicationId` es `com.samuelpararia.gestioninterna`.
14. [ ] Ejecutar `flutterfire configure --project=$FirebaseProjectId --platforms=android --android-package-name=com.samuelpararia.gestioninterna` y seleccionar solo Android.
15. [ ] Confirmar que se generó `lib/firebase_options.dart` y que la app Android corresponde al package exacto.
16. [ ] En Authentication, habilitar Email/Password.
17. [ ] Crear Firestore Standard, Production mode, región `us-central1`.
18. [ ] Crear Storage en `us-central1` y confirmar bucket `*.firebasestorage.app`.
19. [ ] Ejecutar `flutter pub get`, `pnpm --dir functions install --frozen-lockfile` y `pnpm --dir scripts install --frozen-lockfile`.
20. [ ] Abrir Emulator Suite con `firebase emulators:start --project demo-gestion-interna --only "auth,firestore,functions,storage"`.
21. [ ] Abrir `http://127.0.0.1:4000` y confirmar Auth, Firestore, Functions y Storage activos.
22. [ ] Ejecutar `npm --prefix scripts run seed` y revisar `Columbia 21` y `settings/maintenance`.
23. [ ] Ejecutar la app en Android Emulator con `USE_FIREBASE_EMULATORS=true` y host `10.0.2.2`.
24. [ ] Probar login/ticket/cambio de estado local y confirmar datos/eventos en Emulator UI.
25. [ ] Ejecutar `flutter analyze`, `flutter test` y las tres verificaciones de Functions.
26. [ ] Desplegar Firestore Rules, índices y Storage Rules con los comandos de la sección 17.
27. [ ] Desplegar Functions y confirmar todas en `us-central1`.
28. [ ] Confirmar que `checkOverdueTickets` está programada cada cinco minutos en `America/Bogota`.
29. [ ] Ejecutar el seed real con `--production --project ... --confirm-project ...` después de verificar el ID.
30. [ ] Crear en Authentication un usuario de Planta y copiar su UID.
31. [ ] Crear su perfil Firestore con `role=production`, `departmentId=production`, `active=true` mediante `manage-user`.
32. [ ] Crear en Authentication un usuario de Mantenimiento y copiar su UID.
33. [ ] Crear su perfil con `role=maintenance`, `departmentId=maintenance`, `active=true`.
34. [ ] Instalar la build real en **Celular A**, iniciar como Planta y permitir notificaciones.
35. [ ] Instalarla en **Celular B**, iniciar como Mantenimiento y permitir notificaciones.
36. [ ] Confirmar un documento diferente en `users/{uid}/devices/{deviceId}` para cada instalación.
37. [ ] Enviar a cada token una notificación de prueba desde Firebase Console en foreground, background y terminated.
38. [ ] En Celular A crear `Falla Columbia 21`, Producción detenida = Sí, prioridad Crítica.
39. [ ] Confirmar que Celular B recibe el push y que tocarlo abre el ticket correcto.
40. [ ] En Celular B marcar Recibido, asignar, pasar a En proceso y comentar; en Celular A registrar **Producción reanudada** con motivo y validar `productionImpactChanged`/notificación antes de resolver.
41. [ ] En Celular A confirmar cierre; comprobar estado `closed` y eventos inmutables.
42. [ ] Repetir con otro ticket y pulsar **ESCALAR URGENCIA**; validar canal urgente, cooldown y auditoría.
43. [ ] Probar una fotografía desde galería/cámara y confirmar Storage + metadata Firestore.
44. [ ] Revisar Functions logs, `notification_jobs` y verificar que no haya duplicados ni errores.
45. [ ] Revisar **Usage and billing**, destinatarios del presupuesto y cuotas después de la prueba.
46. [ ] Configurar firma release propia antes de distribuir el APK a trabajadores.
47. [ ] Como endurecimiento posterior: implementar App Check/Play Integrity, observar métricas y habilitar enforcement gradualmente después de validar los teléfonos reales.

El escenario verificable completo está en [TESTING.md](TESTING.md). El uso cotidiano por rol está en [USER_GUIDE.md](USER_GUIDE.md).

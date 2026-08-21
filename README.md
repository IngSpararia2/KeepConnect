# Gestión Interna

Aplicación Android interna para crear, atender y auditar solicitudes de mantenimiento entre Planta de Producción y Mantenimiento. El flujo cubre creación, notificación, reconocimiento, asignación, ejecución, conversación, escalamiento, resolución, confirmación y cierre.

Nombre visible: **Gestión Interna**  
Package Android: `com.samuelpararia.gestioninterna`  
Plataforma de esta versión: **Android únicamente**

## Funcionalidad principal

- Firebase Authentication con correo/contraseña, sesión persistente, logout y recuperación.
- Perfiles Firestore con roles `admin`, `production` y `maintenance`.
- Home extensible por módulos; Mantenimiento es el único habilitado en el MVP.
- Dashboard/listas por rol, filtros, búsqueda normalizada y datos en tiempo real.
- Creación de tickets con impacto, activo, prioridad sugerida/configurable y preguntas dinámicas.
- Actualización auditada de parada/reanudación de producción durante un ticket abierto.
- Código humano transaccional `MTTO-YYYYMMDD-NNNN` más ID interno Firestore.
- Máquina de estados validada también en backend.
- Responsable principal, participantes, comentarios, fotos y auditoría inmutable.
- Resolución separada de cierre; el solicitante puede confirmar o pedir revisión.
- Escalamiento manual con confirmación/cooldown y automático programado.
- FCM por dispositivo, múltiples teléfonos, renovación/limpieza de tokens y deep link al ticket.
- Canales Android normal y urgente, foreground/background/terminated.
- Emulator Suite para Auth, Firestore, Functions y Storage.
- Rules, índices, Functions TypeScript y scripts administrativos/seed.

## Tecnologías

- Flutter 3.44.7 / Dart 3.12.2, Material 3.
- Riverpod y `go_router`.
- FlutterFire: Auth, Firestore, Functions, Messaging y Storage.
- `flutter_local_notifications` e `image_picker`.
- Cloud Functions for Firebase 2nd gen, TypeScript, Node.js 22.
- Firebase Admin SDK, FCM y Cloud Scheduler.
- Vitest/ESLint/TypeScript y Flutter tests.

## Estado de configuración Firebase

El repositorio no inventa credenciales. `lib/firebase_options.dart` empieza como placeholder y permite ejecutar el modo emulador. Para Firebase real, Samuel debe ejecutar `flutterfire configure`; la herramienta oficial reemplaza el placeholder con identificadores reales.

La producción requiere **Blaze**:

- Cloud Functions desplegadas no están disponibles en Spark.
- Desde el 3 de febrero de 2026, Cloud Storage real exige Blaze y en Spark responde 402/403.
- Blaze conserva cuotas sin costo, pero permite excesos facturables. Configure presupuesto/alertas antes de desplegar.

FCM es gratuito, pero no se emula. La validación push exige un proyecto real y dos teléfonos. Detalles: [costos y cuotas](docs/FIREBASE_COSTS.md).

## Requisitos

- Windows PowerShell.
- Flutter 3.44.7 con Android toolchain.
- Dart 3.12.2.
- Android SDK y JDK 17 para compilar; JDK 21 para Firebase Emulator Suite.
- Node.js 22, npm y Corepack/pnpm.
- Firebase CLI.
- FlutterFire CLI para el entorno real.

Verificación:

```powershell
flutter --version
dart --version
java -version
node --version
npm --version
corepack --version
pnpm --version
firebase --version
flutterfire --version
flutter doctor -v
```

Si Windows PowerShell bloquea los lanzadores `npm.ps1`, `pnpm.ps1` o
`firebase.ps1`, use sus equivalentes seguros `npm.cmd`, `pnpm.cmd` y
`firebase.cmd`. No hace falta desactivar la política de ejecución.

## Inicio rápido con Emulator Suite

Desde la raíz del repositorio:

```powershell
flutter pub get
corepack enable
pnpm --dir functions install --frozen-lockfile
pnpm --dir scripts install --frozen-lockfile
```

Terminal 1:

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '30'
firebase.cmd emulators:start --project demo-gestion-interna --only "auth,firestore,functions,storage"
```

Abra [http://127.0.0.1:4000](http://127.0.0.1:4000). Puertos: Auth 9099, Firestore 8080, Functions 5001, Storage 9199 y UI 4000. Los cuatro servicios se enlazan a `0.0.0.0` para la LAN; UI permanece en `127.0.0.1`.

Terminal 2, para cargar catálogos/configuración demo:

```powershell
npm --prefix scripts run seed
```

Terminal 3, Android Emulator:

```powershell
flutter run --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
```

En un teléfono físico conectado a la misma red privada, reemplace `10.0.2.2` por la IPv4 LAN del PC y permita los puertos solo en el perfil privado del Firewall. Nunca los reenvíe/exhiba a Internet:

```powershell
flutter run --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.25
```

El HTTP sin cifrar del emulador se permite solo en el manifest Android `debug`; no traslade esa excepción a `main`/release.

FCM queda deshabilitado/logueado en modo emulador; no configure credenciales reales en esa terminal.

## Ejecutar con Firebase real

Resumen; siga el procedimiento literal completo en [FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md).

```powershell
firebase login
$FirebaseProjectId = 'PROJECT-ID-REAL'
firebase use --add
firebase use production
flutterfire configure --project=$FirebaseProjectId --platforms=android --android-package-name=com.samuelpararia.gestioninterna
flutter pub get
```

En `firebase use --add`, seleccione `$FirebaseProjectId` y asigne el alias `production`. En Firebase Console habilite Email/Password, cree Firestore Standard y Storage en `us-central1`, active Blaze y configure presupuesto.

Despliegue:

```powershell
firebase deploy --only firestore:rules --project $FirebaseProjectId
firebase deploy --only firestore:indexes --project $FirebaseProjectId
firebase deploy --only storage --project $FirebaseProjectId
firebase deploy --only functions --project $FirebaseProjectId
```

Ejecute la app sin flags de emulador:

```powershell
flutter run --release
```

## Verificaciones de calidad

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
npm --prefix functions run build
npm --prefix functions run lint
npm --prefix functions test
npm --prefix scripts run build
```

La prueba de aceptación Android/FCM se describe paso a paso en [TESTING.md](docs/TESTING.md), incluido el escenario:

```text
Celular A (Planta) crea Columbia 21 detenida/crítica
  -> Celular B (Mantenimiento) recibe y reconoce
  -> asigna, inicia y comenta
  -> Celular A registra la reanudación de producción
  -> Planta recibe actualizaciones
  -> Mantenimiento resuelve
  -> Planta confirma cierre
  -> auditoría y notificaciones se verifican en cada etapa
```

## Arquitectura y estructura

```text
lib/
  app/                  router y tema
  config/               parámetros centralizados
  core/                 Firebase, errores, notificaciones, utilidades
  features/
    auth/               sesión/perfil
    home/               módulos
    maintenance/        data/domain/application/presentation
  shared/               widgets reutilizables

functions/              backend TypeScript Node 22
scripts/                seed y administración segura
test/                   pruebas Flutter
firebase.json           emuladores/deploy
firestore.rules         autorización de datos
firestore.indexes.json  consultas versionadas
storage.rules           evidencia fotográfica
docs/                   operación, arquitectura y pruebas
```

Las mutaciones críticas no escriben tickets directamente desde Flutter. Usan callables:

```text
createTicket
transitionTicket
assignTicket
addComment
updatePriority
updateProductionImpact
registerAttachment
escalateTicket
registerDevice
unregisterDevice
```

Triggers: `onTicketCreated`, `onTicketUpdated`, `onCommentCreated`. El Scheduler ejecuta `checkOverdueTickets` cada cinco minutos, zona `America/Bogota`. Functions/Firestore/Storage se co-localizan en `us-central1`.

El diseño completo, colecciones, roles, máquina de estados e idempotencia están en [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Documentación

- [Configuración Firebase desde cero](docs/FIREBASE_SETUP.md): consola, CLI, Android, Auth, Firestore, Storage, Functions, FCM, emuladores y checklist final para Samuel.
- [Arquitectura](docs/ARCHITECTURE.md): capas, datos, reglas de negocio y flujo push.
- [Costos Firebase](docs/FIREBASE_COSTS.md): Spark/Blaze, cuotas y alertas.
- [Pruebas](docs/TESTING.md): suites, Rules y escenario real de dos celulares.
- [Guía de usuario](docs/USER_GUIDE.md): operación por rol desde creación hasta cierre.

## Configuración central

`lib/config/app_config.dart` contiene nombre, créditos, región, IDs de módulo/departamentos, flags de emulador y límites. No disperse esos valores.

Canales Android estables:

```text
gestion_interna_normal_v1
gestion_interna_urgent_v1
```

Storage:

```text
tickets/{ticketId}/{attachmentId}/{fileName}
```

Deep link interno:

```text
/maintenance/tickets/:ticketId
```

## Seguridad

- Ninguna credencial Admin vive en Flutter/APK.
- Los archivos de configuración cliente de FlutterFire no son secretos; Service Account JSON, private keys, FCM Server Keys, secretos y tokens App Check sí lo son.
- UI no sustituye Rules; Functions vuelve a validar usuario activo, rol, área y relación.
- Auditoría, contadores, `_command_receipts`, `notification_jobs`, `device_installations` y `device_tokens` son backend-only.
- `registerDevice`/`unregisterDevice` administran el device doc autenticado y garantizan un solo dueño por instalación/token; Flutter no lo escribe directamente.
- Las imágenes están limitadas a rutas, MIME/tamaño y participantes autorizados.
- App Check/Play Integrity se habilita gradualmente después de observar métricas.

## Límites conscientes del MVP

- Solo Android y Email/Password.
- Mantenimiento es el único módulo funcional; los catálogos permiten crecer.
- Búsqueda por tokens/campos, no full-text externo.
- Cinco fotos por ticket, 5 MiB cada una; reducción aproximada 1600×1600/calidad 75 depende del codec.
- FCM no garantiza entrega sin Internet, con permiso denegado o después de Force stop; Firestore es la fuente de verdad.
- App Check requiere configuración manual de huellas/Play Integrity antes de enforcement.
- La build release del esqueleto Android usa firma debug para pruebas. Configure una keystore release segura antes de distribuirla a trabajadores o Play.

## Branding

Nombre visible y créditos se centralizan en `AppConfig`; el label Android está en `android/app/src/main/AndroidManifest.xml`, package/namespace en `android/app/build.gradle.kts` y los iconos en `android/app/src/main/res/mipmap-*`. Cambiar el package después de registrar Firebase implica registrar otra app Android.

---

**App desarrollada por Ing. Samuel Parariá – Derechos Reservados**

# Gestión Interna · KeepConnect

Prototipo Android local y offline para validar solicitudes de mantenimiento entre Planta y Mantenimiento en un solo dispositivo.

## Flujo

1. Seleccionar el área Planta.
2. Crear una solicitud y sus preguntas personalizadas.
3. Alternar el **Modo de prueba** entre Vista Planta y Vista Mantenimiento.
4. Mantenimiento avanza `Pendiente → En revisión → En ejecución → Finalizado`, guarda respuestas parciales y registra actualizaciones.
5. Planta consulta respuestas, actualizaciones, historial y notificaciones, y puede añadir información o preguntas posteriores.

Los tickets, preguntas, respuestas, actualizaciones, eventos y notificaciones se almacenan en SQLite. Las notificaciones Android son locales y la bandeja interna sigue funcionando aunque el permiso del sistema esté denegado.

## Tecnología

- Flutter / Material 3
- Riverpod y `go_router`
- SQLite mediante `sqlite3`, `path` y `path_provider`
- `flutter_local_notifications`
- Android; no requiere Firebase, backend, cuentas ni conexión a Internet

## Verificación y APK de prueba

La generación principal ejecuta `flutter pub get → flutter analyze → flutter test → flutter build apk --debug`. Si alguna validación falla, no se genera una APK considerada válida.

Desde Windows, usa una compilación limpia:

```powershell
.\generar_apk.bat
```

Para repetir el mismo flujo validado reutilizando la caché de compilación:

```powershell
.\actualizar_apk.bat
```

La APK queda en `build/app/outputs/flutter-apk/app-debug.apk`. Es una APK debug para pruebas locales, no una release comercial. Una release futura requiere un keystore privado y `android/key.properties` con `storeFile`, `storePassword`, `keyAlias` y `keyPassword`; esos archivos y credenciales no se versionan.

Cuando el checkout está en una ruta con espacios, el script usa temporalmente `K:` y ejecuta el SDK desde `.tooling/flutter`. Esa carpeta es local, permanece ignorada y debe existir; el script informa claramente si falta y siempre desmonta la unidad al terminar.

**App desarrollada por Ing. Samuel Parariá - Derechos Reservados**

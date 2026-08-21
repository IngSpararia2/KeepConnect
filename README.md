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

## Verificación

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

**App desarrollada por Ing. Samuel Parariá - Derechos Reservados**

# Guía de usuario

## Qué es Gestión Interna

Gestión Interna es una aplicación Android para comunicar y seguir solicitudes internas. La primera versión incluye el módulo **Mantenimiento** y conecta principalmente Planta de Producción con el área de Mantenimiento.

Cada solicitud conserva:

- quién la creó;
- qué equipo/ubicación afecta;
- prioridad sugerida y seleccionada;
- estado y responsables;
- conversación y fotografías;
- diagnóstico/trabajo realizado;
- cada cambio importante con actor y fecha;
- notificaciones a las personas relevantes.

> La app no reemplaza alarmas, bloqueo/etiquetado, evacuación, llamadas de emergencia ni los procedimientos de seguridad de la empresa. Ante riesgo inmediato, primero siga el protocolo oficial y después registre/actualice el ticket cuando sea seguro.

## 1. Antes de comenzar

Necesita:

- teléfono Android 7.0/API 24 o posterior;
- conexión a Internet para enviar cambios y recibir notificaciones;
- cuenta creada por el administrador;
- permiso de notificaciones habilitado;
- cámara/galería solo si desea adjuntar evidencia.

No comparta su contraseña. La aplicación nunca solicitará una clave de Firebase, Server Key o archivo de Service Account.

## 2. Iniciar sesión

1. Abra **Gestión Interna**.
2. Escriba el correo corporativo registrado.
3. Escriba su contraseña.
4. Pulse **Iniciar sesión**.
5. Espere mientras se valida su perfil y rol.

Si las credenciales son correctas pero el perfil está desactivado, contacte al administrador. No intente crear otra cuenta por su cuenta.

### Olvidé mi contraseña

1. En Login pulse **Olvidé mi contraseña**.
2. Introduzca el correo registrado.
3. Pulse **Enviar enlace**.
4. Revise bandeja de entrada y spam.
5. Abra el enlace oficial y establezca una contraseña nueva.

### Cerrar sesión

Conecte el teléfono a Internet, abra el menú de usuario y pulse **Cerrar sesión**. Antes de cerrar Auth, la app intenta retirar mediante `unregisterDevice` el registro push de esa instalación. Si la red o Firebase fallan, el cierre sigue siendo posible y el registro podría permanecer temporalmente; el backend lo reasigna de forma exclusiva en el siguiente inicio de sesión de esa instalación y elimina tokens que FCM rechaza. Para un teléfono compartido, confirme el cierre con red antes de entregarlo. Esto no borra tickets ni comentarios.

## 3. Permiso de notificaciones

En Android 13 o posterior, el primer inicio de sesión en esa instalación solicita permiso.

- Pulse **Permitir** para recibir tickets y cambios.
- Si pulsa **No permitir**, puede seguir usando la app, pero no verá alertas push.
- Para corregirlo: **Ajustes del teléfono > Aplicaciones > Gestión Interna > Notificaciones > Permitir**.

La app crea dos canales:

- **Actualizaciones de solicitudes:** avisos normales.
- **Solicitudes críticas y urgentes:** emergencias, producción detenida y escalamiento.

Android permite silenciar cada canal. Si un aviso crítico no suena, revise volumen, No molestar, ahorro de batería y la configuración del canal urgente.

## 4. Home

Después del login aparece la pantalla principal. En esta versión muestra una tarjeta grande:

**Mantenimiento**

Pulse la tarjeta para entrar. La estructura admite futuros módulos como Calidad, Laboratorio o Logística sin mezclar sus solicitudes.

En la parte inferior aparece:

**App desarrollada por Ing. Samuel Parariá – Derechos Reservados**

## 5. Qué ve cada rol

### Producción

- Crear solicitud.
- Mis solicitudes abiertas/historial.
- Ver estado en tiempo real.
- Comentar y adjuntar evidencia.
- Escalar urgencia con confirmación/cooldown.
- Reportar una nueva parada o confirmar reanudación mientras el ticket siga abierto.
- Confirmar cierre o solicitar nueva revisión.
- Cancelar su ticket mientras siga pendiente, si corresponde.

### Mantenimiento

- Solicitudes destinadas a Mantenimiento.
- Pendientes, críticas y asignadas a mí.
- Marcar recibido.
- Asignar responsable/participantes autorizados.
- Iniciar, pausar, esperar repuesto/externo y retomar.
- Comentar, adjuntar, diagnosticar y resolver.

### Administrador

- Vista global y funciones de supervisión.
- Gestión de usuarios/catálogos mediante herramientas administrativas.
- Acciones excepcionales permitidas por backend, siempre auditadas.

Que un botón no aparezca no es un error necesariamente: depende de rol, estado y relación con el ticket.

## 6. Dashboard y listas

El Dashboard resume según el rol:

- Pendientes.
- Críticos.
- En proceso.
- En espera de repuesto.
- Resueltos pendientes de confirmar.
- Asignados a mí para Mantenimiento.

El conjunto de tickets ya viene limitado por rol: Producción recibe sus solicitudes, Mantenimiento las del área y Administración la vista global.

Pulse una tarjeta para abrir la lista filtrada. En la lista puede combinar estado, prioridad, **Producción detenida** e **Historial**. La tarjeta **Asignadas a mí** aplica además el responsable actual.

La búsqueda MVP está optimizada para código, título y equipo mediante términos normalizados. No es un buscador de texto completo: una frase arbitraria dentro de una descripción puede no encontrarse. Use filtros/código cuando sea posible.

## 7. Crear una solicitud

Rol habitual: Producción.

1. Abra **Mantenimiento**.
2. Pulse **Crear solicitud**.
3. Complete cada sección. Los campos obligatorios se marcan claramente.
4. Revise la sugerencia de prioridad y el resumen.
5. Adjunte evidencia si ayuda y es seguro tomarla.
6. Pulse **Enviar solicitud** una sola vez y espere confirmación.

El servidor genera el código, por ejemplo `MTTO-20260814-0001`. No invente ni copie un código de otro ticket.

### Información básica

- **Título breve:** describa el problema, no “Ayuda”. Ejemplo: `Columbia 21 detenida`.
- **Descripción:** síntomas observados, momento y contexto. No diagnostique si no sabe.
- **Área solicitante/destino:** el sistema la deriva del perfil; en este MVP usa Producción → Mantenimiento.
- **Ubicación:** línea, zona o punto suficientemente preciso.
- **Categoría:** reparación, correctivo, preventivo, instalación, infraestructura, electricidad, agua, equipos, herramientas, mobiliario, seguridad u otro.
- **Equipo/activo:** elija del catálogo, por ejemplo Columbia 21.

### Impacto

Responda con exactitud:

- **¿La falla tiene detenida la producción?**
- **¿Existe riesgo para la seguridad de personas o equipos?**
- Porcentaje aproximado de afectación, si puede estimarlo.
- Observaciones de impacto.

Si marca producción detenida, el detalle muestra **PRODUCCIÓN DETENIDA** de forma destacada y el servidor registra la hora de inicio.

Mientras el ticket siga abierto, su solicitante de Producción puede usar la acción del detalle:

- **Producción reanudada** cuando el indicador esté detenido.
- **Reportar parada** si la producción vuelve a detenerse.

La acción exige un motivo y guarda hora/usuario en `productionImpactChanged`; Mantenimiento recibe una actualización y una nueva parada usa el canal urgente. No la use para corregir la prioridad: el impacto y la prioridad son datos separados, y Mantenimiento/Administración cambia la prioridad con su acción auditada cuando corresponda.

### Prioridad

| Nivel | Uso orientativo |
|---|---|
| Baja | Puede programarse, impacto reducido. |
| Media | Requiere atención, sin impacto severo inmediato. |
| Alta | Impacto importante o producción detenida. |
| Crítica | Riesgo/paro crítico que exige atención inmediata. |

La app sugiere prioridad usando producción detenida, seguridad, activo crítico y afectación. Son criterios operativos configurables, **no una norma industrial oficial**.

Puede elegir otro nivel. Si reduce la prioridad sugerida, debe explicar el motivo; si la aumenta, el formulario no lo exige. El sistema conserva sugerida, final, quién decidió y cuándo. Cualquier cambio posterior de prioridad sí exige motivo y queda auditado.

### Preguntas adicionales

Según la plantilla pueden aparecer:

- texto corto/largo;
- número;
- Sí/No;
- selección única/múltiple;
- checklist;
- fecha;
- foto.

Responda los campos requeridos. La versión de la plantilla queda asociada al ticket para conservar el contexto histórico.

### Fotografías

Puede tomar una foto o elegirla de galería.

- Máximo inicial: cinco fotos por ticket.
- Límite duro: 5 MiB por archivo.
- La app pide al sistema una reducción aproximada a 1600×1600 y calidad 75 cuando el formato lo permite.
- HEIC y algunos formatos pueden variar según el fabricante; si supera 5 MiB, elija/cree una imagen menor.
- No fotografíe información personal, claves, tableros sensibles o personas sin autorización.
- No se acerque a maquinaria peligrosa para obtener una foto.

Una evidencia se almacena fuera de Firestore y queda registrada en el historial del ticket.

## 8. Leer el detalle

El detalle reúne:

- código, estado y prioridad;
- título/descripción;
- solicitante, área, ubicación;
- activo y su snapshot histórico;
- producción detenida y riesgo;
- responsable/participantes;
- fechas y tiempo transcurrido;
- respuestas dinámicas;
- fotos;
- conversación;
- historial/auditoría;
- diagnóstico, trabajo y resolución.

Las acciones visibles cambian con estado/rol. Actualice la lista o revise conexión si un cambio tarda; Firestore normalmente lo muestra en tiempo real.

## 9. Estados

| Estado visible | Significado |
|---|---|
| Pendiente | Creado; Mantenimiento aún no lo reconoce. |
| Recibido | Mantenimiento confirmó recepción. |
| Asignado | Tiene responsable principal/participantes. |
| En proceso | El trabajo está en ejecución. |
| En espera de repuesto | Falta un repuesto; motivo registrado. |
| En espera externa | Depende de proveedor/tercero. |
| Pausado | Trabajo suspendido con motivo. |
| Resuelto | Mantenimiento terminó; falta aceptación de Planta. |
| Cerrado | Solicitante confirmó la solución. |
| Cancelado | Se anuló conforme a permisos/estado. |

No se puede saltar de cualquier estado a otro. Flujo habitual:

```text
Pendiente -> Recibido -> Asignado -> En proceso
          -> Resuelto -> Cerrado
```

Las esperas/pausa salen de En proceso y regresan a En proceso. Un ticket resuelto puede volver a En proceso si el solicitante pide revisión. Cerrado/Cancelado son terminales.

## 10. Recibir y asignar (Mantenimiento)

### Marcar recibido

1. Abra una solicitud Pendiente.
2. Revise riesgo, producción detenida, ubicación y activo.
3. Pulse **Marcar recibido**.
4. Confirme.

Se guardan técnico y hora; Planta recibe actualización.

### Asignar

1. En estado Recibido pulse **Asignar**.
2. Elija responsable principal activo de Mantenimiento.
3. Añada participantes si hace falta.
4. Confirme.

No use asignación para compartir un ticket con personas ajenas. Cada cambio queda auditado y notifica según corresponda.

### Iniciar trabajo

El responsable/participante abre el ticket Asignado y pulsa **Iniciar trabajo**. Se establece En proceso y `workStartedAt`.

### Esperas y pausa

Desde En proceso:

- **Esperando repuesto**: indique cuál/por qué.
- **Espera externa**: indique dependencia/proveedor.
- **Pausar**: explique el motivo.

Cuando pueda continuar, pulse **Reanudar trabajo**. No marque Resuelto solo para detener el reloj.

## 11. Conversación

En el ticket abra **Comentarios/Conversación**:

1. Escriba información relacionada con el trabajo.
2. Pulse **Enviar** una sola vez.
3. El comentario aparece en tiempo real y se notifica a otros participantes, no normalmente al autor.

Buenas prácticas:

- Sea concreto: acción, resultado y siguiente paso.
- No incluya contraseñas ni datos personales innecesarios.
- No use comentarios para cambiar informalmente estado/prioridad; use la acción correspondiente para que quede estructurada.
- Un comentario forma parte de la trazabilidad y no debe tratarse como chat desechable.

## 12. ESCALAR URGENCIA (Producción)

Use esta acción cuando un ticket abierto requiere atención inmediata adicional. No reemplaza una llamada/protocolo de emergencia.

1. Abra el ticket.
2. Pulse **ESCALAR URGENCIA**.
3. Lea la confirmación.
4. Escriba un motivo, por ejemplo: `Producción continúa completamente paralizada.`
5. Confirme una vez.

El sistema:

- registra usuario, fecha, motivo y contador;
- genera evento de auditoría;
- alerta al personal relevante por canal urgente;
- impide repeticiones accidentales durante un cooldown (demo: 15 minutos).

Si aparece “cooldown activo”, no pulse repetidamente. Llame por el canal operativo de emergencia si la situación lo exige.

Los tickets críticos sin reconocimiento también pueden escalar automáticamente. Configuración demo: 30 minutos para crítico, revisión cada cinco minutos y niveles limitados. Al marcar Recibido, cesa el escalamiento por falta de reconocimiento.

## 13. Resolver (Mantenimiento)

Desde En proceso:

1. Pulse **Resolver solicitud**.
2. Complete **Diagnóstico**.
3. Complete **Trabajo realizado**.
4. Añada observaciones/solución.
5. Adjunte evidencia opcional cuando sea segura/útil.
6. Pulse **Marcar resuelto** y confirme.

“Resuelto” significa que Mantenimiento terminó, no que Planta ya aceptó. El solicitante recibe una notificación para revisar.

## 14. Cerrar o solicitar revisión (Producción)

Cuando el ticket esté Resuelto:

### Si quedó solucionado

1. Revise solución/evidencia.
2. Verifique operacionalmente conforme al procedimiento de planta.
3. Pulse **Confirmar cierre**.
4. Confirme. El estado pasa a Cerrado.

### Si el problema continúa

1. Pulse **Solicitar revisión nuevamente**.
2. Explique qué continúa fallando.
3. Confirme.

El ticket vuelve a En proceso, aumenta el contador de reaperturas y notifica a Mantenimiento. No cree un ticket duplicado para ocultar una resolución fallida.

## 15. Notificaciones y apertura directa

Las notificaciones incluyen el ticket. Al tocarlas se abre:

```text
/maintenance/tickets/<ticketId>
```

- App abierta: se muestra una notificación local.
- Segundo plano: Android la muestra y abre el ticket al tocar.
- Cerrada normalmente: abre la app y luego el ticket al iniciar.

Si Android aplicó **Forzar detención**, no recibirá FCM hasta abrir la app otra vez. Sin Internet tampoco hay entrega inmediata; al reconectar, Firestore muestra el estado real.

FCM es un aviso, no una confirmación de que alguien atendió. Use el estado **Recibido** para saber que Mantenimiento reconoció el ticket.

## 16. Trabajo sin conexión

La app puede mostrar datos ya cacheados cuando se pierde Internet. El banner **Datos locales/cache** indica que la lista proviene de la caché; no es un medidor perfecto de la conexión física. Una operación que necesita servidor muestra además un error accionable si no logra completarse.

- No asuma que un comentario/cambio se guardó hasta ver confirmación.
- No pulse muchas veces; espere o reintente una vez tras recuperar red.
- Las transiciones, asignaciones, escalamiento y creación requieren backend.
- FCM no llega sin Internet.
- Al reconectar, revise el historial para confirmar una sola acción.

## 17. Mensajes frecuentes

### “Usuario desactivado”

Su cuenta Auth existe, pero el perfil interno está inactivo. Contacte al administrador.

### “Operación no permitida”

Su rol, relación o estado no permite esa acción. Revise el flujo. Si debería permitirse, informe código del ticket y acción, no su contraseña.

### “La imagen supera 5 MiB”

Recorte la foto, use una resolución menor o seleccione otra. Algunos HEIC no reducen igual que JPEG.

### “Sin conexión” o timeout

Revise Wi‑Fi/datos, espere y reintente. No cree otro ticket hasta verificar si el primero tiene código.

### No recibo notificaciones

1. Abra la app al menos una vez después de instalar/reiniciar.
2. Revise permiso y canales en Ajustes Android.
3. Quite Force stop; abra de nuevo.
4. Revise Internet, No molestar y ahorro de batería.
5. Cierre sesión/inicie de nuevo si el administrador lo indica.
6. Informe modelo Android, hora y código de ticket; no envíe token públicamente.

### La notificación abre “sin permiso”

El ticket existe, pero su usuario ya no tiene autorización, fue desactivado o cambió de área. Contacte al administrador; el link nunca evita Security Rules.

## 18. Buenas prácticas en planta

- Use títulos específicos y una ubicación precisa.
- Marque producción detenida/riesgo con honestidad.
- Evite tickets duplicados; comente o escale el existente.
- No abuse del canal urgente.
- No cierre sin validar la solución.
- No altere fotos ni elimine contexto relevante.
- No comparta APKs de origen desconocido.
- Mantenga Android/Google Play Services actualizados.
- Si cambia de teléfono o deja la empresa, cierre sesión y avise al administrador.

## 19. Soporte: datos útiles

Al reportar un problema incluya:

- código humano del ticket;
- acción intentada;
- fecha/hora aproximada;
- rol (sin contraseña);
- modelo/versión Android;
- si la app estaba abierta, background o cerrada;
- mensaje visible;
- captura sin información sensible.

No envíe contraseña, token FCM, API keys privadas ni Service Account JSON.

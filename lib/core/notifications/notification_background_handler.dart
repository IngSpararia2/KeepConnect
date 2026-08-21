import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_constants.dart';
import 'notification_message.dart';

bool _backgroundHandlerRegistered = false;

/// Registers the top-level FCM callback required by Android background isolates.
///
/// Call this before `runApp` whenever notifications are enabled. The service
/// also calls it during initialization as a defensive fallback.
void registerNotificationBackgroundHandler({bool enabled = true}) {
  if (!enabled || _backgroundHandlerRegistered) {
    return;
  }
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  _backgroundHandlerRegistered = true;
}

/// Handles data-only FCM messages while the app is backgrounded or terminated.
///
/// Messages with a `notification` payload are rendered by Android/FCM itself,
/// so they are deliberately ignored here to prevent duplicate notifications.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    if (message.notification != null || message.data.isEmpty) {
      return;
    }

    final notification = NotificationMessage.fromRemoteMessage(message);
    final localNotifications = FlutterLocalNotificationsPlugin();
    await localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(
          NotificationConstants.notificationIcon,
        ),
      ),
    );

    final androidPlugin = localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      NotificationConstants.normalChannel,
    );
    await androidPlugin?.createNotificationChannel(
      NotificationConstants.urgentChannel,
    );

    final channel = notification.isUrgent
        ? NotificationConstants.urgentChannel
        : NotificationConstants.normalChannel;
    await localNotifications.show(
      id: _notificationId(notification.messageId),
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          icon: NotificationConstants.notificationIcon,
          importance: notification.isUrgent
              ? Importance.max
              : Importance.defaultImportance,
          priority: notification.isUrgent
              ? Priority.max
              : Priority.defaultPriority,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.message,
        ),
      ),
      payload: notification.ticketId,
    );
  } on Object {
    // A background callback has no UI or reliable logger. FCM will retry where
    // appropriate; swallowing failures prevents an isolate crash loop when the
    // app intentionally has no Firebase configuration in local development.
  }
}

int _notificationId(String? messageId) {
  return (messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch) &
      0x7fffffff;
}

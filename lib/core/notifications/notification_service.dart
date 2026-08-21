import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract interface class NotificationGateway {
  Stream<String> get ticketIds;
  Future<void> initialize();
  Future<void> show({
    required String ticketId,
    required String title,
    required String message,
    bool urgent = false,
  });
  Future<void> dispose();
}

final class LocalNotificationService implements NotificationGateway {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _ticketIds = StreamController<String>.broadcast();
  String? _pendingTicketId;
  @override
  Stream<String> get ticketIds async* {
    final pending = _pendingTicketId;
    _pendingTicketId = null;
    if (pending != null) yield pending;
    yield* _ticketIds.stream;
  }

  static const _channel = AndroidNotificationChannel(
    'gestion_interna_local_v1',
    'Solicitudes de mantenimiento',
    description: 'Cambios y novedades de las solicitudes locales',
    importance: Importance.high,
  );

  @override
  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_maintenance'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload?.trim();
        if (payload != null && payload.isNotEmpty) _ticketIds.add(payload);
      },
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_channel);
    await android?.requestNotificationsPermission();
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload?.trim();
    if ((launch?.didNotificationLaunchApp ?? false) &&
        payload != null &&
        payload.isNotEmpty) {
      _pendingTicketId = payload;
    }
  }

  @override
  Future<void> show({
    required String ticketId,
    required String title,
    required String message,
    bool urgent = false,
  }) async {
    await _plugin.show(
      id: DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
      title: title,
      body: message,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          icon: 'ic_stat_maintenance',
          importance: urgent ? Importance.max : Importance.high,
          priority: urgent ? Priority.max : Priority.high,
        ),
      ),
      payload: ticketId,
    );
  }

  @override
  Future<void> dispose() => _ticketIds.close();
}

final class NoopNotificationGateway implements NotificationGateway {
  const NoopNotificationGateway();
  @override
  Stream<String> get ticketIds => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> show({
    required String ticketId,
    required String title,
    required String message,
    bool urgent = false,
  }) async {}
  @override
  Future<void> dispose() async {}
}

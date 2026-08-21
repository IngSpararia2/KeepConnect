import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'notification_background_handler.dart';
import 'notification_constants.dart';
import 'notification_message.dart';

enum NotificationServiceState { ready, disabled, unavailable }

enum NotificationPermissionState { granted, denied, notDetermined }

final class NotificationInitializationResult {
  const NotificationInitializationResult._({
    required this.state,
    required this.permission,
    this.reason,
    this.error,
  });

  const NotificationInitializationResult.ready(
    NotificationPermissionState permission,
  ) : this._(state: NotificationServiceState.ready, permission: permission);

  const NotificationInitializationResult.disabled(String reason)
    : this._(
        state: NotificationServiceState.disabled,
        permission: NotificationPermissionState.notDetermined,
        reason: reason,
      );

  const NotificationInitializationResult.unavailable(Object error)
    : this._(
        state: NotificationServiceState.unavailable,
        permission: NotificationPermissionState.notDetermined,
        error: error,
      );

  final NotificationServiceState state;
  final NotificationPermissionState permission;
  final String? reason;
  final Object? error;

  bool get isReady => state == NotificationServiceState.ready;
}

typedef NotificationErrorHandler =
    void Function(Object error, StackTrace stackTrace);

/// Owns Android FCM/local-notification behavior without depending on navigation.
///
/// Consumers navigate by listening to [ticketIds]. Create the disabled factory
/// for Firebase Emulator Suite or an app build that has no Firebase options;
/// that mode never touches a Firebase singleton.
final class NotificationService {
  NotificationService({
    required this.enabled,
    FirebaseMessaging? messaging,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    FlutterLocalNotificationsPlugin? localNotifications,
    SharedPreferencesAsync? preferences,
    Uuid? uuid,
    this.disabledReason = 'Notifications were disabled by configuration.',
    this.onError,
  }) : _messaging = messaging,
       _auth = auth,
       _functions = functions,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin(),
       _preferences = preferences ?? SharedPreferencesAsync(),
       _uuid = uuid ?? const Uuid() {
    if (enabled && (messaging == null || auth == null || functions == null)) {
      throw ArgumentError(
        'messaging, auth and functions are required when notifications are enabled.',
      );
    }
    _ticketIdController = StreamController<String>.broadcast(
      onListen: _flushPendingTicketIds,
    );
  }

  factory NotificationService.firebase({
    bool enabled = true,
    String disabledReason =
        'Notifications are disabled for the current environment.',
    NotificationErrorHandler? onError,
  }) {
    if (!enabled) {
      return NotificationService.disabled(
        reason: disabledReason,
        onError: onError,
      );
    }
    return NotificationService(
      enabled: true,
      messaging: FirebaseMessaging.instance,
      auth: FirebaseAuth.instance,
      functions: FirebaseFunctions.instanceFor(region: 'us-central1'),
      disabledReason: disabledReason,
      onError: onError,
    );
  }

  factory NotificationService.disabled({
    String reason = 'Firebase/FCM is not configured for this environment.',
    NotificationErrorHandler? onError,
  }) {
    return NotificationService(
      enabled: false,
      disabledReason: reason,
      onError: onError,
    );
  }

  final bool enabled;
  final String disabledReason;
  final NotificationErrorHandler? onError;

  final FirebaseMessaging? _messaging;
  final FirebaseAuth? _auth;
  final FirebaseFunctions? _functions;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final SharedPreferencesAsync _preferences;
  final Uuid _uuid;

  late final StreamController<String> _ticketIdController;
  final List<String> _pendingTicketIds = <String>[];
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  Future<NotificationInitializationResult>? _initialization;
  Future<_InstallationIdentity>? _installationIdentityFuture;
  NotificationPermissionState _permission =
      NotificationPermissionState.notDetermined;
  String? _registeredUid;
  String? _lastRegistrationFingerprint;
  bool _disposed = false;

  /// Ticket IDs selected from foreground, background, or terminated messages.
  ///
  /// IDs received before the first listener are buffered so initial-message
  /// navigation is not lost during application startup.
  Stream<String> get ticketIds => _ticketIdController.stream;

  NotificationPermissionState get permission => _permission;

  Future<NotificationInitializationResult> initialize({
    bool requestPermission = true,
  }) {
    if (_disposed) {
      throw StateError('NotificationService has already been disposed.');
    }
    if (!enabled) {
      return Future<NotificationInitializationResult>.value(
        NotificationInitializationResult.disabled(disabledReason),
      );
    }
    return _initialization ??= _initialize(requestPermission);
  }

  Future<NotificationInitializationResult> _initialize(
    bool shouldRequestPermission,
  ) async {
    try {
      registerNotificationBackgroundHandler();
      await _initializeLocalNotifications();
      _listenForMessagesAndAuthentication();

      _permission = shouldRequestPermission
          ? await requestNotificationPermission()
          : _mapAuthorizationStatus(
              (await _messaging!.getNotificationSettings()).authorizationStatus,
            );

      final localLaunch = await _localNotifications
          .getNotificationAppLaunchDetails();
      if (localLaunch?.didNotificationLaunchApp ?? false) {
        _emitTicketId(localLaunch?.notificationResponse?.payload);
      }

      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        _emitTicketFromMessage(initialMessage);
      }

      _runBestEffort(() => _registerCurrentToken(_auth!.currentUser));
      return NotificationInitializationResult.ready(_permission);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
      return NotificationInitializationResult.unavailable(error);
    }
  }

  Future<void> _initializeLocalNotifications() async {
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(
          NotificationConstants.notificationIcon,
        ),
      ),
      onDidReceiveNotificationResponse: _onLocalNotificationSelected,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      NotificationConstants.normalChannel,
    );
    await androidPlugin?.createNotificationChannel(
      NotificationConstants.urgentChannel,
    );
  }

  void _listenForMessagesAndAuthentication() {
    _subscriptions
      ..add(
        FirebaseMessaging.onMessage.listen(
          _showForegroundNotification,
          onError: _handleStreamError,
        ),
      )
      ..add(
        FirebaseMessaging.onMessageOpenedApp.listen(
          _emitTicketFromMessage,
          onError: _handleStreamError,
        ),
      )
      ..add(
        _messaging!.onTokenRefresh.listen(
          _onTokenRefresh,
          onError: _handleStreamError,
        ),
      )
      ..add(
        _auth!.authStateChanges().listen(
          _onAuthenticationChanged,
          onError: _handleStreamError,
        ),
      );
  }

  Future<NotificationPermissionState> requestNotificationPermission() async {
    if (!enabled) {
      return NotificationPermissionState.notDetermined;
    }
    final settings = await _messaging!.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    _permission = _mapAuthorizationStatus(settings.authorizationStatus);

    final user = _auth!.currentUser;
    if (user != null) {
      _runBestEffort(() => _registerCurrentToken(user));
    }
    return _permission;
  }

  NotificationPermissionState _mapAuthorizationStatus(
    AuthorizationStatus status,
  ) {
    return switch (status) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => NotificationPermissionState.granted,
      AuthorizationStatus.denied => NotificationPermissionState.denied,
      AuthorizationStatus.notDetermined =>
        NotificationPermissionState.notDetermined,
    };
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    try {
      final notification = NotificationMessage.fromRemoteMessage(message);
      final channel = notification.isUrgent
          ? NotificationConstants.urgentChannel
          : NotificationConstants.normalChannel;
      await _localNotifications.show(
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
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  void _onLocalNotificationSelected(NotificationResponse response) {
    _emitTicketId(response.payload);
  }

  void _emitTicketFromMessage(RemoteMessage message) {
    _emitTicketId(NotificationMessage.fromRemoteMessage(message).ticketId);
  }

  void _emitTicketId(String? value) {
    final ticketId = value?.trim();
    if (ticketId == null || ticketId.isEmpty || _disposed) {
      return;
    }
    if (_ticketIdController.hasListener) {
      _ticketIdController.add(ticketId);
    } else {
      _pendingTicketIds.add(ticketId);
    }
  }

  void _flushPendingTicketIds() {
    if (_pendingTicketIds.isEmpty || _disposed) {
      return;
    }
    final pending = List<String>.of(_pendingTicketIds);
    _pendingTicketIds.clear();
    scheduleMicrotask(() {
      if (_disposed) {
        return;
      }
      for (final ticketId in pending) {
        _ticketIdController.add(ticketId);
      }
    });
  }

  void _onAuthenticationChanged(User? user) {
    if (user == null) {
      _registeredUid = null;
      _lastRegistrationFingerprint = null;
      return;
    }
    _runBestEffort(() => _registerCurrentToken(user));
  }

  void _onTokenRefresh(String token) {
    final user = _auth!.currentUser;
    if (user == null) {
      return;
    }
    _runBestEffort(() => _writeDeviceRegistration(uid: user.uid, token: token));
  }

  void _runBestEffort(Future<void> Function() operation) {
    unawaited(_retryBackgroundOperation(operation));
  }

  Future<void> _retryBackgroundOperation(
    Future<void> Function() operation,
  ) async {
    for (var attempt = 0; attempt < 3 && !_disposed; attempt += 1) {
      try {
        await operation().timeout(const Duration(seconds: 15));
        return;
      } on Object catch (error, stackTrace) {
        _report(error, stackTrace);
        if (attempt < 2 && !_disposed) {
          await Future<void>.delayed(Duration(seconds: attempt == 0 ? 2 : 8));
        }
      }
    }
  }

  Future<void> _registerCurrentToken(User? user) async {
    if (user == null) {
      return;
    }
    final token = await _messaging!.getToken();
    if (token == null || token.isEmpty) {
      return;
    }
    await _writeDeviceRegistration(uid: user.uid, token: token);
  }

  Future<void> _writeDeviceRegistration({
    required String uid,
    required String token,
  }) async {
    final fingerprint = '$uid|$token|${_permission.name}';
    if (_lastRegistrationFingerprint == fingerprint) {
      return;
    }
    _lastRegistrationFingerprint = fingerprint;

    final installation = await _installationIdentity();
    try {
      await _functions!.httpsCallable('registerDevice').call(<String, Object?>{
        'installationId': installation.id,
        'token': token,
        'platform': 'android',
        'applicationId': 'com.samuelpararia.gestioninterna',
        'notificationsEnabled':
            _permission != NotificationPermissionState.denied,
        'permissionStatus': _permission.name,
        'installationCreatedAtMillis':
            installation.createdAt.millisecondsSinceEpoch,
      });
      _registeredUid = uid;
    } on Object {
      if (_lastRegistrationFingerprint == fingerprint) {
        _lastRegistrationFingerprint = null;
      }
      rethrow;
    }
  }

  /// Deletes this installation's device document while the user is still
  /// authenticated. The logout flow must await this method before `signOut()`;
  /// after sign-out, normal Firestore security rules can no longer authorize
  /// deletion under `users/{uid}`.
  Future<void> prepareForLogout() async {
    if (!enabled) {
      return;
    }
    final uid = _auth!.currentUser?.uid ?? _registeredUid;
    if (uid == null) {
      return;
    }
    final installationId = await _installationId(createIfMissing: false);
    try {
      if (installationId != null) {
        await _functions!
            .httpsCallable('unregisterDevice')
            .call(<String, Object?>{'installationId': installationId})
            .timeout(const Duration(seconds: 5));
      }
    } on Object catch (error, stackTrace) {
      // Logout must remain possible if Firestore is offline or a profile was
      // just disabled. Invalid/stale tokens are also removed by the backend.
      _report(error, stackTrace);
    } finally {
      _registeredUid = null;
      _lastRegistrationFingerprint = null;
    }
  }

  Future<_InstallationIdentity> _installationIdentity() {
    return _installationIdentityFuture ??= _loadInstallationIdentity();
  }

  Future<_InstallationIdentity> _loadInstallationIdentity() async {
    final id = (await _installationId(createIfMissing: true))!;
    final storedDate = await _preferences.getString(
      NotificationConstants.installationCreatedAtPreference,
    );
    final parsedDate = storedDate == null
        ? null
        : DateTime.tryParse(storedDate);
    if (parsedDate != null) {
      return _InstallationIdentity(id, parsedDate.toUtc());
    }

    final createdAt = DateTime.now().toUtc();
    await _preferences.setString(
      NotificationConstants.installationCreatedAtPreference,
      createdAt.toIso8601String(),
    );
    return _InstallationIdentity(id, createdAt);
  }

  Future<String?> _installationId({required bool createIfMissing}) async {
    final existing = await _preferences.getString(
      NotificationConstants.installationIdPreference,
    );
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }
    if (!createIfMissing) {
      return null;
    }

    final created = _uuid.v4();
    await _preferences.setString(
      NotificationConstants.installationIdPreference,
      created,
    );
    return created;
  }

  int _notificationId(String? messageId) {
    return (messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch) &
        0x7fffffff;
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    _report(error, stackTrace);
  }

  void _report(Object error, StackTrace stackTrace) {
    final handler = onError;
    if (handler != null) {
      handler(error, stackTrace);
    } else if (kDebugMode) {
      debugPrint('NotificationService: $error');
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _ticketIdController.close();
  }
}

final class _InstallationIdentity {
  const _InstallationIdentity(this.id, this.createdAt);

  final String id;
  final DateTime createdAt;
}

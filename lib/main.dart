import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_10y.dart' as timezone_data;

import 'app/app.dart';
import 'app/app_providers.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/firebase/firebase_providers.dart';
import 'core/notifications/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  timezone_data.initializeTimeZones();
  await initializeDateFormatting('es_CO');
  Intl.defaultLocale = 'es_CO';

  final firebase = await FirebaseBootstrap.initialize();
  final notifications = firebase.isReady && !firebase.usesEmulators
      ? NotificationService.firebase(
          onError: (error, stackTrace) {
            if (kDebugMode) debugPrint('FCM: $error');
          },
        )
      : NotificationService.disabled(
          reason: firebase.usesEmulators
              ? 'FCM no forma parte de Firebase Emulator Suite.'
              : 'Firebase no está configurado.',
        );

  registerNotificationBackgroundHandler(
    enabled: firebase.isReady && !firebase.usesEmulators,
  );
  await notifications.initialize(requestPermission: false);

  runApp(
    ProviderScope(
      overrides: [
        firebaseBootstrapProvider.overrideWithValue(firebase),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: const GestionInternaApp(),
    ),
  );
}

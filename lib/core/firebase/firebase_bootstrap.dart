import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../config/app_config.dart';
import '../../firebase_options.dart';

enum FirebaseBootstrapState { ready, emulator, notConfigured, failed }

class FirebaseBootstrapResult {
  const FirebaseBootstrapResult({
    required this.state,
    this.message,
    this.error,
  });

  final FirebaseBootstrapState state;
  final String? message;
  final Object? error;

  bool get isReady =>
      state == FirebaseBootstrapState.ready ||
      state == FirebaseBootstrapState.emulator;
  bool get usesEmulators => state == FirebaseBootstrapState.emulator;
}

abstract final class FirebaseBootstrap {
  static Future<FirebaseBootstrapResult> initialize() async {
    if (AppConfig.useFirebaseEmulators) {
      try {
        await Firebase.initializeApp(demoProjectId: AppConfig.demoProjectId);
        await _connectToEmulators();
        return const FirebaseBootstrapResult(
          state: FirebaseBootstrapState.emulator,
          message: 'Conectado a Firebase Emulator Suite.',
        );
      } catch (error) {
        return FirebaseBootstrapResult(
          state: FirebaseBootstrapState.failed,
          message: 'No fue posible conectar con Firebase Emulator Suite.',
          error: error,
        );
      }
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return const FirebaseBootstrapResult(state: FirebaseBootstrapState.ready);
    } on UnsupportedError catch (error) {
      return FirebaseBootstrapResult(
        state: FirebaseBootstrapState.notConfigured,
        message: error.message?.toString(),
        error: error,
      );
    } catch (error) {
      return FirebaseBootstrapResult(
        state: FirebaseBootstrapState.failed,
        message: 'Firebase no pudo iniciar. Revise la configuración Android.',
        error: error,
      );
    }
  }

  static Future<void> _connectToEmulators() async {
    final host = AppConfig.emulatorHost;
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseFunctions.instanceFor(
      region: AppConfig.functionsRegion,
    ).useFunctionsEmulator(host, 5001);
    await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  }
}

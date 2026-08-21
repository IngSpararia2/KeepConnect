import 'package:firebase_core/firebase_core.dart';

/// Placeholder intentionally containing no Firebase identifiers.
///
/// Run `flutterfire configure --platforms=android` as documented in
/// `docs/FIREBASE_SETUP.md`. FlutterFire replaces this file with the generated
/// configuration. Keeping the same public API means no application code needs
/// to be edited afterwards.
abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw UnsupportedError(
    'Firebase aún no está configurado. Ejecute flutterfire configure.',
  );
}

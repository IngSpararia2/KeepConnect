import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppException implements Exception {
  const AppException(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() => message;

  static AppException from(Object error) {
    if (error is AppException) return error;
    if (error is FirebaseAuthException) {
      return AppException(
        switch (error.code) {
          'invalid-email' => 'El correo electrónico no es válido.',
          'invalid-credential' ||
          'wrong-password' ||
          'user-not-found' => 'Correo o contraseña incorrectos.',
          'user-disabled' => 'Esta cuenta fue desactivada.',
          'too-many-requests' =>
            'Demasiados intentos. Espere unos minutos e inténtelo de nuevo.',
          'network-request-failed' =>
            'No hay conexión. Compruebe Internet e inténtelo de nuevo.',
          _ => 'No fue posible autenticar. Inténtelo nuevamente.',
        },
        code: error.code,
        cause: error,
      );
    }
    if (error is FirebaseFunctionsException) {
      return AppException(
        error.message ?? 'La operación no pudo completarse.',
        code: error.code,
        cause: error,
      );
    }
    return AppException(
      'Ocurrió un error inesperado. Inténtelo nuevamente.',
      cause: error,
    );
  }
}

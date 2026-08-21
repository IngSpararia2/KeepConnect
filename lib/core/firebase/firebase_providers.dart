import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import 'firebase_bootstrap.dart';

final firebaseBootstrapProvider = Provider<FirebaseBootstrapResult>(
  (ref) => throw StateError('firebaseBootstrapProvider debe sobrescribirse.'),
);

final firebaseAuthProvider = Provider<FirebaseAuth?>((ref) {
  return ref.watch(firebaseBootstrapProvider).isReady
      ? FirebaseAuth.instance
      : null;
});

final firestoreProvider = Provider<FirebaseFirestore?>((ref) {
  return ref.watch(firebaseBootstrapProvider).isReady
      ? FirebaseFirestore.instance
      : null;
});

final functionsProvider = Provider<FirebaseFunctions?>((ref) {
  return ref.watch(firebaseBootstrapProvider).isReady
      ? FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion)
      : null;
});

final storageProvider = Provider<FirebaseStorage?>((ref) {
  return ref.watch(firebaseBootstrapProvider).isReady
      ? FirebaseStorage.instance
      : null;
});

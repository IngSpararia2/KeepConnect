import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../data/auth_repository.dart';
import '../data/user_repository.dart';
import '../domain/app_user.dart';

final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth == null ? null : AuthRepository(auth);
});

final userRepositoryProvider = Provider<UserRepository?>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return firestore == null ? null : UserRepository(firestore);
});

final authStateProvider = StreamProvider<User?>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository?.authStateChanges() ?? Stream.value(null);
});

final currentUserProfileProvider = StreamProvider<AppUser?>((ref) {
  final authState = ref.watch(authStateProvider);
  final uid = authState.value?.uid;
  final repository = ref.watch(userRepositoryProvider);
  if (uid == null || repository == null) return Stream.value(null);
  return repository.watchUser(uid);
});

final maintenanceUsersProvider = StreamProvider<List<AppUser>>((ref) {
  final repository = ref.watch(userRepositoryProvider);
  return repository?.watchMaintenanceUsers() ?? Stream.value(const []);
});

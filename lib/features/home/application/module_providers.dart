import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../data/module_repository.dart';
import '../domain/app_module.dart';

final moduleRepositoryProvider = Provider<ModuleRepository?>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return firestore == null ? null : ModuleRepository(firestore);
});

final activeModulesProvider = StreamProvider<List<AppModule>>((ref) {
  return ref.watch(moduleRepositoryProvider)?.watchActiveModules() ??
      Stream.value(const [AppModule.maintenanceFallback]);
});

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/app_module.dart';

class ModuleRepository {
  const ModuleRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<AppModule>> watchActiveModules() {
    return _firestore
        .collection('modules')
        .where('active', isEqualTo: true)
        .orderBy('sortOrder')
        .limit(50)
        .snapshots()
        .map((snapshot) {
          final modules = snapshot.docs
              .map(AppModule.fromFirestore)
              .toList(growable: false);
          return modules.isEmpty ? [AppModule.maintenanceFallback] : modules;
        });
  }
}

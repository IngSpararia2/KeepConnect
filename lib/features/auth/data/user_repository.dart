import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/app_user.dart';

class UserRepository {
  const UserRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<AppUser?> watchUser(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      return data == null ? null : AppUser.fromMap(snapshot.id, data);
    });
  }

  Stream<List<AppUser>> watchMaintenanceUsers() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: UserRole.maintenance.name)
        .where('departmentId', isEqualTo: 'maintenance')
        .where('active', isEqualTo: true)
        .orderBy('name')
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppUser.fromMap(doc.id, doc.data()))
              .toList(growable: false),
        );
  }
}

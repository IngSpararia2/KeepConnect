import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_value.dart';
import '../../auth/domain/app_user.dart';

class TicketComment {
  const TicketComment({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.authorRole,
    required this.text,
    this.createdAt,
  });

  final String id;
  final String authorUid;
  final String authorName;
  final UserRole authorRole;
  final String text;
  final DateTime? createdAt;

  factory TicketComment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final map = document.data() ?? const <String, dynamic>{};
    return TicketComment(
      id: document.id,
      authorUid: (map['authorUid'] as String?) ?? '',
      authorName: (map['authorName'] as String?) ?? 'Usuario',
      authorRole: UserRole.fromValue(map['authorRole']),
      text: (map['text'] as String?) ?? '',
      createdAt: dateTimeFromFirestore(map['createdAt']),
    );
  }
}

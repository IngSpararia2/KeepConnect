import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_value.dart';
import 'ticket_enums.dart';

class TicketEvent {
  const TicketEvent({
    required this.id,
    required this.type,
    required this.actorUid,
    required this.actorName,
    required this.message,
    required this.previousValue,
    required this.newValue,
    required this.metadata,
    this.createdAt,
  });

  final String id;
  final TicketEventType type;
  final String actorUid;
  final String actorName;
  final String message;
  final Object? previousValue;
  final Object? newValue;
  final Map<String, Object?> metadata;
  final DateTime? createdAt;

  factory TicketEvent.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final map = document.data() ?? const <String, dynamic>{};
    return TicketEvent(
      id: document.id,
      type: TicketEventType.fromValue(map['type']),
      actorUid: (map['actorUid'] as String?) ?? '',
      actorName: (map['actorName'] as String?) ?? 'Sistema',
      message: (map['message'] as String?) ?? '',
      previousValue: map['previousValue'],
      newValue: map['newValue'],
      metadata: objectMapFromFirestore(map['metadata']),
      createdAt: dateTimeFromFirestore(map['createdAt']),
    );
  }
}

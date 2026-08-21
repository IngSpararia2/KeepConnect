import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_value.dart';

class TicketAttachment {
  const TicketAttachment({
    required this.id,
    required this.storagePath,
    required this.fileName,
    required this.contentType,
    required this.bytes,
    required this.uploaderUid,
    required this.uploaderName,
    this.createdAt,
  });

  final String id;
  final String storagePath;
  final String fileName;
  final String contentType;
  final int bytes;
  final String uploaderUid;
  final String uploaderName;
  final DateTime? createdAt;

  factory TicketAttachment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final map = document.data() ?? const <String, dynamic>{};
    return TicketAttachment(
      id: document.id,
      storagePath: (map['storagePath'] as String?) ?? '',
      fileName: (map['fileName'] as String?) ?? 'evidencia.jpg',
      contentType: (map['contentType'] as String?) ?? 'image/jpeg',
      bytes: ((map['sizeBytes'] ?? map['bytes']) as num?)?.toInt() ?? 0,
      uploaderUid: (map['uploaderUid'] as String?) ?? '',
      uploaderName: (map['uploaderName'] as String?) ?? 'Usuario',
      createdAt: dateTimeFromFirestore(map['createdAt']),
    );
  }
}

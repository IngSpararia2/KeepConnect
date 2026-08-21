import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../config/app_config.dart';
import '../../../core/errors/app_exception.dart';
import 'maintenance_repository.dart';

class AttachmentService {
  AttachmentService(this._storage, this._repository);

  final FirebaseStorage _storage;
  final MaintenanceRepository _repository;
  final Uuid _uuid = const Uuid();

  Future<void> uploadEvidence({
    required String ticketId,
    required String uploaderUid,
    required XFile image,
  }) async {
    final file = File(image.path);
    final bytes = await file.length();
    if (bytes <= 0) {
      throw const AppException('La imagen seleccionada está vacía.');
    }
    if (bytes > AppConfig.maxPhotoBytes) {
      throw const AppException(
        'La imagen supera el límite de 5 MB. Seleccione una imagen más pequeña.',
      );
    }

    final attachmentId = _uuid.v4();
    final safeName = _safeFileName(image.name);
    final storagePath = 'tickets/$ticketId/$attachmentId/$safeName';
    final reference = _storage.ref(storagePath);
    final contentType = image.mimeType ?? _contentTypeFor(safeName);

    try {
      await reference.putFile(
        file,
        SettableMetadata(
          contentType: contentType,
          customMetadata: {
            'ticketId': ticketId,
            'attachmentId': attachmentId,
            'uploaderUid': uploaderUid,
          },
        ),
      );
      await _repository.registerAttachment(
        ticketId: ticketId,
        attachmentId: attachmentId,
        storagePath: storagePath,
        fileName: safeName,
        contentType: contentType,
        bytes: bytes,
      );
    } catch (error) {
      try {
        await reference.delete();
      } catch (_) {
        // El documento no se registró. La limpieza de huérfanos también se
        // contempla en la guía operativa si la red cae durante este punto.
      }
      throw AppException.from(error);
    }
  }

  Future<String> downloadUrl(String storagePath) {
    return _storage.ref(storagePath).getDownloadURL();
  }

  static String _safeFileName(String value) {
    var normalized = value
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll('..', '__');
    if (normalized.isEmpty) normalized = 'evidencia.jpg';
    if (!RegExp(r'^[A-Za-z0-9]').hasMatch(normalized)) {
      normalized = 'evidencia_$normalized';
    }
    return normalized.length <= 120 ? normalized : normalized.substring(0, 120);
  }

  static String _contentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }
}

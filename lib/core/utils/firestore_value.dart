import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? dateTimeFromFirestore(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

List<String> stringListFromFirestore(Object? value) {
  if (value is! Iterable) return const [];
  return value.whereType<String>().toList(growable: false);
}

Map<String, Object?> objectMapFromFirestore(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

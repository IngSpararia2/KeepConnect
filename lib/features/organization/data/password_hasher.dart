import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final class PasswordHasher {
  const PasswordHasher({this.iterations = 120000});

  final int iterations;

  String hash(String password) {
    _validate(password);
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final derived = _pbkdf2(utf8.encode(password), salt, iterations, 32);
    return 'pbkdf2-sha256\$$iterations\$${base64UrlEncode(salt)}\$${base64UrlEncode(derived)}';
  }

  bool verify(String password, String encoded) {
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null || rounds < 10000) return false;
    try {
      final salt = base64Url.decode(parts[2]);
      final expected = base64Url.decode(parts[3]);
      final actual = _pbkdf2(
        utf8.encode(password),
        salt,
        rounds,
        expected.length,
      );
      var difference = actual.length ^ expected.length;
      for (var i = 0; i < actual.length && i < expected.length; i++) {
        difference |= actual[i] ^ expected[i];
      }
      return difference == 0;
    } on FormatException {
      return false;
    }
  }

  void _validate(String password) {
    if (password.length < 10) {
      throw ArgumentError('La contraseña debe tener al menos 10 caracteres.');
    }
  }

  Uint8List _pbkdf2(
    List<int> password,
    List<int> salt,
    int rounds,
    int length,
  ) {
    final hmac = Hmac(sha256, password);
    final output = BytesBuilder(copy: false);
    for (var block = 1; output.length < length; block++) {
      final counter = ByteData(4)..setUint32(0, block, Endian.big);
      var value = hmac.convert([
        ...salt,
        ...counter.buffer.asUint8List(),
      ]).bytes;
      final accumulator = Uint8List.fromList(value);
      for (var round = 1; round < rounds; round++) {
        value = hmac.convert(value).bytes;
        for (var i = 0; i < accumulator.length; i++) {
          accumulator[i] ^= value[i];
        }
      }
      output.add(accumulator);
    }
    return Uint8List.sublistView(output.toBytes(), 0, length);
  }
}

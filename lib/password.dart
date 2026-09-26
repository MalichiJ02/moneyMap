import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalPassword {
  static const _key = 'moneymap_local_password_v1';
  final _storage = const FlutterSecureStorage();
  final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 210000, bits: 256);

  Future<bool> exists() async => (await _storage.read(key: _key)) != null;

  Future<String> _hash(String password, List<int> salt) async {
    final key = await _kdf.deriveKeyFromPassword(password: password, nonce: salt);
    return base64Encode(await key.extractBytes());
  }

  Future<void> create(String password) async {
    if (await exists()) throw StateError('A password has already been set.');
    if (password.length < 8) throw ArgumentError('Use at least 8 characters.');
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final record = jsonEncode({'salt': base64Encode(salt), 'hash': await _hash(password, salt)});
    await _storage.write(key: _key, value: record);
  }

  Future<bool> verify(String password) async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return false;
    final record = jsonDecode(raw) as Map<String, dynamic>;
    final expected = base64Decode(record['hash'] as String);
    final actual = base64Decode(await _hash(password, base64Decode(record['salt'] as String)));
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var index = 0; index < actual.length; index++) {
      difference |= actual[index] ^ expected[index];
    }
    return difference == 0;
  }

  Future<bool> change(String oldPassword, String newPassword) async {
    if (!await verify(oldPassword)) return false;
    if (newPassword.length < 8) throw ArgumentError('Use at least 8 characters.');
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    await _storage.write(key: _key, value: jsonEncode({
      'salt': base64Encode(salt), 'hash': await _hash(newPassword, salt),
    }));
    return true;
  }
}


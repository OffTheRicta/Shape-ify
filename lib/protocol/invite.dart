import 'dart:math';

/// A human-typable local session identifier. It is not a password or a network address.
class InviteCode {
  static const _alphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
  static final _legacyUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static String create() {
    final rng = Random.secure();
    final chars = List.generate(12,
        (_) => _alphabet[rng.nextInt(_alphabet.length)]).join();
    return 'RH-${chars.substring(0, 4)}-${chars.substring(4, 8)}-${chars.substring(8)}';
  }

  static String? parse(String input) {
    final trimmed = input.trim();
    if (_legacyUuid.hasMatch(trimmed)) return trimmed.toLowerCase();
    final raw = trimmed.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (raw.startsWith('RH')) {
      final chars = raw.substring(2);
      if (chars.length == 12 && chars.split('').every(_alphabet.contains)) {
        return 'RH-${chars.substring(0, 4)}-${chars.substring(4, 8)}-${chars.substring(8)}';
      }
    }
    return null;
  }

}

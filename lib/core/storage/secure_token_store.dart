import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the Magento customer token in platform secure storage only — never in
/// shared_preferences.
class SecureTokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const String _tokenKey = 'customer_token';

  Future<String?> read() async {
    final value = await _storage.read(key: _tokenKey);
    // Treat an empty value as "no token" so a neutralised/leftover item can't
    // produce a bare `Bearer ` header.
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Persist the token, removing any prior entry (across both synchronizable
  /// states) first. Guarantees a clean add even if a stale Keychain item exists,
  /// avoiding the `errSecDuplicateItem` write failure that surfaced as "sign-in
  /// not saving token".
  Future<void> write(String token) async {
    await clear();
    await _storage.write(key: _tokenKey, value: token);
  }

  /// Removes the token across **both synchronizable states** with accessibility
  /// unconstrained.
  ///
  /// flutter_secure_storage's `read()` is lenient — it queries the local item
  /// first, then falls back to the **iCloud-synchronizable** one — so it finds a
  /// token that ended up in iCloud Keychain. But its default `delete()` /
  /// `deleteAll()` query filters by `synchronizable = false` (and a fixed
  /// accessibility), so a synchronizable token **survives deletion** and keeps
  /// being sent on every request → Magento "Consumer key has expired", with
  /// `read()` still reporting it present after a "delete". Deleting with
  /// `synchronizable` both false and true (accessibility null → unconstrained)
  /// removes it for good.
  Future<void> clear() async {
    for (final synchronizable in const <bool>[false, true]) {
      await _storage.delete(
        key: _tokenKey,
        iOptions: IOSOptions(
          accessibility: null,
          synchronizable: synchronizable,
        ),
      );
    }
  }
}

final secureTokenStoreProvider = Provider<SecureTokenStore>(
  (ref) => SecureTokenStore(),
);

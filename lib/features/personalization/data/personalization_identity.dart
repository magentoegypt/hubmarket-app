import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_cache.dart';

/// Persisted keys of the personalisation settings.
const String kPersonalizationTokenKey = 'personalization_user_token';
const String kPersonalizationEnabledKey = 'personalization_enabled';

/// What Algolia (and `hmPickedForYou`) accepts as a user token: letters,
/// digits and `_ = + / . -`, 1 to 129 characters.
final RegExp _tokenShape = RegExp(r'^[A-Za-z0-9_=+/.-]{1,129}$');

bool isValidPersonalizationToken(String token) => _tokenShape.hasMatch(token);

const String _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// A new anonymous token: `hm-` and 32 random characters. Nothing in it says
/// who the shopper is; it only names this install's Algolia profile.
String newPersonalizationToken([Random? random]) {
  final rng = random ?? Random.secure();
  return 'hm-${List.generate(32, (_) => _alphabet[rng.nextInt(_alphabet.length)]).join()}';
}

/// This install's Algolia user token: made on first use and kept, so the
/// events the app sends and the picks it asks for are the same shopper.
///
/// Algolia Personalization keys a profile on this token alone (an
/// authenticated token only links events in Analytics), so it stays the same
/// across a sign-in and a language switch: the profile follows the install.
final personalizationTokenProvider = Provider<String>((ref) {
  final cache = ref.read(localCacheProvider);
  final saved = cache.readString(kPersonalizationTokenKey);
  if (saved != null && isValidPersonalizationToken(saved)) return saved;
  final token = newPersonalizationToken();
  unawaited(cache.writeString(kPersonalizationTokenKey, token));
  return token;
});

/// Whether the app may use the shopper's activity to personalise (default on):
/// the Settings switch. Off means no Insights events leave the phone and Picked
/// For You stays the top-rated list.
class PersonalizationEnabled extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(localCacheProvider).readString(kPersonalizationEnabledKey) !=
      'false';

  Future<void> set(bool enabled) async {
    state = enabled;
    await ref
        .read(localCacheProvider)
        .writeString(kPersonalizationEnabledKey, '$enabled');
  }
}

final personalizationEnabledProvider =
    NotifierProvider<PersonalizationEnabled, bool>(PersonalizationEnabled.new);

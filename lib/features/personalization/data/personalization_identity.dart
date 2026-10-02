import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_cache.dart';

/// Persisted keys of the personalisation settings.
const String kPersonalizationTokenKey = 'personalization_user_token';

/// The shopper's answer: `true` (allowed) or `false` (declined); absent while
/// the app has not asked. The key is the one the first builds used for the
/// Settings switch, so a shopper who had already switched it off or on keeps
/// that answer.
const String kPersonalizationEnabledKey = 'personalization_enabled';

/// What the shopper answered when the app asked whether Picked For You may use
/// their activity.
enum PersonalizationConsent {
  /// Not asked yet, or asked and left open: nothing is used.
  undecided,

  /// "Allow" on the prompt, or the Settings switch turned on.
  allowed,

  /// "Not now" on the prompt, or the Settings switch turned off.
  declined,
}

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

/// Whether the shopper let the app use their activity to personalise: asked
/// once by the sheet on the Home and changed any time with the Settings
/// switch. Only [PersonalizationConsent.allowed] lets anything
/// happen: no Insights event leaves the phone, no token exists and
/// `hmPickedForYou` is not asked until then, and Picked For You stays the
/// top-rated list.
///
/// The website works the same way: without the cookie consent it makes no
/// Algolia token and nothing personal.
class PersonalizationConsentController extends Notifier<PersonalizationConsent> {
  @override
  PersonalizationConsent build() {
    final cache = ref.read(localCacheProvider);
    final consent = switch (cache.readString(kPersonalizationEnabledKey)) {
      'true' => PersonalizationConsent.allowed,
      'false' => PersonalizationConsent.declined,
      _ => PersonalizationConsent.undecided,
    };
    // A token the first builds made before the app asked (they personalised by
    // default) goes too: no consent, no token.
    if (consent != PersonalizationConsent.allowed &&
        cache.readString(kPersonalizationTokenKey) != null) {
      unawaited(cache.deleteKey(kPersonalizationTokenKey));
    }
    return consent;
  }

  /// "Allow": from now on the app may send events and ask for the shopper's
  /// own picks.
  Future<void> allow() => _answer(PersonalizationConsent.allowed);

  /// "Not now", or the switch turned off: events stop and the token is
  /// deleted, so a later "Allow" starts a new anonymous profile.
  Future<void> decline() => _answer(PersonalizationConsent.declined);

  /// The Settings switch.
  Future<void> set(bool allowed) => allowed ? allow() : decline();

  Future<void> _answer(PersonalizationConsent answer) async {
    final cache = ref.read(localCacheProvider);
    state = answer;
    final allowed = answer == PersonalizationConsent.allowed;
    await cache.writeString(kPersonalizationEnabledKey, '$allowed');
    if (!allowed) await cache.deleteKey(kPersonalizationTokenKey);
  }
}

final personalizationConsentProvider =
    NotifierProvider<PersonalizationConsentController, PersonalizationConsent>(
      PersonalizationConsentController.new,
    );

/// Whether the app may use the shopper's activity: only after "Allow".
final personalizationEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(personalizationConsentProvider) ==
      PersonalizationConsent.allowed,
);

/// This install's Algolia user token, made on first use after the shopper
/// allowed personalisation and kept, so the events the app sends and the picks
/// it asks for are the same shopper. Null while the shopper has not allowed it:
/// no consent, no token.
///
/// Algolia Personalization keys a profile on this token alone (an
/// authenticated token only links events in Analytics), so it stays the same
/// across a sign-in and a language switch: the profile follows the install.
/// Turning personalisation off deletes it ([PersonalizationConsentController]);
/// turning it on again makes a new one.
final personalizationTokenProvider = Provider<String?>((ref) {
  if (!ref.watch(personalizationEnabledProvider)) return null;
  final cache = ref.read(localCacheProvider);
  final saved = cache.readString(kPersonalizationTokenKey);
  if (saved != null && isValidPersonalizationToken(saved)) return saved;
  final token = newPersonalizationToken();
  unawaited(cache.writeString(kPersonalizationTokenKey, token));
  return token;
});

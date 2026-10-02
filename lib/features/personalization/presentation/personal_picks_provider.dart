import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../data/personalization_identity.dart';
import '../data/picked_for_you_repository.dart';
import '../domain/personal_picks.dart';

/// The shopper's own Picked For You, asked for once the Home has drawn its
/// cached top-rated section: the picks when Algolia ranked them from this
/// shopper's profile ([PersonalPicks.personalized]), otherwise null.
///
/// Null while it loads, with personalisation off in Settings, for a shopper
/// with no profile yet (the server answers the same top-rated list the Home
/// shows, which the app never labels as personal), and on any failure: the
/// Home's own section is always the fallback.
///
/// Asked again after a store switch (the index is per language) and by the
/// Home's pull to refresh (invalidate it there).
final personalPicksProvider = FutureProvider<PersonalPicks?>((ref) async {
  if (!ref.watch(personalizationEnabledProvider)) return null;
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final token = ref.watch(personalizationTokenProvider);
  try {
    final picks = await ref.watch(pickedForYouRepositoryProvider).fetch(token);
    return picks.personalized && picks.items.isNotEmpty ? picks : null;
  } on Object {
    return null;
  }
});

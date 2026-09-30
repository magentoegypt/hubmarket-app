import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hubapp/hubapp.dart';
import '../../../core/store/store_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/hm_home_repository.dart';
import '../domain/hm_home.dart';

/// Who the Home is built for: a signed-in customer or a guest (marketing
/// targeting only).
final homeAudienceProvider = Provider<HmAudience>(
  (ref) => ref.watch(authControllerProvider.select((s) => s.isAuthenticated))
      ? HmAudience.customer
      : HmAudience.guest,
);

/// The admin-laid-out Home (`hmAppHome`) for the active store view and
/// audience; null while the Hub Market App API isn't available, so the Home
/// stays Build 1. Kept for the session (the GET is cached server-side too);
/// pull-to-refresh, a store switch or a sign-in/out reads it again.
final hmHomeProvider = FutureProvider<HmHome?>((ref) async {
  if (ref.watch(hubAppStatusProvider) != HubAppStatus.available) return null;
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final audience = ref.watch(homeAudienceProvider);
  return ref.watch(hmHomeRepositoryProvider).fetchHome(audience);
});

/// The hero slides of the guest Home — the Welcome carousel (02). Empty
/// while the Hub Market App API isn't available or has no slides, and on any
/// failure: Welcome then keeps its logo panel.
final welcomeSlidesProvider = FutureProvider.autoDispose<List<HmHeroBanner>>((
  ref,
) async {
  try {
    final home = await ref.watch(hmHomeProvider.future);
    if (home == null) return const <HmHeroBanner>[];
    final now = DateTime.now();
    for (final section in home.visibleSections(now)) {
      if (section.type != HmSectionType.heroBanners) continue;
      final slides = [
        for (final slide in section.slides)
          if ((slide.imageUrl ?? '').isNotEmpty) slide,
      ];
      if (slides.isNotEmpty) return slides;
    }
  } on Object {
    // Welcome never fails over a banner.
  }
  return const <HmHeroBanner>[];
});

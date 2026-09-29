import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../data/account_repository.dart';

/// The signed-in customer's newsletter opt-in — Magento's `is_subscribed`,
/// the same flag the website's "Newsletter Subscriptions" page edits, so the
/// app and the site always agree. False for a guest (nothing to read).
///
/// It replaced a switch that only remembered the choice on the device.
class NewsletterController extends AutoDisposeAsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final signedIn = ref.watch(
      authControllerProvider.select((s) => s.isAuthenticated),
    );
    if (!signedIn) return false;
    return ref.read(accountRepositoryProvider).fetchNewsletterSubscription();
  }

  /// Saves the opt-in and returns what the store saved: `false` after a
  /// subscribe means the store wants the customer to confirm by e-mail first.
  /// On failure the previous value is restored and the error rethrown.
  Future<bool> setSubscribed(bool subscribed) async {
    final previous = state.valueOrNull;
    state = AsyncData(subscribed);
    try {
      final saved = await ref
          .read(accountRepositoryProvider)
          .setNewsletterSubscription(subscribed);
      state = AsyncData(saved);
      return saved;
    } catch (_) {
      state = AsyncData(previous ?? !subscribed);
      rethrow;
    }
  }
}

final newsletterProvider =
    AsyncNotifierProvider.autoDispose<NewsletterController, bool>(
      NewsletterController.new,
    );

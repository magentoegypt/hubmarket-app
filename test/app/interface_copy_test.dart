import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

/// QA02: marketing claims come from Magento; the wording the app ships is
/// interface only. These strings once promised deals, store counts, curation
/// and savings the app can't back.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  test('the empty cart invites no deals or store counts', () {
    for (final text in [en.cartEmptyBody, ar.cartEmptyBody]) {
      for (final claim in ['deal', 'hundreds', 'عروض', 'مئات']) {
        expect(text.toLowerCase(), isNot(contains(claim)), reason: text);
      }
    }
  });

  test('the bundles intro makes no saving or curation claim', () {
    for (final text in [
      en.bundlesHeroTitle,
      en.bundlesHeroBody,
      ar.bundlesHeroTitle,
      ar.bundlesHeroBody,
    ]) {
      for (final claim in [
        'save',
        'curated',
        'verified',
        'value',
        'وفّر',
        'موثّق',
        'بعناية',
        'قيمة',
      ]) {
        expect(text.toLowerCase(), isNot(contains(claim)), reason: text);
      }
    }
  });
}

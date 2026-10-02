import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/presentation/search_providers.dart';
import 'package:hubmarket_app/features/home/domain/hm_home.dart';
import 'package:hubmarket_app/features/home/presentation/widgets/hm_picked_for_you.dart';
import 'package:hubmarket_app/features/home/presentation/widgets/hm_product_rail.dart';
import 'package:hubmarket_app/features/personalization/domain/personal_picks.dart';
import 'package:hubmarket_app/features/personalization/presentation/personal_picks_provider.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/audit_pump.dart';
import '../../support/fakes.dart';
import '../../support/fonts.dart';

List<Product> _pool(String name, [int count = 16]) => [
  for (var i = 0; i < count; i++)
    Product(sku: '$name$i', name: '$name $i', urlKey: '$name$i'),
];

HmHomeSection _section({
  String? badge,
  bool personalizable = true,
  List<Product>? products,
}) => HmHomeSection(
  id: 5,
  type: HmSectionType.pickedForYou,
  title: 'Picked For You',
  subtitle: 'Top-rated products across Hub Market',
  badge: badge,
  limit: 16,
  personalizable: personalizable,
  products: products ?? _pool('Top'),
);

/// The SKUs on show in the rail.
List<String> _shown(WidgetTester tester) => tester
    .widget<HmProductRail>(find.byType(HmProductRail))
    .products
    .map((p) => p.sku)
    .toList();

Future<void> _mount(
  WidgetTester tester,
  HmHomeSection section, {
  Future<PersonalPicks?> Function()? picks,
  VoidCallback? onRefresh,
  String locale = 'en',
  List<Override> more = const [],
}) => pumpAudit(
  tester,
  locale: locale,
  pushed: false,
  screen: Scaffold(
    body: SingleChildScrollView(
      child: HmPickedForYou(section: section, onRefresh: onRefresh),
    ),
  ),
  overrides: [
    personalPicksProvider.overrideWith(
      (ref) => picks == null ? Future.value(null) : picks(),
    ),
    ...more,
  ],
);

void main() {
  setUpAll(loadAppFonts);

  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  group('the top-rated list from the Home', () {
    testWidgets('shows four of the 16, and Refresh turns to the next four, '
        'round to the start', (tester) async {
      await _mount(tester, _section(badge: 'AI ENGINE'));

      expect(_shown(tester), ['Top0', 'Top1', 'Top2', 'Top3']);
      final seen = <String>[];
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text(en.homeRefresh));
        await tester.pump();
        seen.add(_shown(tester).first);
      }
      expect(seen, ['Top4', 'Top8', 'Top12', 'Top0']);
    });

    testWidgets('is not labelled as personal: no pill, the admin\'s subtitle', (
      tester,
    ) async {
      await _mount(tester, _section(badge: 'AI ENGINE'));

      expect(find.text('AI ENGINE'), findsNothing);
      expect(find.text('Top-rated products across Hub Market'), findsOneWidget);
      expect(find.text(en.homePickedPersonalSubtitle), findsNothing);
    });

    testWidgets('with no more than four, Refresh reloads the Home as it did', (
      tester,
    ) async {
      var reloads = 0;
      await _mount(
        tester,
        _section(products: _pool('Top', 4)),
        onRefresh: () => reloads++,
      );

      await tester.tap(find.text(en.homeRefresh));
      await tester.pump();
      expect(reloads, 1);
      expect(_shown(tester), ['Top0', 'Top1', 'Top2', 'Top3']);
    });
  });

  group('the searches row', () {
    // A shopper's own searches, as the search screen keeps them.
    Override searched(List<String> terms) => localCacheProvider.overrideWithValue(
      FakeLocalCache()..writeString('search_history', jsonEncode(terms)),
    );

    testWidgets('a shopper who has not searched sees the store\'s top searches '
        'from Algolia, under a label of their own, four at most', (tester) async {
      await _mount(
        tester,
        _section(),
        more: [
          topSearchesProvider.overrideWith(
            (ref) async => ['bag', 'shirt', 'dress', 'women', 'shoes'],
          ),
        ],
      );
      await tester.pump();

      expect(find.text(en.homeTopSearches), findsOneWidget);
      expect(find.text(en.homeYourSearches), findsNothing);
      for (final term in ['bag', 'shirt', 'dress', 'women']) {
        expect(find.text(term), findsOneWidget, reason: term);
      }
      expect(find.text('shoes'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a shopper who has searched sees their own, and Algolia is '
        'not even asked', (tester) async {
      var asked = 0;
      await _mount(
        tester,
        _section(),
        more: [
          searched(['sofa', 'lamp']),
          topSearchesProvider.overrideWith((ref) async {
            asked++;
            return ['bag', 'shirt'];
          }),
        ],
      );
      await tester.pump();

      expect(find.text(en.homeYourSearches), findsOneWidget);
      expect(find.text(en.homeTopSearches), findsNothing);
      expect(find.text('sofa'), findsOneWidget);
      expect(find.text('lamp'), findsOneWidget);
      expect(find.text('bag'), findsNothing);
      expect(asked, 0);
    });

    testWidgets('with no searches of their own and none from Algolia there is '
        'no row', (tester) async {
      await _mount(
        tester,
        _section(),
        more: [topSearchesProvider.overrideWith((ref) async => const <String>[])],
      );
      await tester.pump();

      expect(find.text(en.homeTopSearches), findsNothing);
      expect(find.text(en.homeYourSearches), findsNothing);
    });

    testWidgets('while Algolia answers there is no row, and a failure leaves '
        'none', (tester) async {
      final answer = Completer<List<String>>();
      await _mount(
        tester,
        _section(),
        more: [topSearchesProvider.overrideWith((ref) => answer.future)],
      );
      expect(find.text(en.homeTopSearches), findsNothing);

      answer.complete(['bag']);
      await tester.pump();
      await tester.pump();
      expect(find.text(en.homeTopSearches), findsOneWidget);
    });

    testWidgets('in Arabic the label is Arabic and the chips read right to '
        'left', (tester) async {
      await _mount(
        tester,
        _section(),
        locale: 'ar',
        more: [topSearchesProvider.overrideWith((ref) async => ['bag', 'حقيبة'])],
      );
      await tester.pump();

      expect(find.text(ar.homeTopSearches), findsOneWidget);
      expect(find.text('حقيبة'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(ar.homeTopSearches))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the shopper\'s own picks', () {
    final personal = PersonalPicks(items: _pool('Bag'), personalized: true);

    testWidgets('replace the list once the server says they are personal, and '
        'only then the pill and the personalised subtitle show', (tester) async {
      final answer = Completer<PersonalPicks?>();
      await _mount(
        tester,
        _section(badge: 'AI ENGINE'),
        picks: () => answer.future,
      );

      // Home first: the cached top-rated four, nothing personal claimed.
      expect(_shown(tester), ['Top0', 'Top1', 'Top2', 'Top3']);
      expect(find.text('AI ENGINE'), findsNothing);

      answer.complete(personal);
      await tester.pump();
      await tester.pump();

      expect(_shown(tester), ['Bag0', 'Bag1', 'Bag2', 'Bag3']);
      expect(find.text('AI ENGINE'), findsOneWidget);
      expect(find.text('✨'), findsOneWidget);
      expect(find.text(en.homePickedPersonalSubtitle), findsOneWidget);
      expect(find.text('Top-rated products across Hub Market'), findsNothing);
    });

    testWidgets('Refresh pages through them', (tester) async {
      await _mount(
        tester,
        _section(badge: 'AI ENGINE'),
        picks: () async => personal,
      );
      await tester.pump();

      await tester.tap(find.text(en.homeRefresh));
      await tester.pump();
      expect(_shown(tester), ['Bag4', 'Bag5', 'Bag6', 'Bag7']);
    });

    testWidgets('a swap starts the rotation over', (tester) async {
      final answer = Completer<PersonalPicks?>();
      await _mount(tester, _section(), picks: () => answer.future);

      await tester.tap(find.text(en.homeRefresh));
      await tester.pump();
      expect(_shown(tester).first, 'Top4');

      answer.complete(personal);
      await tester.pump();
      await tester.pump();
      expect(_shown(tester).first, 'Bag0');
    });

    testWidgets('the admin\'s empty badge means no pill, even for personal '
        'picks', (tester) async {
      await _mount(tester, _section(badge: '  '), picks: () async => personal);
      await tester.pump();

      expect(_shown(tester).first, 'Bag0');
      expect(find.text('✨'), findsNothing);
      expect(find.text(en.homePickedPersonalSubtitle), findsOneWidget);
    });

    testWidgets('are left out of a section the server does not flag '
        'personalizable', (tester) async {
      await _mount(
        tester,
        _section(personalizable: false, badge: 'AI ENGINE'),
        picks: () async => personal,
      );
      await tester.pump();

      expect(_shown(tester).first, 'Top0');
      expect(find.text('AI ENGINE'), findsNothing);
    });

    testWidgets('in Arabic the subtitle is Arabic and the page reads right to '
        'left', (tester) async {
      await _mount(
        tester,
        _section(badge: 'محرك ذكي'),
        picks: () async => personal,
        locale: 'ar',
      );
      await tester.pump();

      expect(find.text('محرك ذكي'), findsOneWidget);
      expect(find.text(ar.homePickedPersonalSubtitle), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(ar.homeRefresh))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

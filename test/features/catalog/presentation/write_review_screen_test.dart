import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/domain/review_subject.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/write_review_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/review_widgets.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';
import '../../../support/fonts.dart';
import '../../../support/pdp_fixtures.dart';

/// Figma 15b (83:3194 / 96:3683): the review form of the dress — close "×" and
/// the title, the product, "How would you rate it?" with four of five stars
/// lit, nickname, summary and review, and the footer with its note and
/// "Submit review". Drawn to build/test_screens/audit_15b_write_review_{en,ar}.png;
/// the frame's "What I like / don't like" fields and its photos are not here,
/// because core Magento's createProductReview takes none of them.

typedef _Created = ({
  String sku,
  String nickname,
  String summary,
  String text,
  List<({String id, String valueId})> ratings,
});

/// The store's rating dimensions — Quality, Value and Price, 1–5 each, as
/// Magento ships them — and a record of what the form sent.
class _Repo extends FakeCatalogRepository {
  _Repo({List<ReviewRatingMetadata>? metadata, this.failure})
    : metadata = metadata ?? _dimensions();

  final List<ReviewRatingMetadata> metadata;
  final Object? failure;
  final List<_Created> created = [];

  static List<ReviewRatingMetadata> _dimensions() => [
    for (final (id, name) in [
      ('quality', 'Quality'),
      ('value', 'Value'),
      ('price', 'Price'),
    ])
      ReviewRatingMetadata(
        id: id,
        name: name,
        values: [
          for (var star = 1; star <= 5; star++)
            ReviewRatingValue(valueId: '${id[0]}-$star', value: star),
        ],
      ),
  ];

  @override
  Future<List<ReviewRatingMetadata>> fetchReviewRatingsMetadata() async =>
      metadata;

  @override
  Future<void> createReview({
    required String sku,
    required String nickname,
    required String summary,
    required String text,
    required List<({String id, String valueId})> ratings,
  }) async {
    if (failure != null) throw failure!;
    created.add((
      sku: sku,
      nickname: nickname,
      summary: summary,
      text: text,
      ratings: ratings,
    ));
  }
}

/// The form opened from a page behind it, as the product page opens it: the
/// route is pushed over `/home`, so the form can pop back to it.
class _Harness {
  _Harness(this.locale, this.repo, this.subject);

  final String locale;
  final _Repo repo;
  final ReviewSubject? subject;
  final key = GlobalKey();
  late final GoRouter router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('PAGE BEHIND')),
      ),
      GoRoute(
        path: '/review/:sku',
        builder: (_, s) =>
            WriteReviewScreen(sku: s.pathParameters['sku']!, subject: subject),
      ),
    ],
  );

  Future<void> open(WidgetTester tester, {Size? size}) async {
    tester.view.physicalSize = size ?? const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localCacheProvider.overrideWithValue(FakeLocalCache()),
          localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
          secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
          catalogRepositoryProvider.overrideWithValue(repo),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp.router(
            routerConfig: router,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(locale),
            locale: Locale(locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(router.push(AppRoutes.review('LOLY-DR-0231')));
    await tester.pumpAndSettle();
  }
}

ReviewSubject _dress(String locale) {
  final dress = floralDressDetail(locale: locale);
  return ReviewSubject(
    sku: dress.sku,
    name: dress.name,
    imageUrl: 'https://hub-market.test/media/floral-dress.jpg',
    sellerName: locale == 'ar' ? 'متجر لولي' : 'loly store',
  );
}

Finder _field(int index) => find.byType(TextField).at(index);

/// Writes the form to `build/test_screens/NAME.png`. Without captureScreen's
/// image pre-cache: the product photo is a network image, which never loads in
/// a widget test, and waiting for it would wait forever.
Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/test_screens/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(loadAppFonts);
  quietNetworkImages();

  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  group('15b the frame', () {
    // The frame's values, typed in; the frame is 1110 / 1112 px high, so the
    // footer lands where the frame's does and the form fills what is above it.
    const typed = {
      'en': (
        'Sara A.',
        'Lovely fabric, true to size',
        'Beautiful print and the tie waist is really flattering. The fabric is '
            'light — perfect for the Dubai heat. Arrived in two days.',
      ),
      'ar': (
        'سارة أ.',
        'قماش جميل ومقاس مضبوط',
        'الطبعة جميلة ورباط الخصر يعطي شكلًا رائعًا. القماش خفيف ومناسب لحرّ '
            'دبي. وصل خلال يومين.',
      ),
    };

    for (final locale in ['en', 'ar']) {
      testWidgets('audit_15b_write_review ($locale)', (tester) async {
        final harness = _Harness(locale, _Repo(), _dress(locale));
        await harness.open(
          tester,
          size: Size(390, locale == 'ar' ? 1112 : 1110),
        );
        final (nickname, summary, text) = typed[locale]!;
        await tester.tap(find.byKey(const ValueKey('review-star-4')));
        await tester.enterText(_field(0), nickname);
        await tester.enterText(_field(1), summary);
        await tester.enterText(_field(2), text);
        await tester.pumpAndSettle();
        // Typing is done: the caret out of the capture.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();

        // The frame's offsets under its 56 px app bar (47..103 there).
        final bar = tester.getRect(find.byType(RuledTopBar));
        double below(Finder f) => tester.getTopLeft(f).dy - bar.bottom;
        expect(bar.height - 56, tester.view.padding.top / 1);
        expect(tester.getSize(find.byType(RuledTopBar)).width, 390);
        await _capture(tester, harness.key, 'audit_15b_write_review_$locale');
        // The product card sits 16 below the bar and is 80 high, the rating
        // title 18 under it.
        final card = find.byKey(const ValueKey('review-subject'));
        expect(below(card), 16);
        expect(tester.getSize(card).height, 80);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('WriteReviewScreen', () {
    testWidgets('shows the product it was opened for', (tester) async {
      final harness = _Harness('en', _Repo(), _dress('en'));
      await harness.open(tester);
      expect(find.text('Floral Print Corset-Waist Tie Dress'), findsOneWidget);
      expect(find.text('loly store'), findsOneWidget);
    });

    testWidgets('a bare link has no product card', (tester) async {
      final harness = _Harness('en', _Repo(), null);
      await harness.open(tester);
      expect(find.byKey(const ValueKey('review-subject')), findsNothing);
      expect(find.text(en.reviewHowRate), findsOneWidget);
    });

    testWidgets('is the three fields the store keeps — no pros, cons or photos', (
      tester,
    ) async {
      final harness = _Harness('en', _Repo(), _dress('en'));
      await harness.open(tester);
      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.text(en.reviewNickname), findsOneWidget);
      expect(find.text(en.reviewSummary), findsOneWidget);
      expect(find.text(en.reviewText), findsOneWidget);
      expect(find.byIcon(HubIcons.camera), findsNothing);
    });

    testWidgets('rates five stars to begin with and words the rating', (
      tester,
    ) async {
      final harness = _Harness('en', _Repo(), _dress('en'));
      await harness.open(tester);
      expect(
        find.text(en.reviewRatingCaption(5, en.reviewRatingExcellent)),
        findsOneWidget,
      );
      for (final (stars, word) in [
        (1, en.reviewRatingPoor),
        (2, en.reviewRatingFair),
        (3, en.reviewRatingAverage),
        (4, en.reviewRatingGood),
        (5, en.reviewRatingExcellent),
      ]) {
        await tester.tap(find.byKey(ValueKey('review-star-$stars')));
        await tester.pump();
        expect(
          find.text(en.reviewRatingCaption(stars, word)),
          findsOneWidget,
          reason: '$stars stars',
        );
      }
    });

    testWidgets('lights the stars up to the one tapped', (tester) async {
      final harness = _Harness('en', _Repo(), _dress('en'));
      await harness.open(tester);
      await tester.tap(find.byKey(const ValueKey('review-star-2')));
      await tester.pump();
      Color colorOf(int star) {
        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(ValueKey('review-star-$star')),
            matching: find.byType(Icon),
          ),
        );
        return icon.color!;
      }

      expect(colorOf(1), colorOf(2));
      expect(colorOf(2), isNot(colorOf(3)));
      expect(colorOf(3), colorOf(5));
    });

    testWidgets('asks for the three fields before it sends anything', (
      tester,
    ) async {
      final repo = _Repo();
      final harness = _Harness('en', repo, _dress('en'));
      await harness.open(tester);
      await tester.ensureVisible(find.text(en.reviewSubmit));
      await tester.tap(find.text(en.reviewSubmit));
      await tester.pumpAndSettle();
      expect(repo.created, isEmpty);
      expect(find.text('PAGE BEHIND'), findsNothing);
      // Three fields, three reminders.
      expect(find.text(en.validationRequired), findsNWidgets(3));
    });

    testWidgets('sends the review with the chosen star on every dimension', (
      tester,
    ) async {
      final repo = _Repo();
      final harness = _Harness('en', repo, _dress('en'));
      await harness.open(tester);
      await tester.tap(find.byKey(const ValueKey('review-star-4')));
      await tester.enterText(_field(0), '  Sara A. ');
      await tester.enterText(_field(1), 'Lovely fabric');
      await tester.enterText(_field(2), 'True to size.  ');
      await tester.ensureVisible(find.text(en.reviewSubmit));
      await tester.tap(find.text(en.reviewSubmit));
      await tester.pumpAndSettle();

      expect(repo.created, hasLength(1));
      final sent = repo.created.single;
      expect(sent.sku, 'LOLY-DR-0231');
      expect(sent.nickname, 'Sara A.');
      expect(sent.summary, 'Lovely fabric');
      expect(sent.text, 'True to size.');
      expect([for (final r in sent.ratings) (r.id, r.valueId)], [
        ('quality', 'q-4'),
        ('value', 'v-4'),
        ('price', 'p-4'),
      ]);
      // Back on the page behind, with the thanks.
      expect(find.text('PAGE BEHIND'), findsOneWidget);
      expect(find.text(en.reviewSubmitted), findsOneWidget);
    });

    testWidgets('keeps the form, and says so, when the store refuses', (
      tester,
    ) async {
      final repo = _Repo(failure: Exception('boom'));
      final harness = _Harness('en', repo, _dress('en'));
      await harness.open(tester);
      await tester.enterText(_field(0), 'Sara A.');
      await tester.enterText(_field(1), 'Lovely fabric');
      await tester.enterText(_field(2), 'True to size.');
      await tester.ensureVisible(find.text(en.reviewSubmit));
      await tester.tap(find.text(en.reviewSubmit));
      await tester.pumpAndSettle();
      expect(find.text(en.errorGeneric), findsOneWidget);
      expect(find.text('PAGE BEHIND'), findsNothing);
      // What was typed is still there, and the button answers again.
      expect(find.text('Lovely fabric'), findsOneWidget);
      expect(find.text(en.reviewSubmit), findsOneWidget);
    });

    testWidgets('a store with no rating dimensions cannot take a review', (
      tester,
    ) async {
      final repo = _Repo(metadata: const []);
      final harness = _Harness('en', repo, _dress('en'));
      await harness.open(tester);
      await tester.enterText(_field(0), 'Sara A.');
      await tester.enterText(_field(1), 'Lovely fabric');
      await tester.enterText(_field(2), 'True to size.');
      await tester.ensureVisible(find.text(en.reviewSubmit));
      await tester.tap(find.text(en.reviewSubmit));
      await tester.pumpAndSettle();
      expect(repo.created, isEmpty);
      expect(find.text(en.errorGeneric), findsOneWidget);
    });

    testWidgets('the close button goes back to the page behind', (tester) async {
      final harness = _Harness('en', _Repo(), _dress('en'));
      await harness.open(tester);
      await tester.tap(find.byIcon(HubIcons.x));
      await tester.pumpAndSettle();
      expect(find.text('PAGE BEHIND'), findsOneWidget);
    });

    testWidgets('has no tab bar: the footer is the note and the button', (
      tester,
    ) async {
      final harness = _Harness('en', _Repo(), _dress('en'));
      await harness.open(tester);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.text(en.reviewFooterNote), findsOneWidget);
      expect(find.byType(ScreenFooter), findsOneWidget);
    });

    testWidgets('right-to-left: the stars run from the right, the card too', (
      tester,
    ) async {
      final harness = _Harness('ar', _Repo(), _dress('ar'));
      await harness.open(tester);
      expect(find.text(ar.reviewHowRate), findsOneWidget);
      expect(find.text(ar.reviewsWrite), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(ar.reviewHowRate))),
        TextDirection.rtl,
      );
      // Star 1 is the right-most, as in the Arabic frame.
      final first = tester.getCenter(find.byKey(const ValueKey('review-star-1')));
      final fifth = tester.getCenter(find.byKey(const ValueKey('review-star-5')));
      expect(first.dx, greaterThan(fifth.dx));
      // The product's photo sits at the start (right) of its card.
      final card = tester.getRect(find.byKey(const ValueKey('review-subject')));
      final name = tester.getTopLeft(find.text('فستان صدر طباعة الأزهار رباط مشد خصر'));
      expect(name.dx, lessThan(card.center.dx));
      expect(tester.takeException(), isNull);
    });
  });
}

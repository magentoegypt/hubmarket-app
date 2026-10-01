import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/catalog/domain/aggregation.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/filter_sheet.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

const _priceAgg = Aggregation(
  attributeCode: 'price',
  label: 'Price',
  options: [
    AggregationOption(label: '10-50', value: '10_50', count: 3),
    AggregationOption(label: '50-200', value: '50_200', count: 5),
  ],
);
const _colorAgg = Aggregation(
  attributeCode: 'color',
  label: 'Color',
  options: [AggregationOption(label: 'Red', value: '1', count: 2)],
);

Future<FilterResult?> _open(
  WidgetTester tester, {
  required List<Aggregation> aggregations,
}) async {
  FilterResult? result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showModalBottomSheet<FilterResult>(
                context: context,
                builder: (_) => FilterSheet(
                  aggregations: aggregations,
                  initial: const {},
                  currency: 'AED',
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('shows a price range slider derived from the price aggregation', (
    tester,
  ) async {
    await _open(tester, aggregations: const [_priceAgg, _colorAgg]);
    expect(find.text('Price (AED)'), findsOneWidget);
    expect(find.byType(RangeSlider), findsOneWidget);
    // The range's ends are the Min and Max boxes (Figma 11).
    expect(find.text('Min'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
  });

  testWidgets('omits the price slider when no price aggregation exists', (
    tester,
  ) async {
    await _open(tester, aggregations: const [_colorAgg]);
    expect(find.byType(RangeSlider), findsNothing);
    expect(find.text('Color'), findsOneWidget);
  });

  testWidgets('hides Discount / Rating where the store cannot filter them', (
    tester,
  ) async {
    await _open(tester, aggregations: const [_priceAgg, _colorAgg]);
    expect(find.text('Color'), findsOneWidget);
    expect(find.text('Discount'), findsNothing);
    expect(find.text('Rating'), findsNothing);
  });

  testWidgets('apply returns a FilterResult (full range => null price)', (
    tester,
  ) async {
    FilterResult? captured;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                captured = await showModalBottomSheet<FilterResult>(
                  context: context,
                  builder: (_) => const FilterSheet(
                    aggregations: [_priceAgg],
                    initial: {},
                    currency: 'AED',
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.priceFrom, isNull, reason: 'full range = no filter');
    expect(captured!.priceTo, isNull);
  });

  group('Figma 11', () {
    /// Opens [sheet] on a tall phone and returns what it pops.
    Future<FilterResult? Function()> open(
      WidgetTester tester,
      FilterSheet sheet,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      FilterResult? captured;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  captured = await showModalBottomSheet<FilterResult>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => sheet,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => captured;
    }

    const vendors = Aggregation(
      attributeCode: 'VENDORID',
      label: 'Vendor ID',
      options: [
        AggregationOption(label: '12', value: '522', count: 8),
        AggregationOption(label: '9', value: '523', count: 3),
        AggregationOption(label: '77', value: '524', count: 1),
      ],
    );

    testWidgets('a facet of vendor ids is the Store section, by store name', (
      tester,
    ) async {
      final result = await open(
        tester,
        const FilterSheet(
          aggregations: [vendors, _colorAgg],
          initial: {},
          currency: 'AED',
          // Vendor 77 has no name: it is left out rather than shown as "77".
          storeNames: {'12': 'MIA CO', '9': 'ENARA'},
        ),
      );
      expect(find.text('Vendor ID'), findsNothing);
      expect(find.text('Store'), findsOneWidget);
      expect(find.text('2 stores'), findsOneWidget);
      expect(find.text('All stores'), findsOneWidget);
      expect(find.text('77'), findsNothing);

      await tester.tap(find.text('MIA CO'));
      await tester.pump();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();
      expect(result()!.attributes, {
        'VENDORID': {'522'},
      });
    });

    testWidgets('All stores takes the store picks off', (tester) async {
      final result = await open(
        tester,
        const FilterSheet(
          aggregations: [vendors],
          initial: {
            'VENDORID': {'522'},
          },
          currency: 'AED',
          storeNames: {'12': 'MIA CO', '9': 'ENARA'},
        ),
      );
      await tester.tap(find.text('All stores'));
      await tester.pump();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();
      expect(result()!.attributes, isEmpty);
    });

    testWidgets('without store names a facet of vendor ids stays out', (
      tester,
    ) async {
      await open(
        tester,
        const FilterSheet(
          aggregations: [vendors],
          initial: {},
          currency: 'AED',
        ),
      );
      expect(find.text('Store'), findsNothing);
      expect(find.text('Vendor ID'), findsNothing);
    });

    testWidgets('Sort by chips return the pick', (tester) async {
      final result = await open(
        tester,
        const FilterSheet(
          aggregations: [_priceAgg],
          initial: {},
          currency: 'AED',
          sortChoices: [
            (value: 'relevance', label: 'Relevance'),
            (value: 'priceAsc', label: 'Lowest price'),
          ],
          initialSort: 'relevance',
        ),
      );
      expect(find.text('Sort by'), findsOneWidget);
      await tester.tap(find.text('Lowest price'));
      await tester.pump();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();
      expect(result()!.sort, 'priceAsc');
    });

    testWidgets('Customer rating offers 4.5, 4 and 3.5 stars', (tester) async {
      final result = await open(
        tester,
        const FilterSheet(
          aggregations: [_priceAgg],
          initial: {},
          currency: 'AED',
          showRating: true,
        ),
      );
      expect(find.text('Customer rating'), findsOneWidget);
      await tester.tap(find.text('4.5'));
      await tester.pump();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();
      // Exactly as picked, and in whole stars for the listings that count so.
      expect(result()!.minRatingStars, 4.5);
      expect(result()!.minRating, 4);
    });

    testWidgets('Show N results follows the selection', (tester) async {
      await open(
        tester,
        FilterSheet(
          aggregations: const [_colorAgg],
          initial: const {},
          currency: 'AED',
          resultCount: 12,
          countFor: (selection) async => selection.attributes.isEmpty ? 12 : 7,
        ),
      );
      expect(find.text('Show 12 results'), findsOneWidget);
      await tester.tap(find.text('Red'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Show 7 results'), findsOneWidget);
    });

    testWidgets('typing a Min moves the range', (tester) async {
      final result = await open(
        tester,
        const FilterSheet(
          aggregations: [_priceAgg, _colorAgg],
          initial: {},
          currency: 'AED',
        ),
      );
      await tester.enterText(find.byType(TextField).first, '50');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();
      // A narrowed range goes back whole: its other end is the bound.
      expect(result()!.priceFrom, 50);
      expect(result()!.priceTo, 200);
    });

    testWidgets('Reset clears the selection', (tester) async {
      final result = await open(
        tester,
        const FilterSheet(
          aggregations: [_priceAgg, _colorAgg],
          initial: {
            'color': {'1'},
          },
          currency: 'AED',
          initialPriceFrom: 20,
        ),
      );
      await tester.tap(find.text('Reset'));
      await tester.pump();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();
      expect(result()!.attributes, isEmpty);
      expect(result()!.priceFrom, isNull);
    });
  });
}

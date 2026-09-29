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
    expect(find.text('Price Range'), findsOneWidget);
    expect(find.byType(RangeSlider), findsOneWidget);
    // Bounds render as a single combined range string (Figma).
    expect(find.text('AED 10 — AED 200'), findsOneWidget);
  });

  testWidgets('omits the price slider when no price aggregation exists', (
    tester,
  ) async {
    await _open(tester, aggregations: const [_colorAgg]);
    expect(find.byType(RangeSlider), findsNothing);
    expect(find.text('Color'), findsOneWidget);
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
}

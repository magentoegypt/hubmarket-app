import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/widgets/shimmer.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/product_skeletons.dart';

Widget _wrap(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Center(
            child: SizedBox(width: 360, height: 1000, child: child),
          ),
        ),
      ),
    );

void main() {
  testWidgets('ProductCardSkeleton renders shimmering placeholder blocks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const SizedBox(width: 180, height: 280, child: ProductCardSkeleton())),
    );
    await tester.pump();

    expect(find.byType(Shimmer), findsOneWidget);
    // Image block, seller / name / rating / price bars and the round add button.
    expect(find.byType(SkeletonBox), findsNWidgets(6));
  });

  testWidgets('ProductGridSkeleton builds the requested number of cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const ProductGridSkeleton(count: 6)),
    );
    await tester.pump();

    expect(find.byType(ProductCardSkeleton), findsNWidgets(6));
  });

  testWidgets('shimmer animation pumps without error in LTR and RTL', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 180,
            height: 280,
            child: ProductCardSkeleton(),
          ),
          direction: direction,
        ),
      );
      // The controller repeats, so advance frames explicitly (never settle).
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
    }
  });
}

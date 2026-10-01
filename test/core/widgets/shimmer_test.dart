import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/core/widgets/shimmer.dart';

Widget _wrap({bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: const Scaffold(
      body: Shimmer(child: SkeletonBox(width: 120, height: 20)),
    ),
  ),
);

void main() {
  testWidgets('skeleton blocks are drawn in the frame\'s bg/subtle', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    expect(
      tester.widget<SkeletonBox>(find.byType(SkeletonBox)).color,
      AppColors.surfaceSubtle,
    );
    expect(
      tester.widget<Shimmer>(find.byType(Shimmer)).base,
      AppColors.surfaceSubtle,
    );
  });

  testWidgets('the sweep repeats until the page is left', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(seconds: 1));
    // Still animating: a repeating controller never lets the tree settle.
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('with "reduce motion" there is no sweep, and leaving the page '
      'is clean', (tester) async {
    await tester.pumpWidget(_wrap(reduceMotion: true));
    // Nothing runs, so the tree settles at once.
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    // The controller used to be created for the first time while the widget was
    // being torn down, which asserts.
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('turning "reduce motion" on stops the sweep, off starts it', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(_wrap(reduceMotion: true));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(_wrap());
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.hasRunningAnimations, isTrue);
  });
}

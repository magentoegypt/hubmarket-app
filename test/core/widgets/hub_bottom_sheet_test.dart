import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/widgets/hub_bottom_sheet.dart';

/// A phone with a 3-button navigation bar: 48 logical pixels at the bottom.
const double _navBar = 48;

Widget _app({required Widget Function(BuildContext) sheet}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: const EdgeInsets.only(top: 24, bottom: _navBar),
        viewPadding: const EdgeInsets.only(top: 24, bottom: _navBar),
      ),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showHubBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: sheet,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the last row of a sheet is lifted clear of the navigation bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        sheet: (_) => const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 60, child: Text('first row')),
            SizedBox(key: Key('last'), height: 60, child: Text('last row')),
          ],
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final bottom = tester.getBottomLeft(find.byKey(const Key('last'))).dy;
    // Screen is 800 high; the bar takes the bottom 48.
    expect(bottom, lessThanOrEqualTo(800 - _navBar));
  });

  testWidgets('a sheet that has its own SafeArea is not padded twice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        sheet: (_) => const SafeArea(
          child: SizedBox(key: Key('body'), height: 100, child: Text('body')),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final bottom = tester.getBottomLeft(find.byKey(const Key('body'))).dy;
    // Lifted by the bar once, not twice.
    expect(bottom, lessThanOrEqualTo(800 - _navBar));
    expect(bottom, greaterThan(800 - _navBar - 1));
  });
}

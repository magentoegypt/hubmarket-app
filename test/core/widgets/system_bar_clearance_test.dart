import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/widgets/hub_bottom_action_bar.dart';
import 'package:hubmarket_app/core/widgets/hub_footer_bar.dart';
import 'package:hubmarket_app/core/widgets/system_bar_clearance.dart';

/// A pinned bar's button has to clear what the system draws under it. On a
/// phone with a persistent navigation bar (a three-button bar is 47 dp tall) the
/// Save button of Profile details lay 35 dp under it, half hidden and untappable
/// where it was; an iPhone's thin home indicator is another matter, and the
/// frames' spacing stands there.

Widget _host({
  required TargetPlatform platform,
  required double inset,
  required Widget bar,
}) => MaterialApp(
  theme: ThemeData(platform: platform),
  home: MediaQuery(
    data: MediaQueryData(
      viewPadding: EdgeInsets.only(bottom: inset),
      padding: EdgeInsets.only(bottom: inset),
    ),
    child: Scaffold(bottomNavigationBar: bar),
  ),
);

/// The clearance [systemBarClearance] works out under [platform] with [inset].
Future<double> _clearance(
  WidgetTester tester, {
  required TargetPlatform platform,
  required double inset,
  double iosGap = 4,
}) async {
  late double result;
  await tester.pumpWidget(
    _host(
      platform: platform,
      inset: inset,
      bar: Builder(
        builder: (context) {
          result = systemBarClearance(context, iosGap: iosGap);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  // A new app with another theme platform animates from the old one: settle.
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('systemBarClearance', () {
    testWidgets('an Android three-button bar is cleared as a whole', (
      tester,
    ) async {
      expect(
        await _clearance(tester, platform: TargetPlatform.android, inset: 47),
        47,
      );
    });

    testWidgets('an Android gesture bar and no bar at all', (tester) async {
      expect(
        await _clearance(tester, platform: TargetPlatform.android, inset: 24),
        24,
      );
      expect(
        await _clearance(tester, platform: TargetPlatform.android, inset: 0),
        0,
      );
    });

    testWidgets('an iPhone keeps the frame\'s space: the inset less the gap', (
      tester,
    ) async {
      expect(
        await _clearance(tester, platform: TargetPlatform.iOS, inset: 34),
        30,
      );
      expect(
        await _clearance(
          tester,
          platform: TargetPlatform.iOS,
          inset: 34,
          iosGap: 6,
        ),
        28,
      );
      expect(
        await _clearance(tester, platform: TargetPlatform.iOS, inset: 0),
        0,
      );
    });
  });

  group('HubFooterBar', () {
    Future<double> spaceUnderButton(
      WidgetTester tester, {
      required TargetPlatform platform,
      required double inset,
    }) async {
      const button = Key('button');
      await tester.pumpWidget(
        _host(
          platform: platform,
          inset: inset,
          bar: const HubFooterBar(child: SizedBox(key: button, height: 52)),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getRect(find.byType(HubFooterBar)).bottom -
          tester.getRect(find.byKey(button)).bottom;
    }

    testWidgets('lifts the button above a three-button navigation bar', (
      tester,
    ) async {
      expect(
        await spaceUnderButton(
          tester,
          platform: TargetPlatform.android,
          inset: 47,
        ),
        47,
      );
    });

    testWidgets('keeps the frame\'s 28 px where nothing is in the way', (
      tester,
    ) async {
      expect(
        await spaceUnderButton(
          tester,
          platform: TargetPlatform.android,
          inset: 0,
        ),
        28,
      );
      // An iPhone: 34 less the 4 the frame already has, so 30, not 34.
      expect(
        await spaceUnderButton(tester, platform: TargetPlatform.iOS, inset: 34),
        30,
      );
    });
  });

  group('HubBottomActionBar', () {
    testWidgets('clears a three-button navigation bar too', (tester) async {
      const button = Key('button');
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.android,
          inset: 47,
          bar: const HubBottomActionBar(
            child: SizedBox(key: button, height: 52),
          ),
        ),
      );
      final under =
          tester.getRect(find.byType(HubBottomActionBar)).bottom -
          tester.getRect(find.byKey(button)).bottom;
      expect(under, 47);
    });
  });
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';

import '../../test/support/audit_pump.dart';
import '../../test/support/fakes.dart';
import 'audit_scene.dart';

/// Takes one capture: [name] is the file name without `.png`; [boundary] wraps
/// the whole app, for the host-side capture that paints it to an image (on the
/// phone `binding.takeScreenshot(name)` ignores it).
typedef CaptureFn = Future<void> Function(String name, GlobalKey boundary);

/// What one scene run found.
class SceneRun {
  SceneRun(this.scene, this.locale);

  final AuditScene scene;
  final String locale;

  /// The captures taken, by file name (without `.png`).
  final List<String> captures = [];

  /// Layout overflows and other framework errors raised while the scene was
  /// mounted, one line each: what happened and the widget it happened in.
  final List<String> errors = [];

  String get id => '$locale-${scene.id}';
}

/// Pumps frames for [ms] milliseconds in 100 ms steps. `pumpAndSettle` would
/// time out on the shimmering skeletons and the auto-advancing carousels, and a
/// network image needs wall-clock time on the phone, which a step-wise pump
/// gives it.
Future<void> pumpFor(WidgetTester tester, int ms) async {
  var left = ms;
  while (left > 0) {
    final step = math.min(left, 100);
    await tester.pump(Duration(milliseconds: step));
    left -= step;
  }
}

/// Mounts [scene] in [locale] like the widget tests do (`pumpAudit`), lets it
/// settle, runs its `act`, captures it and then the scrolled-down parts, and
/// unmounts it. Never throws: whatever goes wrong is in [SceneRun.errors], so
/// one broken scene does not end the run.
Future<SceneRun> runScene(
  WidgetTester tester,
  AuditScene scene,
  String locale,
  CaptureFn capture,
) async {
  final run = SceneRun(scene, locale);
  final original = FlutterError.onError;
  FlutterError.onError = (details) => run.errors.add(describeError(details));
  // The integration test binding leaves the fake keyboard uninstalled ("to test
  // real IME input"), so on the phone `enterText`, and a field with `autofocus`,
  // would raise the phone's own keyboard and its inset would resize the screen
  // under the capture. The scenes want what the widget tests get: text goes in,
  // no keyboard shows.
  final keyboard = tester.testTextInput;
  final fakeKeyboard = !keyboard.isRegistered;
  if (fakeKeyboard) keyboard.register();
  ProviderContainer? container;
  try {
    // Prices read "425 د.إ" in Arabic (the app root sets this from the store).
    Money.arabic = locale == 'ar';
    final setup = scene.setup?.call(locale) ?? const AuditSetup();
    container = ProviderContainer(
      overrides: auditOverrides(
        locale: locale,
        signedIn: scene.signedIn,
        account: setup.account,
        returns: setup.returns,
        wishlist: setup.wishlist,
        features: setup.features,
        hubApp: setup.hubApp,
        // No scene may reach the server: the token-less client, which the Hub
        // Market App data (stores, deals, brands, the Home sections) goes
        // through, is a fake unless the scene brings its own.
        overrides: [
          publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
          ...setup.overrides,
        ],
      ),
    );
    final router = auditRouter(
      screen: scene.screen(locale),
      pushed: scene.pushed,
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: boundary,
          child: auditApp(router: router, locale: locale),
        ),
      ),
    );
    if (scene.pushed) {
      await tester.pump();
      router.push('/screen');
    }
    await pumpFor(tester, scene.settleMs);
    if (scene.act != null) {
      await scene.act!(tester, locale);
      await pumpFor(tester, 600);
    }
    await capture(run.id, boundary);
    run.captures.add(run.id);
    for (var i = 1; i <= scene.scrolls; i++) {
      if (!scrollMain(tester)) break;
      await pumpFor(tester, 500);
      final name = '${run.id}__s$i';
      await capture(name, boundary);
      run.captures.add(name);
    }
    final pending = tester.takeException();
    if (pending != null) run.errors.add('EXCEPTION $pending');
  } catch (error) {
    run.errors.add('EXCEPTION in the scene: $error');
  } finally {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      // Host only: a timer a screen started (the splash's hold, a countdown)
      // fires after the screen is gone; let the fake clock run it out, or the
      // test ends with a pending timer.
      if (tester.binding is! LiveTestWidgetsFlutterBinding) {
        await tester.pump(const Duration(seconds: 3));
      }
      tester.takeException();
    } catch (_) {}
    container?.dispose();
    // After the tree is gone, so its fields close their connections through the
    // fake keyboard.
    if (fakeKeyboard) keyboard.unregister();
    FlutterError.onError = original;
  }
  return run;
}

/// Scrolls the screen's longest vertical scrollable down by about a screen.
/// False when there is none, or it is at the end already.
bool scrollMain(WidgetTester tester) {
  ScrollPosition? best;
  for (final element in find.byType(Scrollable).evaluate()) {
    if (element is! StatefulElement) continue;
    final state = element.state;
    if (state is! ScrollableState) continue;
    final axis = state.axisDirection;
    if (axis == AxisDirection.left || axis == AxisDirection.right) continue;
    final position = state.position;
    if (!position.hasContentDimensions) continue;
    if (best == null || position.maxScrollExtent > best.maxScrollExtent) {
      best = position;
    }
  }
  if (best == null || best.pixels >= best.maxScrollExtent - 1) return false;
  best.jumpTo(
    math.min(best.pixels + best.viewportDimension * 0.85, best.maxScrollExtent),
  );
  return true;
}

/// One line for a framework error: its first sentence and the widget it was
/// raised in (the `Row:file:///...` creator, when the error names one).
String describeError(FlutterErrorDetails details) {
  final text = details.toString();
  final first = details.summary.toString().split('\n').first;
  final creator = RegExp(r'\w+:file:///\S+').firstMatch(text)?.group(0);
  final where = creator == null
      ? ''
      : ' @ ${creator.replaceAll(RegExp(r'file:///.*?/lib/'), 'lib/')}';
  return '$first$where';
}

/// The view's size, pixel ratio and system-bar insets, for the log.
String describeView(WidgetTester tester) {
  final view = tester.view;
  final ratio = view.devicePixelRatio;
  final size = view.physicalSize / ratio;
  return 'logical ${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)} '
      'dpr $ratio, padding top ${(view.padding.top / ratio).toStringAsFixed(1)} '
      'bottom ${(view.padding.bottom / ratio).toStringAsFixed(1)}';
}

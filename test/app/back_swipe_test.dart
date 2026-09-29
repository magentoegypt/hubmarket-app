import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/shell/back_swipe.dart';

/// Default test surface is 800x600, so the commit threshold (25% of width) is
/// 200 logical px. Drags meant not to commit travel less than that, and slowly
/// enough that the fling escape hatch (700 px/s) doesn't fire either.
const double _screenWidth = 800;
const Offset _commitDrag = Offset(250, 0);
const Duration _slow = Duration(milliseconds: 500);

Future<int> _pumpAndDrag(
  WidgetTester tester, {
  required TextDirection direction,
  required Offset from,
  required Offset move,
  bool startEdge = false,
  bool trailingEdge = false,
  bool enabled = true,
  EdgeInsets systemGestureInsets = EdgeInsets.zero,
  Duration duration = _slow,
  Widget child = const ColoredBox(color: Color(0xFF000000)),
}) async {
  var backs = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(systemGestureInsets: systemGestureInsets),
          child: Directionality(
            textDirection: direction,
            child: BackSwipeDetector(
              enabled: enabled,
              startEdge: startEdge,
              trailingEdge: trailingEdge,
              onBack: () => backs++,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.timedDragFrom(from, move, duration);
  await tester.pumpAndSettle();
  return backs;
}

void main() {
  group('BackSwipePolicy', () {
    test('anything poppable takes the leading edge from the drawer', () {
      final policy = BackSwipePolicy.forRoute(
        canPop: true,
        isTabRoot: false,
        isHome: false,
      );
      expect(policy.enabled, isTrue);
      expect(policy.startEdge, isTrue);
      expect(policy.trailingEdge, isFalse);
      expect(policy.drawerOwnsLeadingEdge, isFalse);
    });

    test('a non-Home tab root leaves the leading edge to the drawer', () {
      final policy = BackSwipePolicy.forRoute(
        canPop: false,
        isTabRoot: true,
        isHome: false,
      );
      expect(policy.enabled, isTrue);
      expect(policy.startEdge, isFalse);
      expect(policy.trailingEdge, isTrue);
      expect(policy.drawerOwnsLeadingEdge, isTrue);
    });

    test('Home arms nothing, there is nowhere further back to go', () {
      final policy = BackSwipePolicy.forRoute(
        canPop: false,
        isTabRoot: true,
        isHome: true,
      );
      expect(policy.enabled, isFalse);
      expect(policy.drawerOwnsLeadingEdge, isTrue);
    });

    test('a first route that is not a tab root arms nothing', () {
      // Splash and welcome. Sending a swipe "home" from onboarding would skip
      // the sign-in choice entirely.
      final policy = BackSwipePolicy.forRoute(
        canPop: false,
        isTabRoot: false,
        isHome: false,
      );
      expect(policy.enabled, isFalse);
      expect(policy.startEdge, isFalse);
      expect(policy.trailingEdge, isFalse);
    });

    test('a bare-Scaffold screen that was pushed is covered too', () {
      // Settings, search, checkout, addresses: no HubScaffold, so before
      // AppBackSwipe these armed nothing at all.
      final policy = BackSwipePolicy.forRoute(
        canPop: true,
        isTabRoot: false,
        isHome: false,
      );
      expect(policy.enabled, isTrue);
      expect(policy.startEdge, isTrue);
    });
  });

  group('BackSwipeDetector leading edge (pushed routes)', () {
    testWidgets('English: drag rightward from the left edge goes back', (
      tester,
    ) async {
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.ltr,
        startEdge: true,
        // Band is 20..52 with no system inset; 36 sits in the middle.
        from: const Offset(36, 300),
        move: _commitDrag,
      );
      expect(backs, 1);
    });

    testWidgets('Arabic: the band mirrors to the right edge', (tester) async {
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.rtl,
        startEdge: true,
        // Mirrored band is 748..780; back is a leftward drag.
        from: const Offset(_screenWidth - 36, 300),
        move: -_commitDrag,
      );
      expect(backs, 1);
    });

    testWidgets('dragging the wrong way does not go back', (tester) async {
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.ltr,
        startEdge: true,
        from: const Offset(36, 300),
        move: -_commitDrag,
      );
      expect(backs, 0);
    });
  });

  group('BackSwipeDetector trailing edge (tab roots)', () {
    testWidgets('English: drag leftward from the right edge goes back', (
      tester,
    ) async {
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.ltr,
        trailingEdge: true,
        from: const Offset(_screenWidth - 16, 300),
        move: -_commitDrag,
      );
      expect(backs, 1);
    });

    testWidgets('Arabic: drag rightward from the left edge goes back', (
      tester,
    ) async {
      // The ticket, literally: "swiping the screen to the right in the Arabic
      // view brings us back to the main page again".
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.rtl,
        trailingEdge: true,
        from: const Offset(16, 300),
        move: _commitDrag,
      );
      expect(backs, 1);
    });

    testWidgets('the leading edge stays free for the drawer', (tester) async {
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.ltr,
        trailingEdge: true,
        from: const Offset(36, 300),
        move: _commitDrag,
      );
      expect(backs, 0);
    });
  });

  group('BackSwipeDetector system gesture insets (Android 11 guard)', () {
    // The bug this task exists for: Flutter's own detector sits at
    // `start: 0, width: max(padding, 20)`, inside the band Android reserves for
    // system navigation, so on API 30 (no predictive back to compensate) the
    // drag is never delivered. Ours has to start past it.
    const reserved = EdgeInsets.symmetric(horizontal: 40);

    testWidgets('the band starts outboard of the reserved zone', (
      tester,
    ) async {
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.ltr,
        startEdge: true,
        systemGestureInsets: reserved,
        // Band is 40..72 once the inset is honoured; 50 is inside it.
        from: const Offset(50, 300),
        move: _commitDrag,
      );
      expect(backs, 1);
    });

    testWidgets('nothing is armed inside the zone Android consumes', (
      tester,
    ) async {
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.ltr,
        startEdge: true,
        systemGestureInsets: reserved,
        // 30 would land in the band if the inset were ignored (20..52), which
        // is exactly the regression this guards against.
        from: const Offset(30, 300),
        move: _commitDrag,
      );
      expect(backs, 0);
    });

    testWidgets('the inset resolves directionally in Arabic', (tester) async {
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.rtl,
        startEdge: true,
        // Asymmetric, so a left/right mix-up cannot pass by accident.
        systemGestureInsets: const EdgeInsets.only(right: 40),
        from: const Offset(_screenWidth - 50, 300),
        move: -_commitDrag,
      );
      expect(backs, 1);
    });
  });

  group('BackSwipeDetector thresholds', () {
    testWidgets('a short slow drag does not go back', (tester) async {
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.ltr,
        startEdge: true,
        from: const Offset(36, 300),
        move: const Offset(60, 0),
        duration: const Duration(seconds: 1),
      );
      expect(backs, 0);
    });

    testWidgets('a short fast fling does go back', (tester) async {
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.ltr,
        startEdge: true,
        from: const Offset(36, 300),
        move: const Offset(80, 0),
        duration: const Duration(milliseconds: 60),
      );
      expect(backs, 1);
    });

    testWidgets('disabled arms nothing at all', (tester) async {
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.ltr,
        startEdge: true,
        enabled: false,
        from: const Offset(36, 300),
        move: _commitDrag,
      );
      expect(backs, 0);
    });
  });

  group('BackSwipeDetector arena deference', () {
    // Found on device: dragging the PLP sub-category rail from inside the band
    // navigated back instead of scrolling the rail. The band is an overlay, so
    // it is hit-tested first and used to win the arena at the same touch slop
    // the carousel accepts at.
    testWidgets('a horizontal carousel under the band keeps its drag', (
      tester,
    ) async {
      // Start scrolled in, so a drag in the *back* direction is also a drag the
      // carousel can act on — the real conflict seen on the PLP rail.
      final controller = ScrollController(initialScrollOffset: 500);
      addTearDown(controller.dispose);
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.ltr,
        startEdge: true,
        child: ListView.builder(
          controller: controller,
          scrollDirection: Axis.horizontal,
          itemCount: 40,
          itemBuilder: (_, i) => SizedBox(width: 120, child: Text('item $i')),
        ),
        from: const Offset(36, 300),
        move: _commitDrag,
      );
      expect(backs, 0, reason: 'the carousel must win, not the back swipe');
      expect(
        controller.offset,
        lessThan(500),
        reason: 'and it must actually have scrolled',
      );
    });

    testWidgets('a vertical list under the band still yields the back swipe', (
      tester,
    ) async {
      // A vertical scrollable rejects a horizontal drag, so the band is the
      // only member left when the arena sweeps.
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.ltr,
        startEdge: true,
        child: ListView.builder(
          itemCount: 40,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('row $i')),
        ),
        from: const Offset(36, 300),
        move: _commitDrag,
      );
      expect(backs, 1);
    });
  });

  group('BackSwipeDetector commit distance', () {
    // These must run with a competing recognizer underneath. An uncontested
    // arena accepts at pointer-down, so the raised slop costs nothing and the
    // regression below cannot reproduce — which is exactly why it reached a
    // device: the roomy test surface passed while a 360dp phone did not.
    Widget competitor() => ListView.builder(
      itemCount: 40,
      itemBuilder: (_, i) => SizedBox(height: 80, child: Text('row $i')),
    );

    testWidgets('a drag just past the threshold still commits', (tester) async {
      const threshold = _screenWidth * 0.25; // 200
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.ltr,
        startEdge: true,
        child: competitor(),
        from: const Offset(36, 300),
        move: const Offset(threshold + 10, 0),
        duration: const Duration(seconds: 1), // slow: distance must carry it
      );
      expect(
        backs,
        1,
        reason: 'travel before the arena win must still count toward the commit',
      );
    });

    testWidgets('a drag just under the threshold does not commit', (
      tester,
    ) async {
      const threshold = _screenWidth * 0.25;
      final backs = await _pumpAndDrag(
        tester,
        direction: TextDirection.ltr,
        startEdge: true,
        child: competitor(),
        from: const Offset(36, 300),
        move: const Offset(threshold - 10, 0),
        duration: const Duration(seconds: 1),
      );
      expect(backs, 0);
    });
  });
}

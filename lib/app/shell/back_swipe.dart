import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../routes.dart';

/// Width of the framework's own Cupertino back-gesture strip
/// (`_kBackGestureWidth`, `package:flutter/src/cupertino/route.dart`). The
/// app-owned band starts *after* it so the two never overlap and never fight
/// in the gesture arena.
const double kFrameworkBackGestureWidth = 20.0;

/// Width of the app-owned band. Deliberately wider than the framework's 20 px:
/// this is the whole target on a device where the OS eats the screen edge.
const double kBackSwipeBandWidth = 32.0;

/// Fraction of the screen a drag must cover to commit, if it isn't a fling.
const double _kCommitFraction = 0.25;

/// …or this much fling velocity, in logical px/s.
const double _kCommitVelocity = 700.0;

/// How far the drag must travel before the band claims it. Comfortably above
/// [kTouchSlop] (18) so a carousel underneath always claims first, and far
/// below the commit distance so the gesture still feels immediate.
const double _kEdgeAcceptSlop = 40.0;

/// Which edges mean "back" on a given route. Decided in one place so every
/// screen behaves the same — the shell screens and the ~20 that use a bare
/// [Scaffold] alike. (There is no side menu: the design has none, so the
/// leading edge is always free for "back".)
///
/// | Route                  | Leading edge | Trailing edge |
/// |------------------------|--------------|---------------|
/// | Home                   | —            | —             |
/// | Other tab root         | → Home       | —             |
/// | Anything poppable      | → pop        | —             |
/// | Splash / welcome       | —            | —             |
///
/// That last row matters: those are first routes too, but they are not tab
/// roots, and sending a swipe "home" from onboarding would skip the sign-in
/// choice entirely.
@immutable
class BackSwipePolicy {
  const BackSwipePolicy._({
    required this.enabled,
    required this.startEdge,
    required this.trailingEdge,
  });

  factory BackSwipePolicy.forRoute({
    required bool canPop,
    required bool isTabRoot,
    required bool isHome,
  }) {
    // Only a tab root below Home has somewhere to go when nothing can pop.
    final goesHome = !canPop && isTabRoot && !isHome;
    return BackSwipePolicy._(
      enabled: canPop || goesHome,
      startEdge: canPop || goesHome,
      trailingEdge: false,
    );
  }

  final bool enabled;
  final bool startEdge;
  final bool trailingEdge;
}

/// An app-owned horizontal edge drag that means "back", placed **outboard of
/// [MediaQueryData.systemGestureInsets]** (CL042-DEV11).
///
/// Flutter's own back gesture cannot be relied on here. Its detector is a 20 px
/// strip flush against the screen edge — `PositionedDirectional(start: 0,
/// width: max(padding, 20))` in `cupertino/route.dart` — which sits entirely
/// inside the band Android reserves for system navigation. `media_query.dart`
/// says it plainly: *"Apps should avoid locating gesture detectors within the
/// system gesture insets area."* With gesture navigation the OS consumes those
/// swipes and never delivers them.
///
/// On Android 13+ that goes unnoticed, because the system back gesture reaches
/// Flutter anyway and commits the pop. **On Android 11 (API 30) there is no
/// predictive back to fall back on**, so the drag simply dies — which is how
/// this reached QA twice as "swipe back doesn't work". The fix is to own the
/// gesture on a band offset past the reserved zone; it then works in gesture
/// *and* 3-button navigation without depending on the OS at all.
///
/// The framework also refuses the gesture outright when `route.isFirst`
/// (`widgets/routes.dart`, `popGestureEnabled`), which is every bottom-nav tab
/// root — those reach their screens through `context.go`, replacing the stack.
/// That is the "…or to the homepage" half of the ticket, and nothing in the
/// framework will ever serve it.
///
/// Everything here is directional: [PositionedDirectional] and an RTL sign flip
/// on the drag, mirroring the SDK's own `_convertToLogical`. Never mirror by
/// hand — see the `rtl-arrow-double-flip` lesson.
class BackSwipeDetector extends StatelessWidget {
  const BackSwipeDetector({
    super.key,
    required this.enabled,
    required this.onBack,
    required this.child,
    this.startEdge = false,
    this.trailingEdge = false,
  });

  /// When false the child is returned untouched — no [Stack], no recognizer,
  /// nothing entered into the gesture arena.
  final bool enabled;

  final VoidCallback onBack;

  /// Arm the leading edge — left in English, right in Arabic. Used on pushed
  /// routes to widen the framework's unreachable strip inward.
  final bool startEdge;

  /// Arm the trailing edge — right in English, left in Arabic.
  final bool trailingEdge;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled || (!startEdge && !trailingEdge)) return child;

    // `systemGestureInsets` is physical left/right; resolve it directionally.
    final insets = MediaQuery.systemGestureInsetsOf(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final startInset = isRtl ? insets.right : insets.left;
    final endInset = isRtl ? insets.left : insets.right;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        if (startEdge)
          _EdgeBand(
            fromStart: true,
            // Clear the OS zone *and* the framework's own strip.
            inset: math.max(startInset, kFrameworkBackGestureWidth),
            onBack: onBack,
          ),
        if (trailingEdge)
          _EdgeBand(fromStart: false, inset: endInset, onBack: onBack),
      ],
    );
  }
}

class _EdgeBand extends StatefulWidget {
  const _EdgeBand({
    required this.fromStart,
    required this.inset,
    required this.onBack,
  });

  /// Leading edge when true, trailing edge when false.
  final bool fromStart;

  /// How far in from that edge the band begins.
  final double inset;

  final VoidCallback onBack;

  @override
  State<_EdgeBand> createState() => _EdgeBandState();
}

class _EdgeBandState extends State<_EdgeBand> {
  double _travel = 0;

  /// Physical dx → logical, exactly as the SDK's `_convertToLogical` does: in
  /// RTL a leftward drag is forward progress.
  double _toLogical(double value) =>
      Directionality.of(context) == TextDirection.rtl ? -value : value;

  /// Which way "back" points for this band, in logical terms. A leading-edge
  /// drag travels toward the trailing edge (+); a trailing-edge drag travels
  /// back toward the leading edge (−).
  double get _backwards => widget.fromStart ? 1.0 : -1.0;

  void _onStart(DragStartDetails _) => _travel = 0;

  void _onUpdate(DragUpdateDetails details) =>
      _travel += details.primaryDelta ?? 0;

  void _onEnd(DragEndDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    // Positive once the drag heads the way "back" lies for this edge.
    final travel = _toLogical(_travel) * _backwards;
    final velocity =
        _toLogical(details.velocity.pixelsPerSecond.dx) * _backwards;
    _travel = 0;
    if (travel > width * _kCommitFraction || velocity > _kCommitVelocity) {
      widget.onBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      start: widget.fromStart ? widget.inset : null,
      end: widget.fromStart ? null : widget.inset,
      width: kBackSwipeBandWidth,
      top: 0,
      bottom: 0,
      child: RawGestureDetector(
        // Translucent so taps still reach what sits under the band — the app
        // bar's search and bell buttons live on the trailing edge.
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          _EdgeBackDrag:
              GestureRecognizerFactoryWithHandlers<_EdgeBackDrag>(
                () => _EdgeBackDrag(debugOwner: this),
                (recognizer) => recognizer
                  // Required, and paired with the raised slop in
                  // [_EdgeBackDrag]. While another recognizer competes, the win
                  // is deferred until that slop is passed, and under the default
                  // `start` behaviour every pixel travelled before the win is
                  // discarded (`monodrag.dart` sets `localUpdateDelta =
                  // Offset.zero`). It would be deducted from the distance
                  // measured here — enough, on a 360dp phone, to drop a real
                  // swipe under the commit distance. An *uncontested* arena
                  // accepts at pointer-down and loses nothing, which is why
                  // this only shows up on screens that have a scrollable.
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onStart = _onStart
                  ..onUpdate = _onUpdate
                  ..onEnd = _onEnd,
              ),
        },
      ),
    );
  }
}

/// A horizontal drag that only claims the gesture after a longer travel than
/// the ordinary touch slop, so anything scrollable underneath wins first.
///
/// The band is an overlay, so it is hit-tested ahead of the content and, at
/// equal slop, would take the drag away from horizontal carousels sitting under
/// it — the PLP sub-category rail, the PDP gallery. Verified on device before
/// this existed: dragging the PLP rail navigated back instead of scrolling it.
///
/// Raising our own acceptance threshold is the arena working as designed: a
/// carousel accepts at [kTouchSlop] and wins outright, while on a screen with
/// nothing else competing we accept a few pixels later and behave identically.
/// The threshold stays far below the commit distance, so the swipe itself feels
/// no different.
///
/// Note the alternative — never self-accepting and waiting for the arena sweep
/// — does not work: [DragGestureRecognizer] rejects its own pointer on pointer-up
/// (`_giveUpPointer`), so it is gone before any sweep happens.
class _EdgeBackDrag extends HorizontalDragGestureRecognizer {
  _EdgeBackDrag({super.debugOwner});

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind kind,
    double? deviceTouchSlop,
  ) {
    return globalDistanceMoved.abs() > _kEdgeAcceptSlop;
  }
}

/// Installs the back swipe once, above the router's [Navigator], so it covers
/// every route — the shell screens and the ~20 that build a bare [Scaffold]
/// (settings, search, auth, checkout, addresses, order detail…). Those were the
/// screens QA reported it "not working on": nothing there ever armed a gesture,
/// because only [HubScaffold] used to install one.
///
/// Going through [NavigatorState.maybePop] rather than `router.pop()` is
/// deliberate: it fires [PopScope], so `HubScaffold`'s existing ladder still
/// runs — a tab root heads back to Home. When nothing handles the pop, a tab
/// root falls through to Home explicitly.
class AppBackSwipe extends StatefulWidget {
  const AppBackSwipe({
    super.key,
    required this.router,
    required this.navigatorKey,
    required this.child,
  });

  final GoRouter router;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AppBackSwipe> createState() => _AppBackSwipeState();
}

class _AppBackSwipeState extends State<AppBackSwipe> {
  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_onRouteChanged);
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRouteChanged);
    super.dispose();
  }

  /// Deferred by a frame on purpose. This widget sits *above* the `Router`, and
  /// the delegate notifies while that descendant is building — rebuilding
  /// synchronously marks an already-dirty ancestor dirty again and trips
  /// framework's `!_dirty` assertion. A frame's lag in arming an edge band is
  /// imperceptible.
  void _onRouteChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// The current path, or null before the router has resolved its first match.
  /// [GoRouter.state] throws `Bad state: No element` in that window, which is
  /// reachable on the very first build.
  String? get _location {
    final configuration = widget.router.routerDelegate.currentConfiguration;
    return configuration.isEmpty ? null : configuration.uri.path;
  }

  bool _isTabRoot(String location) =>
      AppTab.values.any((tab) => tab.route == location);

  @override
  Widget build(BuildContext context) {
    final location = _location;
    if (location == null) return widget.child;
    final policy = BackSwipePolicy.forRoute(
      canPop: widget.router.canPop(),
      isTabRoot: _isTabRoot(location),
      isHome: location == AppRoutes.home,
    );
    return BackSwipeDetector(
      enabled: policy.enabled,
      startEdge: policy.startEdge,
      trailingEdge: policy.trailingEdge,
      onBack: _back,
      child: widget.child,
    );
  }

  Future<void> _back() async {
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    // maybePop fires PopScope, so HubScaffold's ladder still runs: a tab root
    // heads back to Home.
    if (await navigator.maybePop()) return;
    final location = _location;
    if (location != null &&
        location != AppRoutes.home &&
        _isTabRoot(location)) {
      widget.router.go(AppRoutes.home);
    }
  }
}

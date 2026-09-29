import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../routes.dart';
import 'back_swipe.dart';
import 'menu_drawer.dart';
import 'hub_app_bar.dart';
import 'hub_bottom_nav.dart';

/// Standard chrome for primary screens: shared app bar + drawer + bottom nav.
/// Content screens place the [MarketingFooter] at the end of their own scroll
/// view; the 1st-group screens (splash/welcome/auth) do NOT use this scaffold.
///
/// Owns the back policy for its screens (QA): an open drawer closes first; a
/// pushed route pops; a non-Home tab root returns to Home (instead of exiting
/// the app); only Home itself exits. That policy is reached three ways — the
/// Android system back, the app-bar arrow, and the edge swipe — and they all
/// land on the same ladder in [_onBack] or on [BackSwipeDetector].
class HubScaffold extends StatefulWidget {
  const HubScaffold({
    super.key,
    required this.currentTab,
    required this.body,
    this.showSearch = true,
    this.appBar,
    this.bottomBar,
  });

  final AppTab currentTab;
  final Widget body;
  final bool showSearch;
  final PreferredSizeWidget? appBar;

  /// Optional persistent bar pinned directly above the bottom nav (e.g. the PDP
  /// sticky Add-to-Cart bar). Null on most screens.
  final Widget? bottomBar;

  @override
  State<HubScaffold> createState() => _HubScaffoldState();
}

class _HubScaffoldState extends State<HubScaffold> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Mirrors the drawer's open state so [build] can hand the pop back to the
  /// framework only while the drawer is shut. Tracked rather than read from the
  /// key because `canPop` is decided at build time.
  bool _drawerOpen = false;

  void _onBack(bool didPop, Object? result) {
    if (didPop) return;
    // 1) Close the drawer if it's open.
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen ?? false) {
      scaffold!.closeDrawer();
      return;
    }
    // 2) A pushed route (PDP, orders, …) pops normally.
    if (context.canPop()) {
      context.pop();
      return;
    }
    // 3) A tab root other than Home returns to Home rather than exiting.
    if (widget.currentTab != AppTab.home) {
      context.go(AppRoutes.home);
      return;
    }
    // 4) Home root → let the system close the app.
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    // A pushed route (PDP, cart, orders, …) is one the router can pop; on those
    // the app bar already shows a back arrow instead of the hamburger.
    final isPushed = context.canPop();

    // Hand the pop to the framework on a pushed route with the drawer shut.
    // This is what arms the edge-swipe back (CL042-DEV11): the Cupertino back
    // gesture is only installed when the route's popDisposition is `pop`, and a
    // blanket `canPop: false` reports `doNotPop`, which silently disabled the
    // gesture on every screen using this scaffold. The cases `_onBack` exists
    // for — closing the drawer, sending a non-Home tab root back to Home,
    // exiting from Home — all still report false and route through it.
    final deferToFramework = isPushed && !_drawerOpen;

    // The back swipe itself lives in [AppBackSwipe], above the router, so every
    // route gets it — not just the screens using this scaffold. All this owns
    // is the drawer's competing edge-drag.
    return PopScope(
      canPop: deferToFramework,
      onPopInvokedWithResult: _onBack,
      child: Scaffold(
        key: _scaffoldKey,
        appBar: widget.appBar ?? HubAppBar(showSearch: widget.showSearch),
        drawer: const MenuDrawer(),
        onDrawerChanged: (open) {
          if (mounted) setState(() => _drawerOpen = open);
        },
        // Both gestures live in the same ~20px strip and the drawer's wins the
        // arena, so a pushed route would open the menu instead of going back.
        // The hamburger isn't offered there anyway — the drawer stays a
        // tab-root affordance, and the edge belongs to the back gesture.
        drawerEnableOpenDragGesture: !isPushed,
        body: widget.body,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.bottomBar != null) widget.bottomBar!,
            HubBottomNav(current: widget.currentTab),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/offline_state.dart';
import '../../core/address/delivery_location.dart';
import '../routes.dart';
import 'back_swipe.dart';
import 'hub_bottom_nav.dart';

/// Standard chrome for the app's screens: the screen's own app bar (the Figma
/// frames draw a different header per screen, see `HubTopBar`) and the bottom
/// tab bar. The 1st-group screens (splash/welcome/auth) do NOT use this
/// scaffold.
///
/// [showTabBar] is false for the pushed pages whose frames have no tab bar
/// (profile, privacy, help, the product page, track order…): they keep the
/// scaffold's back policy and its [bottomBar] / offline strip, only the five
/// tabs are left out.
///
/// Owns the back policy for its screens (QA): a pushed route pops; a non-Home
/// tab root returns to Home (instead of exiting the app); only Home itself
/// exits. That policy is reached three ways — the Android system back, the
/// app-bar arrow, and the edge swipe — and they all land on the same ladder in
/// [_onBack] or on [BackSwipeDetector].
class HubScaffold extends StatefulWidget {
  const HubScaffold({
    super.key,
    required this.currentTab,
    required this.body,
    this.showSearch = true,
    this.appBar,
    this.bottomBar,
    this.showTabBar = true,
  });

  final AppTab currentTab;
  final Widget body;

  /// Unused: the hamburger app bar this used to configure is gone (pass
  /// [appBar]). Kept until every call site stops passing it.
  final bool showSearch;

  /// The screen's header (null: none — a full-bleed page draws its own).
  final PreferredSizeWidget? appBar;

  /// Optional persistent bar pinned directly above the bottom nav (e.g. the PDP
  /// sticky Add-to-Cart bar). Null on most screens.
  final Widget? bottomBar;

  /// Whether the five-tab bar sits at the bottom.
  final bool showTabBar;

  @override
  State<HubScaffold> createState() => _HubScaffoldState();
}

class _HubScaffoldState extends State<HubScaffold> {
  void _onBack(bool didPop, Object? result) {
    if (didPop) return;
    // 1) A pushed route (PDP, orders, …) pops normally.
    if (context.canPop()) {
      context.pop();
      return;
    }
    // 2) A tab root other than Home returns to Home rather than exiting.
    if (widget.currentTab != AppTab.home) {
      context.go(AppRoutes.home);
      return;
    }
    // 3) Home root → let the system close the app.
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    // A pushed route (PDP, cart, orders, …) is one the router can pop.
    final isPushed = context.canPop();

    // Hand the pop to the framework on a pushed route. This is what arms the
    // edge-swipe back (CL042-DEV11): the Cupertino back gesture is only
    // installed when the route's popDisposition is `pop`, and a blanket
    // `canPop: false` reports `doNotPop`, which silently disabled the gesture on
    // every screen using this scaffold. The cases `_onBack` exists for —
    // sending a non-Home tab root back to Home, exiting from Home — still
    // report false and route through it.
    //
    // The back swipe itself lives in [AppBackSwipe], above the router, so every
    // route gets it — not just the screens using this scaffold.
    return PopScope(
      canPop: isPushed,
      onPopInvokedWithResult: _onBack,
      child: Scaffold(
        appBar: widget.appBar,
        body: widget.showTabBar && widget.currentTab != AppTab.account
            ? Column(
                children: [
                  DeliveryLocationBar(
                    showCartChecks: widget.currentTab == AppTab.cart,
                  ),
                  Expanded(child: widget.body),
                ],
              )
            : widget.body,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.bottomBar != null) widget.bottomBar!,
            // Figma S3: "No internet connection" sits right on the tab bar.
            const OfflineBannerSlot(),
            if (widget.showTabBar) HubBottomNav(current: widget.currentTab),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/config/free_shipping.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../core/widgets/load_failure_view.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../l10n/l10n.dart';
import '../../../marketplace/domain/seller_groups.dart';
import '../../../marketplace/presentation/seller_widgets.dart';
import '../../domain/cart.dart';
import '../cart_controller.dart';
import '../cart_store_credit.dart';
import '../widgets/cart_bars.dart';
import '../widgets/cart_coupon_card.dart';
import '../widgets/cart_empty_view.dart';
import '../widgets/cart_item_tile.dart';
import '../widgets/cart_store_card.dart';
import '../widgets/cart_summary_card.dart';

/// The cart tab (Figma 16, S1): a compact header with the count and "Select",
/// the lines in one card per store with a note that stores ship separately, the
/// coupon, the summary and trust ticks, and a pinned Total / Checkout bar above
/// the tab bar. With nothing in it, the empty state.
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final TextEditingController _coupon = TextEditingController();

  /// "Select" was tapped: the lines show tick boxes and the bar below removes
  /// the ticked ones.
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    // Real-time sync: refetch the (customer) cart on tab entry so an add/remove
    // done on the website (same account) shows without a relogin.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(cartControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  CartController get _controller => ref.read(cartControllerProvider.notifier);

  void _toggleSelecting() => setState(() {
    _selecting = !_selecting;
    _selected.clear();
  });

  void _toggleLine(String uid) => setState(() {
    if (!_selected.remove(uid)) _selected.add(uid);
  });

  void _toggleAll(Cart cart) => setState(() {
    if (_selected.length == cart.items.length) {
      _selected.clear();
    } else {
      _selected
        ..clear()
        ..addAll(cart.items.map((i) => i.uid));
    }
  });

  /// Removes every ticked line, one after the other (the cart answers each with
  /// its new state), then leaves selection mode.
  Future<void> _removeSelected() async {
    final uids = _selected.toList();
    for (final uid in uids) {
      await _controller.removeItem(uid);
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _applyCoupon(AppLocalizations l10n) async {
    if (_coupon.text.trim().isEmpty) return;
    try {
      await _controller.applyCoupon(_coupon.text.trim());
      _coupon.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.cartCouponError)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(cartControllerProvider);
    final cart = state.cart;
    final filled =
        !(state.isLoading && cart.isEmpty) &&
        !(state.error != null && cart.isEmpty) &&
        !cart.isEmpty;
    // A line removed elsewhere is no longer ticked.
    _selected.removeWhere((uid) => !cart.items.any((i) => i.uid == uid));

    return HubScaffold(
      currentTab: AppTab.cart,
      showSearch: false,
      appBar: filled ? _header(l10n, cart) : HubTopBar(title: l10n.cartHeading),
      bottomBar: filled ? _bottomBar(cart) : null,
      body: _body(l10n, state),
    );
  }

  /// Figma 16 "App bar": "My cart" over "4 items · 2 stores", "Select" at the end
  /// — no logo, no search. A cart reached from another page also gets a back
  /// arrow; as a tab root it has none.
  PreferredSizeWidget _header(AppLocalizations l10n, Cart cart) {
    final itemCount = cart.items.fold<int>(0, (sum, i) => sum + i.quantity);
    final groups = groupBySeller<CartItem>(cart.items, (item) => item.seller);
    final storeCount = groups?.where((g) => g.seller != null).length ?? 0;
    final subtitle = _selecting
        ? l10n.cartSelectedCount(_selected.length)
        : storeCount > 0
        ? '${l10n.cartItemCount(itemCount)} · ${l10n.cartStoreCount(storeCount)}'
        : l10n.cartItemCount(itemCount);
    return HubTopBar(
      title: l10n.cartHeading,
      subtitle: subtitle,
      horizontalPadding: 16,
      actions: [
        _HeaderLink(
          label: _selecting ? l10n.actionCancel : l10n.cartSelect,
          onTap: _toggleSelecting,
        ),
      ],
    );
  }

  Widget _bottomBar(Cart cart) {
    if (_selecting) {
      return CartSelectionBar(
        count: _selected.length,
        allSelected: _selected.length == cart.items.length,
        onToggleAll: () => _toggleAll(cart),
        onRemove: _removeSelected,
      );
    }
    return CartCheckoutBar(
      total: cart.totals.grandTotal ?? cart.totals.subtotal,
      onCheckout: () => context.push(AppRoutes.checkout),
    );
  }

  Widget _body(AppLocalizations l10n, CartState state) {
    if (state.isLoading && state.cart.isEmpty) {
      return const _CartSkeleton();
    }
    if (state.error != null && state.cart.isEmpty) {
      // Offline: the S3 page, which reloads by itself once the network is back.
      return LoadFailureView(error: state.error, onRetry: _controller.refresh);
    }
    if (state.cart.isEmpty) {
      return CartEmptyView(
        onStartShopping: () => context.go(AppRoutes.home),
        onViewWishlist: () => context.go(AppRoutes.wishlist),
      );
    }

    final cart = state.cart;
    final groups = groupBySeller<CartItem>(cart.items, (item) => item.seller);
    // Free-shipping threshold comes from the backend (`hmAppConfig.shipping
    // .free_over`, the storefront's cart-rule figure) — never hardcoded. Null
    // while loading, in Build 1, or when the store publishes none, in which
    // case the bar hides and the shipping line reads "calculated at checkout".
    final threshold = ref.watch(freeShippingThresholdProvider).valueOrNull;
    Widget tile(CartItem item) => CartItemTile(
      item: item,
      busy: state.isMutating,
      onChangeQuantity: (q) => _controller.setQuantity(item.uid, q),
      onRemove: () => _controller.removeItem(item.uid),
      selecting: _selecting,
      selected: _selected.contains(item.uid),
      onToggleSelected: () => _toggleLine(item.uid),
    );
    final sections = <Widget>[
      if (cart.totals.subtotal != null && threshold != null)
        CartFreeShippingBar(
          subtotal: cart.totals.subtotal!,
          threshold: threshold,
        ),
      if (groups != null && groups.length > 1) const SplitPackagesNote(),
      ...cartStoreCards<CartItem>(cart.items, (item) => item.seller, tile),
      CartCouponCard(
        controller: _coupon,
        appliedCoupon: cart.totals.appliedCoupon,
        discount: cart.totals.discount,
        busy: state.isMutating,
        onApply: () => _applyCoupon(l10n),
        onRemove: _controller.removeCoupon,
      ),
      CartSummaryCard(
        cart: cart,
        freeShippingThreshold: threshold,
        storeCredit: ref.watch(cartStoreCreditProvider).valueOrNull,
      ),
      const CartTrustTicks(),
    ];
    // A light page of light cards, as the frame draws it, in dark mode too.
    return Theme(
      data: AppTheme.light(Localizations.localeOf(context).languageCode),
      child: ColoredBox(
        color: AppColors.surfaceSubtle,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              sections[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// "Select" / "Cancel" at the end of the header: Body Strong in the accent.
class _HeaderLink extends StatelessWidget {
  const _HeaderLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      // Tall enough for a tap target inside the 56 px bar; the text keeps its
      // place at the bar's 16 px margin.
      padding: const EdgeInsetsDirectional.only(start: 12, top: 14, bottom: 14),
      child: Text(
        label,
        style: AppTextStyles.of(
          context,
        ).bodyStrong.copyWith(color: AppColors.accentStrong),
      ),
    ),
  );
}

/// The cart's first load: the heading and three lines shaped like
/// [CartItemTile], shimmering, in place of a spinner. The lines sit on the
/// scaffold, so the blocks follow the theme instead of glaring in dark mode.
class _CartSkeleton extends StatelessWidget {
  const _CartSkeleton();

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    final base = dark ? Colors.white10 : AppColors.surfaceMuted;
    Widget box({double? width, double height = 12, double radius = 4}) =>
        SkeletonBox(
          width: width,
          height: height,
          borderRadius: radius,
          color: base,
        );
    Widget part(double factor, {double height = 12}) => FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: factor,
      child: box(height: height),
    );
    return Shimmer(
      base: base,
      highlight: dark ? Colors.white24 : Colors.white,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          part(0.4, height: 22),
          const SizedBox(height: 8),
          part(0.2),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  box(width: 72, height: 72, radius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        part(0.9),
                        const SizedBox(height: 8),
                        part(0.55),
                        const SizedBox(height: 12),
                        part(0.35, height: 15),
                        const SizedBox(height: 12),
                        box(width: 88, height: 24, radius: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

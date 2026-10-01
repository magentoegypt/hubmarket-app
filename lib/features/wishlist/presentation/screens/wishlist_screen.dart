import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/store/store_urls.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/hub_icon_button.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../cart/presentation/cart_controller.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../../../catalog/presentation/widgets/product_card.dart';
import '../../domain/wishlist_entry.dart';
import '../wishlist_controller.dart';

/// Wishlist (Figma 25): the Wishlist tab with its own header — back and the
/// title, a share action — then "6 saved items · 3 stores" and the saved
/// products as two columns of product cards (the heart already filled).
///
/// Left out, with nothing behind them: the frame's "Notify on price drops"
/// link and the "PRICE DROP" badge (the wishlist keeps no earlier price and the
/// app has no price alerts). "Add all to bag", which the frame does not draw,
/// takes the link's place at the end of the summary line.
class WishlistScreen extends ConsumerStatefulWidget {
  const WishlistScreen({super.key});

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen> {
  @override
  void initState() {
    super.initState();
    // Real-time sync: refetch on tab entry so a wishlist change made on the
    // website (same account) shows without a relogin.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(authControllerProvider).isAuthenticated) {
        ref.read(wishlistControllerProvider.notifier).refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authControllerProvider);
    final state = ref.watch(wishlistControllerProvider);
    final saved = auth.isAuthenticated && state.entries.isNotEmpty;

    final Widget body;
    if (!auth.isAuthenticated) {
      body = _Prompt(
        title: l10n.wishlistGuestTitle,
        body: l10n.wishlistGuestBody,
        cta: l10n.authSignInTitle,
        onTap: () => context.push(AppRoutes.signIn),
      );
    } else if (state.isLoading && state.entries.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.entries.isEmpty) {
      body = EmptyState(
        icon: HubIcons.heart,
        title: l10n.wishlistEmptyTitle,
        body: l10n.wishlistEmptyBody,
      );
    } else {
      body = CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _Summary(
              entries: state.entries,
              busy: state.isLoading,
              onAddAll: () => _addAll(state.entries, l10n),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            sliver: SliverGrid(
              gridDelegate: productGridDelegate(context),
              delegate: SliverChildBuilderDelegate(
                childCount: state.entries.length,
                (context, index) {
                  final product = state.entries[index].product;
                  return ProductCard(
                    product: product,
                    onTap: () => openProduct(context, product),
                    // Added to the bag → drop it from the wishlist (QA).
                    onAddedToCart: () => ref
                        .read(wishlistControllerProvider.notifier)
                        .removeSkus([product.sku]),
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    return HubScaffold(
      currentTab: AppTab.wishlist,
      showSearch: false,
      // The frame's header: back, the title and share — no hamburger, search
      // or notifications.
      appBar: HubTopBar(
        title: l10n.wishlistTitle,
        showBack: true,
        onBack: () =>
            context.canPop() ? context.pop() : context.go(AppRoutes.home),
        actions: [
          if (saved)
            HubIconButton(
              icon: HubIcons.share2,
              tooltip: l10n.actionShare,
              onPressed: () => _share(state.entries, l10n),
            ),
        ],
      ),
      body: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor, child: body),
    );
  }

  /// Shares the saved products: their names with the links to their pages on
  /// the website.
  Future<void> _share(List<WishlistEntry> entries, AppLocalizations l10n) {
    final store = ref.read(storeControllerProvider);
    final lines = <String>[];
    for (final entry in entries) {
      final url = productUrl(store, entry.product.urlKey);
      lines.add(
        [entry.product.name, if (url != null) url].join('\n'),
      );
    }
    return SharePlus.instance.share(
      ShareParams(text: '${l10n.wishlistShareTitle}\n\n${lines.join('\n\n')}'),
    );
  }

  /// "Add all to Bag": one batched add (was N sequential requests — very slow),
  /// then drop from the wishlist the items that actually landed in the cart.
  /// Configurables needing option selection stay in the wishlist.
  Future<void> _addAll(
    List<WishlistEntry> entries,
    AppLocalizations l10n,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final cart = ref.read(cartControllerProvider.notifier);
    final wishlist = ref.read(wishlistControllerProvider.notifier);
    final skus = [for (final e in entries) e.product.sku];
    try {
      await cart.addManyToCart(skus);
      final inCart = ref
          .read(cartControllerProvider)
          .cart
          .items
          .map((i) => i.sku)
          .toSet();
      await wishlist.removeSkus(skus.where(inCart.contains).toList());
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.cartAdded)));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
      }
    }
  }
}

/// Figma 25 "meta": "6 saved items · 3 stores" (the stores part once the lists
/// name every seller) and, at the end, the "Add all to bag" link in the frame's
/// link style (12 Strong, accent-strong, 14 px icon).
class _Summary extends StatelessWidget {
  const _Summary({
    required this.entries,
    required this.busy,
    required this.onAddAll,
  });

  final List<WishlistEntry> entries;
  final bool busy;
  final VoidCallback onAddAll;

  /// How many stores the saved products come from; null while a product's
  /// seller is not known (HubAppVendors off), where a count would be a guess.
  int? get _stores {
    final stores = <String>{};
    for (final entry in entries) {
      final p = entry.product;
      if (!p.sellerKnown) return null;
      final code = p.sellerCode?.trim() ?? '';
      final name = p.sellerName?.trim() ?? '';
      stores.add(code.isNotEmpty ? code : (name.isNotEmpty ? name : 'hub'));
    }
    return stores.length;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final stores = _stores;
    final summary = [
      l10n.wishlistSavedCount(entries.length),
      if (stores != null) l10n.wishlistStoreCount(stores),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.caption.copyWith(color: context.scaffoldMuted),
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: busy ? null : onAddAll,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  HubIcons.shoppingBag,
                  size: 14,
                  color: busy ? AppColors.disabled : AppColors.accentStrong,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.wishlistAddAll,
                  style: t.captionStrong.copyWith(
                    color: busy ? AppColors.disabled : AppColors.accentStrong,
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

class _Prompt extends StatelessWidget {
  const _Prompt({
    required this.title,
    required this.body,
    required this.cta,
    required this.onTap,
  });

  final String title;
  final String body;
  final String cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: HubIcons.heart,
    title: title,
    body: body,
    action: SizedBox(
      width: double.infinity,
      child: FilledButton(onPressed: onTap, child: Text(cta)),
    ),
  );
}

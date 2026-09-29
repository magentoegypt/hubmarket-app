import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/marketing_footer.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../cart/presentation/cart_controller.dart';
import '../../../catalog/presentation/widgets/product_card.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../../domain/wishlist_entry.dart';
import '../wishlist_controller.dart';

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
      body = _Empty(
        title: l10n.wishlistEmptyTitle,
        body: l10n.wishlistEmptyBody,
      );
    } else {
      body = ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.wishlistHeading,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  l10n.wishlistSavedCount(state.entries.length),
                  style: const TextStyle(color: AppColors.inkMuted),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: state.isLoading
                        ? null
                        : () => _addAll(state.entries, l10n),
                    icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                    label: Text(l10n.wishlistAddAll),
                  ),
                ),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.58,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: state.entries.length,
            itemBuilder: (context, index) {
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
          const MarketingFooter(),
        ],
      );
    }

    return HubScaffold(
      currentTab: AppTab.wishlist,
      showSearch: false,
      // Decluttered header per Figma: back chevron + centered logo, no
      // search/notification icons.
      appBar: AppBar(
        toolbarHeight: 60,
        centerTitle: false,
        titleSpacing: 4,
        leading: HubBackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
        title: const BrandLogo(height: 44),
      ),
      body: body,
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

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 48,
            backgroundColor: AppColors.surfaceTint,
            child: Icon(
              Icons.favorite_border,
              size: 48,
              color: AppColors.brandPrimary,
            ),
          ),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkMuted),
          ),
        ],
      ),
    ),
  );
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 48,
            backgroundColor: AppColors.surfaceTint,
            child: Icon(
              Icons.favorite_border,
              size: 48,
              color: AppColors.brandPrimary,
            ),
          ),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkMuted),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onTap, child: Text(cta)),
          ),
        ],
      ),
    ),
  );
}

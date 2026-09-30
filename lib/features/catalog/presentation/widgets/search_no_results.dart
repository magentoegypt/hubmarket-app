import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../l10n/l10n.dart';
import '../../../stores/presentation/stores_providers.dart';
import '../../domain/product.dart';
import '../product_navigation.dart';
import '../search_providers.dart';
import 'product_card.dart';
import 'search_style.dart';

/// A search that found nothing (Figma S2): the search glyph in a grey disc,
/// "No results for “…”" and a hint.
///
/// With the Hub Market App's API ([storesAvailableProvider]) it also offers
/// "Browse stores" and the "Popular right now" rail — its best sellers
/// (`hmBestSellers`), "View All" opening the whole ranking; without it the
/// page stays as it was.
///
/// Left out of the frame: the "Try" suggestions, as the store's Algolia has
/// no query-suggestions index (autocomplete suggestions are off and
/// `popularQueries` is empty, checked 29 Sep 2026); and the category in
/// "Browse Furniture stores", as a search that found nothing names no
/// category.
class SearchNoResults extends ConsumerWidget {
  const SearchNoResults({super.key, required this.query});

  final String query;

  /// The rail's card, as on Home.
  static const double _cardWidth = 152;
  static const double _railHeight = 292;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final stores = ref.watch(storesAvailableProvider);
    final popular = stores
        ? ref.watch(searchPopularNowProvider).valueOrNull ?? const <Product>[]
        : const <Product>[];
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final display = TextStyle(
      fontFamily: isEn ? AppTheme.displayFont : null,
      fontSize: 22,
      height: 28 / 22,
      fontWeight: FontWeight.w700,
      color: context.scaffoldHeading,
    );
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(top: 24, bottom: 24),
      children: [
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: SearchStyle.pillFill(context),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.search, size: 48, color: context.scaffoldMuted),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l10n.searchNoResultsTitle(isolateQuery(query)),
            textAlign: TextAlign.center,
            style: display,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            stores ? l10n.searchNoResultsBodyStores : l10n.searchNoResultsBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 20 / 14,
              color: context.scaffoldMuted,
            ),
          ),
        ),
        if (stores) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.stores),
              icon: const Icon(Icons.storefront_outlined, size: 20),
              label: Text(l10n.searchBrowseStores),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: context.isDarkMode
                    ? Colors.white
                    : AppColors.brandPrimary,
                side: BorderSide(
                  color: context.isDarkMode
                      ? Colors.white70
                      : AppColors.brandPrimary,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                // From the theme, so the label keeps the app's typeface.
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 15,
                  height: 20 / 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
        if (popular.isNotEmpty) ...[
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: Text(l10n.searchPopularNow, style: display)),
                const SizedBox(width: 8),
                _ViewAll(onTap: () => context.push(AppRoutes.bestSellers)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: _railHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: popular.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => SizedBox(
                width: _cardWidth,
                child: ProductCard(
                  product: popular[i],
                  onTap: () => openProduct(context, popular[i]),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The rail's orange "View All →", as on the Home's section headers.
class _ViewAll extends StatelessWidget {
  const _ViewAll({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context).homeViewAll,
              style: t.bodyStrong.copyWith(color: AppColors.accentStrong),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_forward,
              size: 16,
              color: AppColors.accentStrong,
            ),
          ],
        ),
      ),
    );
  }
}

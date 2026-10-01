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
import '../../../../app/theme/hub_icons.dart';

/// A search that found nothing (Figma S2): the search glyph in a grey disc,
/// "No results for “…”" and a hint.
///
/// The "Try" chips come from the store's Algolia query-suggestions index —
/// the one the website's autocomplete reads ([searchTrySuggestionsProvider]);
/// a chip searches for it ([onTry]). No index, no row: Hub Market's
/// suggestions are off today (checked 30 Sep 2026), so the row appears the
/// day they are switched on in Magento, and nothing is made up meanwhile.
///
/// With the Hub Market App's API ([storesAvailableProvider]) it also offers
/// "Browse stores" and the "Popular right now" rail — its best sellers
/// (`hmBestSellers`), "View All" opening the whole ranking; without it the
/// page stays as it was.
///
/// Left out of the frame: the category in "Browse Furniture stores", as a
/// search that found nothing names no category.
class SearchNoResults extends ConsumerWidget {
  const SearchNoResults({super.key, required this.query, this.onTry});

  final String query;

  /// Searches for a "Try" suggestion; without it the row isn't offered.
  final ValueChanged<String>? onTry;

  /// The rail's card, as on Home.
  static const double _cardWidth = 152;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final stores = ref.watch(storesAvailableProvider);
    final popular = stores
        ? ref.watch(searchPopularNowProvider).valueOrNull ?? const <Product>[]
        : const <Product>[];
    final tries = onTry == null
        ? const <String>[]
        : ref.watch(searchTrySuggestionsProvider(query)).valueOrNull ??
              const <String>[];
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
            child: Icon(HubIcons.search, size: 48, color: context.scaffoldMuted),
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
        if (tries.isNotEmpty) ...[
          const SizedBox(height: 20),
          _TryRow(terms: tries, onTry: onTry!),
        ],
        if (stores) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.stores),
              icon: const Icon(HubIcons.store, size: 20),
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
            height: ProductCardMetrics.heightFor(context, _cardWidth),
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

/// "Try" and the suggested searches as outlined chips, on a light panel
/// (Figma S2).
class _TryRow extends StatelessWidget {
  const _TryRow({required this.terms, required this.onTry});

  final List<String> terms;
  final ValueChanged<String> onTry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: SearchStyle.pillFill(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.searchTryLabel,
              style: TextStyle(fontSize: 12, color: context.scaffoldMuted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final term in terms)
                  ActionChip(
                    label: Text(term),
                    onPressed: () => onTry(term),
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    side: BorderSide(color: context.hairline),
                    shape: const StadiumBorder(),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.scaffoldHeading,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
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
              HubIcons.arrowRight,
              size: 16,
              color: AppColors.accentStrong,
            ),
          ],
        ),
      ),
    );
  }
}

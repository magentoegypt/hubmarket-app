import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../l10n/l10n.dart';
import '../../../home/presentation/home_providers.dart';
import '../../domain/product.dart';
import '../product_navigation.dart';
import 'product_card.dart';
import 'search_style.dart';

/// A search that found nothing (Figma S2): the search glyph in a grey disc,
/// "No results for “…”", a hint, then a "Popular right now" rail.
///
/// The rail reuses Home's Today's Deals — the live special prices, deepest
/// discount first — instead of a query of its own: the store has no
/// best-seller data to rank "popular" by, and Home normally sits under the
/// search route with that list already loaded. Its "View All" is left out
/// because the deals have no listing of their own. The frame's "Try"
/// suggestions and "Browse … stores" button are left out too: Magento's
/// `products.suggestions` comes back empty behind the Algolia adapter, and
/// vendor pages need the public vendor API (Build 2).
class SearchNoResults extends ConsumerWidget {
  const SearchNoResults({super.key, required this.query});

  final String query;

  /// Home's rail geometry: a 152 pt card, so the next one peeks.
  static const double _cardWidth = 152;
  static const double _railHeight = 292;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final popular =
        ref.watch(homeDealsProvider).valueOrNull ?? const <Product>[];
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
            l10n.searchNoResultsBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 20 / 14,
              color: context.scaffoldMuted,
            ),
          ),
        ),
        if (popular.isNotEmpty) ...[
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l10n.searchPopularNow, style: display),
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

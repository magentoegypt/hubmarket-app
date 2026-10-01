import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/presentation/widgets/search_style.dart';
import '../../domain/store.dart';
import '../search_vendors.dart';
import 'store_widgets.dart';
import '../../../../app/theme/hub_icons.dart';

/// The line under a found seller's name: how many of the search's products
/// they sell, or — for a name match the seller facet doesn't count — their
/// product count; then the seller's category when the card carries one
/// ("8 matching products · Furniture").
String searchVendorDetail(AppLocalizations l10n, SearchVendor vendor) {
  final matches = vendor.matchCount;
  final count = matches != null
      ? l10n.searchCategoryMatches(matches)
      : l10n.categoryProductCount(vendor.store.productCount);
  final category = vendor.store.categoryName;
  return category == null ? count : '$count · $category';
}

/// The seller at the head of a search's products (Figma 09c "vendor-match"):
/// logo, name, what matched, its category, and View.
class SearchVendorCard extends StatelessWidget {
  const SearchVendorCard({super.key, required this.vendor});

  final SearchVendor vendor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final store = vendor.store;
    return Material(
      color: SearchStyle.pillFill(context),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openStore(context, store),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              StoreLogo(store: store, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StoreNameLine(
                      name: store.name,
                      markSize: 14,
                      style: TextStyle(
                        fontSize: 14,
                        height: 20 / 14,
                        fontWeight: FontWeight.w600,
                        color: context.scaffoldHeading,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      searchVendorDetail(l10n, vendor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 16 / 12,
                        color: context.scaffoldMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                l10n.searchVendorView,
                style: const TextStyle(
                  fontSize: 12,
                  height: 16 / 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentStrong,
                ),
              ),
              const SizedBox(width: 4),
              // chevron_right mirrors itself in RTL.
              const Icon(
                HubIcons.chevronRight,
                size: 16,
                color: AppColors.accentStrong,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Figma 09c's Vendors tab: the sellers a search found, best first, each
/// opening its store.
class SearchVendorsTab extends StatelessWidget {
  const SearchVendorsTab({
    super.key,
    required this.query,
    required this.vendors,
    this.loading = false,
  });

  final String query;
  final List<SearchVendor> vendors;

  /// Still asking; nothing found yet.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (vendors.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: loading
              ? const CircularProgressIndicator()
              : Text(
                  l10n.searchNoVendorMatches(isolateQuery(query)),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.scaffoldMuted),
                ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: vendors.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final vendor = vendors[i];
        return StoreListTile(
          store: vendor.store,
          detail: searchVendorDetail(l10n, vendor),
          onTap: () => openStore(context, vendor.store),
        );
      },
    );
  }
}

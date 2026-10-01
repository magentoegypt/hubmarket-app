import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/hubapp/hubapp_models.dart';
import '../../../marketplace/domain/seller_groups.dart';
import '../../../marketplace/presentation/seller_widgets.dart';

/// One store's lines as one white card (Figma 16 "store-group"): the store's
/// logo, name and tick, then its lines 14 px apart with a hairline between them.
/// [seller] is null for lines the backend named no seller for — and for the flat
/// cart of a build without HubApp — which get the card without a header.
class CartStoreCard extends StatelessWidget {
  const CartStoreCard({super.key, required this.seller, required this.lines});

  final HmSellerSummary? seller;

  /// The lines, as widgets ([CartItemTile]).
  final List<Widget> lines;

  @override
  Widget build(BuildContext context) {
    final head = seller;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (head != null) ...[
              _StoreHeader(seller: head),
              const SizedBox(height: 14),
            ],
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) ...[
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.borderSubtle,
                ),
                const SizedBox(height: 14),
              ],
              lines[i],
              if (i < lines.length - 1) const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

/// Figma "store-header": a 28 px round logo, the name in Title type and the
/// verified tick; opens the store when it has a page.
class _StoreHeader extends StatelessWidget {
  const _StoreHeader({required this.seller});

  final HmSellerSummary seller;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final row = Row(
      children: [
        SellerLogo(seller: seller),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            seller.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.title.copyWith(color: AppColors.inkHeading),
          ),
        ),
        if (!seller.isMarketplace) ...[
          const SizedBox(width: 8),
          const SellerVerifiedIcon(),
        ],
      ],
    );
    if (seller.storeCode == null) return row;
    return InkWell(
      onTap: () => openSellerStore(context, seller),
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}

/// The groups of a cart's lines for the screen: one [CartStoreCard] per store
/// (HubApp), or one headerless card for everything when no line names a seller.
/// [tile] builds a line's widget.
List<Widget> cartStoreCards<T>(
  List<T> items,
  HmSellerSummary? Function(T item) sellerOf,
  Widget Function(T item) tile,
) {
  final groups = groupBySeller<T>(items, sellerOf);
  if (groups == null) {
    return [
      CartStoreCard(seller: null, lines: [for (final i in items) tile(i)]),
    ];
  }
  return [
    for (final group in groups)
      CartStoreCard(
        seller: group.seller,
        lines: [for (final i in group.items) tile(i)],
      ),
  ];
}

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../l10n/l10n.dart';
import '../domain/product_offer.dart';
import 'seller_widgets.dart';
import '../../../core/widgets/hub_bottom_sheet.dart';

/// What the customer chose in the other-sellers sheet.
@immutable
class OfferChoice {
  /// Open the offer's own product page.
  const OfferChoice.open(this.offer) : add = false;

  /// Put the offer in the cart, as the product page's Add to Cart does.
  const OfferChoice.add(this.offer) : add = true;

  final ProductOffer offer;
  final bool add;
}

/// Figma 14, under "Sold by": "Sold by N other sellers" and "Compare" — the
/// website's price comparison (Vnecoms "select and sell"). The whole row
/// opens [OtherSellersSheet].
class OtherSellersRow extends StatelessWidget {
  const OtherSellersRow({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(12);
    // A white card, light in both themes, like the "Sold by" band above it.
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: AppColors.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.storefront_outlined,
                size: 20,
                color: AppColors.brandPrimary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.pdpOtherSellers(count),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkHeading,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.pdpOtherSellersCompare,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentStrong,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
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

/// The other sellers' offers, cheapest first (the website's table, Figma 14
/// "Other sellers"): each seller with its rating and typical dispatch, the
/// price, and "+" to add it to the cart. Tapping an offer opens its own page;
/// an offer bought with options (a configurable product) opens it from its
/// button too. Pops with the [OfferChoice], or null.
class OtherSellersSheet extends StatelessWidget {
  const OtherSellersSheet({
    super.key,
    required this.count,
    required this.offers,
  });

  final int count;
  final List<ProductOffer> offers;

  static Future<OfferChoice?> show(
    BuildContext context, {
    required int count,
    required List<ProductOffer> offers,
  }) => showHubBottomSheet<OfferChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => OtherSellersSheet(count: count, offers: offers),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
            child: Text(
              l10n.pdpOtherSellers(count),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.inkHeading,
              ),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: offers.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: AppColors.borderDefault,
              ),
              itemBuilder: (context, i) => OfferTile(
                offer: offers[i],
                onOpen: () =>
                    Navigator.of(context).pop(OfferChoice.open(offers[i])),
                onAdd: () =>
                    Navigator.of(context).pop(OfferChoice.add(offers[i])),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One offer (Figma 14 "offer"): the seller's logo, name, ✓ and rating, its
/// typical dispatch, the price (the regular one struck through when lower),
/// and the round "+" — or, for an offer bought with options, a way to its
/// page.
class OfferTile extends StatelessWidget {
  const OfferTile({
    super.key,
    required this.offer,
    required this.onOpen,
    required this.onAdd,
  });

  final ProductOffer offer;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seller = offer.seller;
    final rating = seller.rating;
    final dispatch = offer.dispatchTime;
    final addable = offer.addsDirectly && offer.inStock;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SellerLogo(seller: seller, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          seller.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkHeading,
                          ),
                        ),
                      ),
                      if (!seller.isMarketplace) ...[
                        const SizedBox(width: 4),
                        const SellerVerifiedIcon(size: 13),
                      ],
                    ],
                  ),
                  if (rating != null || dispatch != null) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (rating != null) _Rating(rating: rating),
                        if (dispatch != null)
                          Semantics(
                            label: '${l10n.storeStatDispatch}: ${dispatch.label}',
                            excludeSemantics: true,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.schedule,
                                  size: 12,
                                  color: AppColors.inkMuted,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  dispatch.label,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  offer.price.formatted(),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandPrimary,
                  ),
                ),
                if (offer.isDiscounted)
                  Text(
                    offer.regularPrice!.formatted(),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            addable
                ? _RoundButton(
                    icon: Icons.add,
                    filled: true,
                    label: l10n.offerAddToCart(seller.name),
                    onPressed: onAdd,
                  )
                : _RoundButton(
                    icon: Icons.chevron_right,
                    filled: false,
                    label: l10n.offerChooseOptions(seller.name),
                    onPressed: onOpen,
                  ),
          ],
        ),
      ),
    );
  }
}

/// The 36 pt round button of an offer: navy "+" (Figma), or an outlined
/// chevron to the offer's page.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.filled,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final bool filled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Tooltip(
      message: label,
      child: Material(
        color: filled ? AppColors.brandPrimary : Colors.white,
        shape: CircleBorder(
          side: filled
              ? BorderSide.none
              : const BorderSide(color: AppColors.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              icon,
              size: 20,
              color: filled ? Colors.white : AppColors.brandPrimary,
            ),
          ),
        ),
      ),
    ),
  );
}

/// ★ 4.4 of a seller.
class _Rating extends StatelessWidget {
  const _Rating({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final text = rating.toStringAsFixed(1);
    return Semantics(
      label: AppLocalizations.of(context).sellerRating(text),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 12, color: AppColors.accentGold),
          const SizedBox(width: 2),
          Text(
            text,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

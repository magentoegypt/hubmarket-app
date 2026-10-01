import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/hub_icons.dart';
import '../../../core/widgets/hub_bottom_sheet.dart';
import '../../../l10n/l10n.dart';
import '../../catalog/presentation/widgets/review_widgets.dart';
import '../domain/product_offer.dart';
import 'seller_widgets.dart';

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

/// Figma 14 "Other sellers (price comparison)": the website's price comparison
/// (Vnecoms "select and sell") as a card on the product page — "Sold by N other
/// sellers" and "Compare", then the cheapest offers, each with the seller, its
/// rating, the price and a round "+" to add it. "Compare" opens
/// [OtherSellersSheet] with every offer; an offer's row opens its own page.
class OtherSellersCard extends StatelessWidget {
  const OtherSellersCard({
    super.key,
    required this.count,
    required this.offers,
    required this.onCompare,
    required this.onOpen,
    required this.onAdd,
  });

  /// Offers the card lists itself; the sheet has the rest.
  static const int inlineOffers = 3;

  final int count;
  final List<ProductOffer> offers;
  final VoidCallback onCompare;
  final ValueChanged<ProductOffer> onOpen;
  final ValueChanged<ProductOffer> onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.pdpOtherSellers(count),
                  style: t.title.copyWith(color: AppColors.inkHeading),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onCompare,
                child: Text(
                  l10n.pdpOtherSellersCompare,
                  style: t.captionStrong.copyWith(color: AppColors.accentStrong),
                ),
              ),
            ],
          ),
          // The frame's column puts 6 px between the header and each offer.
          for (final offer in offers.take(inlineOffers)) ...[
            const SizedBox(height: 6),
            OfferTile(
              offer: offer,
              inCard: true,
              onOpen: () => onOpen(offer),
              onAdd: () => onAdd(offer),
            ),
          ],
        ],
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
    final t = AppTextStyles.of(context);
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
              style: t.heading2.copyWith(color: AppColors.inkHeading),
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
                color: AppColors.borderSubtle,
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

/// One offer (Figma 14 "offer"): the seller's 36 px logo, its name with the ✓
/// and its rating — five stars and the figure — with its typical dispatch, the
/// price (the regular one struck through under it when lower), and the round
/// navy "+" — or, for an offer bought with options, a way to its page.
///
/// [inCard] sets it as a row of the product page's card: a hairline above it and
/// 10 px above and below; in the sheet it is padded 16 × 12.
class OfferTile extends StatelessWidget {
  const OfferTile({
    super.key,
    required this.offer,
    required this.onOpen,
    required this.onAdd,
    this.inCard = false,
  });

  final ProductOffer offer;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  final bool inCard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final seller = offer.seller;
    final rating = seller.rating;
    final dispatch = offer.dispatchTime;
    final addable = offer.addsDirectly && offer.inStock;
    final row = Padding(
      padding: inCard
          ? const EdgeInsets.symmetric(vertical: 10)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SellerLogo(seller: seller, size: 36),
          const SizedBox(width: 10),
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
                        style: t.bodyStrong.copyWith(
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
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (rating != null)
                        Semantics(
                          label: l10n.sellerRating(rating.toStringAsFixed(1)),
                          excludeSemantics: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ReviewStars(stars: rating.round(), size: 12),
                              const SizedBox(width: 4),
                              Text(
                                rating.toStringAsFixed(1),
                                textDirection: TextDirection.ltr,
                                style: t.caption.copyWith(
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (dispatch != null)
                        Semantics(
                          label: '${l10n.storeStatDispatch}: ${dispatch.label}',
                          excludeSemantics: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                HubIcons.clock,
                                size: 12,
                                color: AppColors.inkMuted,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                dispatch.label,
                                style: t.caption.copyWith(
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
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                offer.price.formatted(),
                textDirection: TextDirection.ltr,
                style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
              ),
              if (offer.isDiscounted)
                Text(
                  offer.regularPrice!.formatted(),
                  textDirection: TextDirection.ltr,
                  style: t.caption.copyWith(
                    color: AppColors.inkMuted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          addable
              ? _RoundButton(
                  icon: HubIcons.plus,
                  filled: true,
                  label: l10n.offerAddToCart(seller.name),
                  onPressed: onAdd,
                )
              : _RoundButton(
                  icon: HubIcons.chevronRight,
                  filled: false,
                  label: l10n.offerChooseOptions(seller.name),
                  onPressed: onOpen,
                ),
        ],
      ),
    );
    return InkWell(
      onTap: onOpen,
      child: inCard
          // A Container, not a DecoratedBox: the hairline adds its 1 px to the
          // row's height, as the frame's "border-t" does.
          ? Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderSubtle)),
              ),
              child: row,
            )
          : row,
    );
  }
}

/// The 36 pt round button of an offer: navy "+" (Figma, an 18 px glyph), or an
/// outlined chevron to the offer's page.
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
              size: 18,
              color: filled ? Colors.white : AppColors.brandPrimary,
            ),
          ),
        ),
      ),
    ),
  );
}

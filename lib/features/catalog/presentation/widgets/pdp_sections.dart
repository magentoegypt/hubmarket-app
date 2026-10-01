import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/util/image_prefetch.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../home/domain/home_content.dart';
import '../../../home/presentation/widgets/hm_cms_sections.dart';
import '../../domain/product.dart';
import '../../domain/product_detail.dart';
import '../product_navigation.dart';
import 'product_card.dart';
import 'review_widgets.dart';

/// The building blocks of the product page (Figma 14), top to bottom. Each takes
/// what it draws and nothing else; `ProductDetailScreen` composes them and owns
/// the state (the chosen options, the quantity).

/// Figma "rating": five stars, the average, "27 reviews" (a link to the Reviews
/// screen) and "In stock" — separated by a 6 px gap and a "·". A product nobody
/// reviewed shows only its stock line: no stars are made up.
class PdpRatingRow extends StatelessWidget {
  const PdpRatingRow({
    super.key,
    required this.ratingSummary,
    required this.reviewCount,
    required this.inStock,
    required this.onReviews,
  });

  /// 0–100 (Magento `rating_summary`).
  final int ratingSummary;
  final int reviewCount;
  final bool inStock;
  final VoidCallback onReviews;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final average = ratingSummary / 20;
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (reviewCount > 0) ...[
          ReviewStars(stars: average.round(), size: 14),
          Text(
            average.toStringAsFixed(1),
            style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
          ),
          InkWell(
            onTap: onReviews,
            child: Text(
              l10n.reviewsCount(reviewCount),
              style: t.body.copyWith(color: AppColors.info),
            ),
          ),
          Text('·', style: t.body.copyWith(color: AppColors.inkMuted)),
        ],
        Text(
          inStock ? l10n.pdpInStock : l10n.productOutOfStock,
          style: t.bodyStrong.copyWith(
            color: inStock ? AppColors.successStrong : AppColors.danger,
          ),
        ),
      ],
    );
  }
}

/// Figma "price": the price in Price Large and "Inclusive of VAT" in Caption,
/// on one baseline 10 px apart. On a sale the price turns `price/sale` orange
/// and the regular one follows it, struck through, as on the product card.
class PdpPriceRow extends StatelessWidget {
  const PdpPriceRow({
    super.key,
    required this.price,
    this.regularPrice,
    this.showSale = false,
  });

  final String price;

  /// The price before the discount, formatted.
  final String? regularPrice;
  final bool showSale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final onSale = showSale && regularPrice != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          price,
          textDirection: TextDirection.ltr,
          style: t.priceLarge.copyWith(
            color: onSale ? AppColors.accentStrong : AppColors.inkHeading,
          ),
        ),
        if (onSale) ...[
          const SizedBox(width: 8),
          Text(
            regularPrice!,
            textDirection: TextDirection.ltr,
            style: t.body.copyWith(
              color: AppColors.inkMuted,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ],
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            l10n.pdpInclusiveVat,
            style: t.caption.copyWith(color: AppColors.inkMuted),
          ),
        ),
      ],
    );
  }
}

/// A swatch's `swatch_data.value` as a colour — a `#RGB` / `#RRGGBB` hex only.
/// Text swatches (a size's "M") and anything else are not colours.
Color? swatchColorOf(String? value) {
  if (value == null) return null;
  final match = RegExp(
    r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  var hex = match.group(1)!;
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

/// Figma "option/color" and "option/size": the option's name and the chosen
/// value ("Colour: Beige floral"), then its values — round swatches when every
/// value is a colour, 40 px chips otherwise. A value no variant in stock has
/// (given what the other options picked) is drawn disabled but stays choosable,
/// so the buy bar can say it is out of stock.
class PdpOptionPicker extends StatelessWidget {
  const PdpOptionPicker({
    super.key,
    required this.option,
    required this.selectedValue,
    required this.onSelect,
    this.isAvailable,
  });

  final ConfigurableOption option;
  final int? selectedValue;
  final ValueChanged<int> onSelect;

  /// Whether a value can be bought; null treats every value as available.
  final bool Function(SwatchValue value)? isAvailable;

  bool get _swatches =>
      option.values.isNotEmpty &&
      option.values.every((v) => swatchColorOf(v.swatchColor) != null);

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final chosen = option.values
        .where((v) => v.valueIndex == selectedValue)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${option.label}:',
                style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
              ),
              if (chosen != null)
                TextSpan(
                  text: '  ${chosen.label}',
                  style: t.body.copyWith(color: AppColors.inkMuted),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_swatches)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final value in option.values)
                _Swatch(
                  key: ValueKey('pdp-option-${option.attributeCode}-${value.valueIndex}'),
                  value: value,
                  selected: value.valueIndex == selectedValue,
                  available: isAvailable?.call(value) ?? true,
                  onTap: () => onSelect(value.valueIndex),
                ),
            ],
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in option.values)
                _SizeChip(
                  key: ValueKey('pdp-option-${option.attributeCode}-${value.valueIndex}'),
                  value: value,
                  selected: value.valueIndex == selectedValue,
                  available: isAvailable?.call(value) ?? true,
                  onTap: () => onSelect(value.valueIndex),
                ),
            ],
          ),
      ],
    );
  }
}

/// A colour: a 28 px disc in a 36 px ring — 2 px navy when chosen, 1 px
/// `border/subtle` otherwise.
class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.value,
    required this.selected,
    required this.available,
    required this.onTap,
  });

  final SwatchValue value;
  final bool selected;
  final bool available;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: value.label,
    child: InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.brandPrimary : AppColors.borderSubtle,
            width: selected ? 2 : 1,
          ),
        ),
        child: Opacity(
          opacity: available ? 1 : 0.4,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: swatchColorOf(value.swatchColor),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    ),
  );
}

/// A size (or any text value): a 52 px-wide, 40 px chip with radius 10 — white
/// with a `border/strong` outline, navy with a white label once chosen, the
/// label `disabled` when out of stock.
class _SizeChip extends StatelessWidget {
  const _SizeChip({
    super.key,
    required this.value,
    required this.selected,
    required this.available,
    required this.onTap,
  });

  final SwatchValue value;
  final bool selected;
  final bool available;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final ink = selected
        ? Colors.white
        : available
        ? AppColors.inkHeading
        : AppColors.disabled;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.brandPrimary : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: selected
              ? BorderSide.none
              : const BorderSide(color: AppColors.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 52, minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            // A shrink-wrapped, centred label: a Container with an alignment
            // would stretch the chip across the whole row.
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                value.label,
                textAlign: TextAlign.center,
                style: t.bodyStrong.copyWith(color: ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma "icon/alert" + Caption Strong in `warning`: "Only 3 left in size M".
class PdpLowStockLine extends StatelessWidget {
  const PdpLowStockLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(HubIcons.triangleAlert, size: 14, color: AppColors.warning),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          text,
          style: AppTextStyles.of(
            context,
          ).captionStrong.copyWith(color: AppColors.warning),
        ),
      ),
    ],
  );
}

/// Figma "delivery" (the grey card under the offers): the store's delivery and
/// returns promises, two rows of a white 36 px tile with the glyph, a Body
/// Strong title and a Caption line, a hairline between. They come from the
/// storefront's CMS block `hm_home_trust` (Content › Blocks), the same one the
/// Home shows, so marketing edits them once: the items about delivery and
/// returns are the ones taken. The frame's "Delivery by Thu, 2 Oct" would need
/// a delivery estimate the backend has none of. Hidden when the block has
/// neither (or can't be read).
class PdpTrustRow extends StatelessWidget {
  const PdpTrustRow({super.key, required this.rows});

  /// The glyph, title and caption of each row — see [rowsOf].
  final List<(IconData, String, String)> rows;

  /// What the card says: the delivery and returns items of the trust block
  /// ([homeTrustProvider]), whose glyph (picked from the item's words by
  /// `HmTrustGrid.iconFor`) is a truck or a returns arrow.
  static List<(IconData, String, String)> rowsOf(List<TrustItem> items) {
    final rows = <(IconData, String, String)>[];
    for (var i = 0; i < items.length; i++) {
      final icon = HmTrustGrid.iconFor(items[i], i);
      if (icon == HubIcons.truck || icon == HubIcons.rotateCcw) {
        rows.add((icon, items[i].title, items[i].text));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final t = AppTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.borderSubtle),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      rows[i].$1,
                      size: 20,
                      color: AppColors.brandPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].$2,
                          style: t.bodyStrong.copyWith(
                            color: AppColors.inkHeading,
                          ),
                        ),
                        if (rows[i].$3.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            rows[i].$3,
                            style: t.caption.copyWith(
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Figma "description": a section header — Title and a chevron — that opens its
/// [child] under it. [topRule] draws the hairline above, as the Description row
/// does; [initiallyOpen] says which state it starts in.
///
/// The chevron stays a "down" one: the frame draws "Specifications" open with
/// the same chevron as the closed "Description & material".
class PdpAccordion extends StatefulWidget {
  const PdpAccordion({
    super.key,
    required this.title,
    required this.child,
    this.initiallyOpen = false,
    this.topRule = false,
    this.chevronSize = 20,
    this.chevronColor = AppColors.inkHeading,
    this.verticalPadding = 14,
  });

  final String title;
  final Widget child;
  final bool initiallyOpen;
  final bool topRule;
  final double chevronSize;
  final Color chevronColor;
  final double verticalPadding;

  @override
  State<PdpAccordion> createState() => _PdpAccordionState();
}

class _PdpAccordionState extends State<PdpAccordion> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: widget.verticalPadding),
              decoration: widget.topRule
                  ? const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.borderSubtle),
                      ),
                    )
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: t.title.copyWith(color: AppColors.inkHeading),
                    ),
                  ),
                  Icon(
                    HubIcons.chevronDown,
                    size: widget.chevronSize,
                    color: widget.chevronColor,
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: AlignmentDirectional.topStart,
          child: _open ? widget.child : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Figma "specifications" rows: a Caption label (muted) and a Caption Strong
/// value at the end, 8 px above and below, a hairline between the rows.
class PdpSpecRows extends StatelessWidget {
  const PdpSpecRows({super.key, required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          // The frame's column puts 4 px between the rows, hairline included.
          if (i > 0) const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: i == rows.length - 1
                  ? null
                  : const Border(
                      bottom: BorderSide(color: AppColors.borderSubtle),
                    ),
            ),
            child: Row(
              children: [
                Flexible(
                  flex: 0,
                  child: Text(
                    rows[i].$1,
                    style: t.caption.copyWith(color: AppColors.inkMuted),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    rows[i].$2,
                    textAlign: TextAlign.end,
                    style: t.captionStrong.copyWith(color: AppColors.inkHeading),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A body paragraph of the description accordion: Body in `muted`, as the
/// bundle page's description is.
class PdpParagraph extends StatelessWidget {
  const PdpParagraph(this.text, {super.key, this.top = 0});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 14),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: AppTextStyles.of(
          context,
        ).body.copyWith(color: AppColors.inkMuted),
      ),
    ),
  );
}

/// Figma "Ratings & reviews": the title with "See all 27", the summary — the
/// average in Display, its stars, the count, and the per-star bars when every
/// review is in hand — then the newest review in a muted card and "Write a
/// review". A product with no reviews says so, and still invites the first one.
class PdpReviewsSection extends StatelessWidget {
  const PdpReviewsSection({
    super.key,
    required this.product,
    required this.onSeeAll,
    required this.onWrite,
  });

  final ProductDetail product;
  final VoidCallback onSeeAll;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final average = product.ratingSummary / 20;
    final newest = product.reviews.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.pdpRatingsReviews,
                style: t.heading2.copyWith(color: AppColors.inkHeading),
              ),
            ),
            if (product.hasReviews)
              InkWell(
                onTap: onSeeAll,
                child: Text(
                  l10n.reviewsSeeAll(product.reviewCount),
                  style: t.bodyStrong.copyWith(color: AppColors.accentStrong),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (product.hasReviews) ...[
          Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    average.toStringAsFixed(1),
                    style: t.display.copyWith(color: AppColors.inkHeading),
                  ),
                  const SizedBox(height: 2),
                  ReviewStars(stars: average.round(), size: 12),
                  const SizedBox(height: 2),
                  Text(
                    l10n.reviewsCount(product.reviewCount),
                    style: t.caption.copyWith(color: AppColors.inkMuted),
                  ),
                ],
              ),
              if (product.ratingHistogram.isNotEmpty) ...[
                const SizedBox(width: 16),
                Expanded(child: PdpRatingBars(bars: product.ratingHistogram)),
              ],
            ],
          ),
          if (newest != null) ...[
            const SizedBox(height: 12),
            PdpTopReview(review: newest),
          ],
        ] else ...[
          Text(
            l10n.reviewsEmptyTitle,
            style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.reviewsEmptyBody,
            style: t.body.copyWith(color: AppColors.inkMuted),
          ),
        ],
        const SizedBox(height: 12),
        HubButton(
          label: l10n.reviewsWrite,
          icon: HubIcons.pencil,
          style: HubButtonStyle.outline,
          onPressed: onWrite,
        ),
      ],
    );
  }
}

/// The per-star bars of the product page: the digit in Micro, a 6 px track on
/// `bg/muted` and the `rating-star` fill, five rows 4 px apart. Counted from the
/// reviews in hand, only when they are all of them ([RatingBar.exactHistogram]).
class PdpRatingBars extends StatelessWidget {
  const PdpRatingBars({super.key, required this.bars});

  final List<RatingBar> bars;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final byStar = {for (final b in bars) b.stars: b};
    return Column(
      children: [
        for (var star = 5; star >= 1; star--) ...[
          if (star < 5) const SizedBox(height: 4),
          SizedBox(
            height: 14,
            child: Row(
              children: [
                Text(
                  '$star',
                  style: t.micro.copyWith(color: AppColors.inkMuted),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (byStar[star]?.percent ?? 0) / 100,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceSubtle,
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.ratingStar,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Figma "top-review": the newest review on `bg/muted` — its stars, the reviewer
/// and the text. (The frame's "Verified purchase" needs a flag core reviews do
/// not carry.)
class PdpTopReview extends StatelessWidget {
  const PdpTopReview({super.key, required this.review});

  final ProductReview review;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final summary = review.summary.trim();
    final text = review.text.trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReviewStars(stars: review.stars, size: 11),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  review.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.captionStrong.copyWith(color: AppColors.inkHeading),
                ),
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              summary,
              style: t.captionStrong.copyWith(color: AppColors.inkHeading),
            ),
          ],
          if (text.isNotEmpty) ...[
            SizedBox(height: summary.isEmpty ? 6 : 2),
            Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: t.caption.copyWith(color: AppColors.inkSubtle),
            ),
          ],
        ],
      ),
    );
  }
}

/// Figma "Looking similar": the title with "See all" (to the product's
/// category, when it has one) and a rail of product cards, 171 wide, 12 apart.
/// Driven by the product's core related + up-sell links; hidden when there are
/// none.
class PdpSimilarRail extends StatefulWidget {
  const PdpSimilarRail({super.key, required this.products, this.onSeeAll});

  final List<Product> products;

  /// Null hides "See all".
  final VoidCallback? onSeeAll;

  static const double cardWidth = 171;

  @override
  State<PdpSimilarRail> createState() => _PdpSimilarRailState();
}

class _PdpSimilarRailState extends State<PdpSimilarRail> {
  @override
  void initState() {
    super.initState();
    // After the frame, so warming the rail never races the hero image the
    // user is actually looking at. Only the cards in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        prefetchImages(
          context,
          widget.products.map((p) => p.imageUrl),
          decodeWidth: HubImage.decodePixels(context, PdpSimilarRail.cardWidth),
          limit: 4,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.products;
    if (products.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.pdpLookingSimilar,
                  style: t.heading2.copyWith(color: AppColors.inkHeading),
                ),
              ),
              if (widget.onSeeAll != null)
                InkWell(
                  onTap: widget.onSeeAll,
                  child: Text(
                    l10n.homeSeeAll,
                    style: t.bodyStrong.copyWith(color: AppColors.accentStrong),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: ProductCardMetrics.heightFor(context, PdpSimilarRail.cardWidth),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: PdpSimilarRail.cardWidth,
              child: ProductCard(
                product: products[i],
                onTap: () => openProduct(context, products[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

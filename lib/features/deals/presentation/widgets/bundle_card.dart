import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/deals.dart';
import '../../../../app/theme/hub_icons.dart';

/// Opens a bundle's product page, where its options are chosen and it goes
/// into the cart (a bundle can't be added by SKU alone).
void openBundle(BuildContext context, BundleDeal deal) =>
    context.push(AppRoutes.product(deal.urlKey));

/// The Home's bundle card (Figma 07 "bundle/…"): 300 pt wide — image with the
/// discount, saving and item-count badges, seller, name, excerpt, child
/// thumbnails, price with the saving, "Add Bundle".
class BundleRailCard extends StatelessWidget {
  const BundleRailCard({super.key, required this.deal});

  final BundleDeal deal;

  static const double width = 300;

  /// The card's height in English at 1× text: 1 pt border, the 150 pt photo,
  /// and the 238 pt body (14 | seller 16 · name 22 · line 16 · thumbs 44 ·
  /// price 20 · button 52, 8 apart | 14).
  static const double height = 390;

  /// The card's height for the language and text size of [context]: [height]
  /// in English, 398 in Arabic (taller lines), so the body keeps its 8 pt
  /// between the rows.
  static double heightFor(BuildContext context) {
    final t = AppTextStyles.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle style) =>
        scaler.scale(style.fontSize! * style.height!);
    return 2 + // the border
        150 +
        14 +
        line(t.captionStrong) +
        8 +
        line(t.title) +
        8 +
        line(t.caption) +
        8 +
        44 +
        8 +
        line(t.button) +
        8 +
        52 +
        14;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openBundle(context, deal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 150,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    HubImage(
                      url: deal.imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (_) => const ColoredBox(color: Colors.white),
                    ),
                    PositionedDirectional(
                      top: 10,
                      start: 10,
                      child: Row(
                        children: [
                          if (deal.hasSaving) ...[
                            BundleBadge(
                              label: l10n.bundleCardDiscount(
                                deal.discountPercent,
                              ),
                              color: AppColors.accentSale,
                            ),
                            const SizedBox(width: 6),
                            BundleBadge(
                              label: l10n.bundleCardSave(
                                deal.saving!.formatted(),
                              ),
                              color: AppColors.successStrong,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (deal.itemCount > 0)
                      PositionedDirectional(
                        top: 10,
                        end: 10,
                        child: _ItemCountPill(count: deal.itemCount),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (deal.seller != null) ...[
                        Text(
                          deal.seller!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.captionStrong.copyWith(
                            color: AppColors.info,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        deal.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.title.copyWith(color: AppColors.inkHeading),
                      ),
                      if (deal.description != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          deal.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption.copyWith(color: AppColors.inkMuted),
                        ),
                      ],
                      const Spacer(),
                      if (deal.thumbnails.isNotEmpty) ...[
                        BundleThumbnails(deal: deal),
                        const SizedBox(height: 8),
                      ],
                      BundlePriceRow(deal: deal),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => openBundle(context, deal),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brandPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: t.button,
                          ),
                          child: Text(l10n.bundleAdd),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A red / green bundle badge.
class BundleBadge extends StatelessWidget {
  const BundleBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: AppTextStyles.of(context).micro.copyWith(color: Colors.white),
    ),
  );
}

class _ItemCountPill extends StatelessWidget {
  const _ItemCountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.borderSubtle),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          HubIcons.package,
          size: 12,
          color: Color(0xFF535D70),
        ),
        const SizedBox(width: 4),
        Text(
          AppLocalizations.of(context).bundleItemCount(count),
          style: AppTextStyles.of(
            context,
          ).micro.copyWith(color: const Color(0xFF535D70)),
        ),
      ],
    ),
  );
}

/// Up to four child thumbnails, then "+N" for the rest.
class BundleThumbnails extends StatelessWidget {
  const BundleThumbnails({super.key, required this.deal, this.size = 44});

  final BundleDeal deal;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Row(
      children: [
        for (final (i, url) in deal.thumbnails.take(4).indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            clipBehavior: Clip.antiAlias,
            child: HubImage(url: url, fit: BoxFit.contain, width: size),
          ),
        ],
        if (deal.moreThumbnails > 0) ...[
          const SizedBox(width: 6),
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '+${deal.moreThumbnails}',
              style: t.captionStrong.copyWith(color: const Color(0xFF535D70)),
            ),
          ),
        ],
      ],
    );
  }
}

/// Price (or "From …"), the struck regular total, and "You save …".
class BundlePriceRow extends StatelessWidget {
  const BundlePriceRow({
    super.key,
    required this.deal,
    this.compactSaving = false,
  });

  final BundleDeal deal;

  /// The 10c list: "Save AED 11" instead of "You save AED 11", and the price
  /// in ink rather than the sale orange (as the frames draw them).
  final bool compactSaving;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final l10n = AppLocalizations.of(context);
    final price = deal.price.formatted();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          deal.priceIsFrom ? l10n.bundleFromPrice(price) : price,
          style: t.button.copyWith(
            color: deal.hasSaving && !compactSaving
                ? AppColors.accentStrong
                : AppColors.inkHeading,
          ),
        ),
        if (deal.hasSaving && deal.regularTotal != null) ...[
          const SizedBox(width: 8),
          Text(
            deal.regularTotal!.formatted(),
            style: t.caption.copyWith(
              color: AppColors.inkMuted,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: deal.hasSaving
              ? Text(
                  compactSaving
                      ? l10n.bundleCardSave(deal.saving!.formatted())
                      : l10n.bundleYouSave(deal.saving!.formatted()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: t.captionStrong.copyWith(
                    color: AppColors.successStrong,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

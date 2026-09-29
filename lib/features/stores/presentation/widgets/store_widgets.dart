import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/hubapp/hubapp.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/presentation/widgets/search_style.dart';
import '../../domain/store.dart';

/// Opens [store]'s page, handing over the card so the header paints at once.
void openStore(BuildContext context, HmStoreCard store) =>
    context.push(AppRoutes.store(store.code), extra: store);

/// A seller's round logo on white (Figma "logo"). A seller without a logo
/// gets its initial in a tinted disc — the website's avatar fallback.
class StoreLogo extends StatelessWidget {
  const StoreLogo({
    super.key,
    required this.store,
    required this.size,
    this.borderWidth = 1,
    this.borderColor = AppColors.borderSubtle,
    this.shadow = false,
  });

  final HmStoreCard store;
  final double size;
  final double borderWidth;
  final Color borderColor;

  /// The store page's floating logo casts a soft shadow.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final url = store.logoUrl ?? '';
    final inner = size - borderWidth * 2;
    Widget initial(BuildContext _) => ColoredBox(
      color: AppColors.surfaceTint,
      child: Center(
        child: Text(
          store.initial,
          style: TextStyle(
            fontSize: inner * 0.42,
            fontWeight: FontWeight.w700,
            color: AppColors.brandPrimary,
          ),
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: borderWidth > 0
            ? Border.all(color: borderColor, width: borderWidth)
            : null,
        boxShadow: shadow
            ? const [
                BoxShadow(
                  color: Color(0x1A0F2145),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: SizedBox(
          width: inner,
          height: inner,
          child: url.isEmpty
              ? initial(context)
              : HubImage(
                  url: url,
                  fit: BoxFit.contain,
                  width: inner,
                  height: inner,
                  placeholder: (_) => const ColoredBox(color: Colors.white),
                  error: initial,
                ),
        ),
      ),
    );
  }
}

/// The blue verified mark after a seller's name. Every seller the app lists
/// is approved, which is what the website's VERIFIED mark stands for.
class VerifiedMark extends StatelessWidget {
  const VerifiedMark({super.key, this.size = 16, this.color = AppColors.info});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Icon(
    Icons.verified_outlined,
    size: size,
    color: color,
    semanticLabel: AppLocalizations.of(context).storeVerified,
  );
}

/// A seller's name with the verified mark, ellipsised before the mark.
class StoreNameLine extends StatelessWidget {
  const StoreNameLine({
    super.key,
    required this.name,
    required this.style,
    this.markSize = 16,
    this.markColor = AppColors.info,
    this.gap = 4,
  });

  final String name;
  final TextStyle style;
  final double markSize;
  final Color markColor;
  final double gap;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
      SizedBox(width: gap),
      VerifiedMark(size: markSize, color: markColor),
    ],
  );
}

/// "★ 4.8 (126 reviews)", or "No reviews yet" for an unrated seller.
class StoreRatingLine extends StatelessWidget {
  const StoreRatingLine({super.key, required this.store});

  final HmStoreCard store;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const muted = TextStyle(
      fontSize: 12,
      height: 16 / 12,
      color: AppColors.inkMuted,
    );
    if (!store.isRated) return Text(l10n.storeNoReviews, style: muted);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 14, color: AppColors.accentGold),
        const SizedBox(width: 4),
        Text(
          formatStoreRating(store.rating!),
          style: const TextStyle(
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w600,
            color: AppColors.inkHeading,
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '(${l10n.storeReviewCount(store.reviewCount)})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ),
      ],
    );
  }
}

/// A rating out of 5 with one decimal, Western digits in both languages.
String formatStoreRating(double rating) => rating.toStringAsFixed(1);

/// "4.8 ★" — or "★ 4.8" with [starFirst] — with the star drawn as an icon, so
/// it shows whatever the font (Tajawal and DM Sans have no ★).
InlineSpan ratingSpan(
  double rating, {
  required double size,
  required Color color,
  bool starFirst = false,
}) {
  final star = WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Icon(Icons.star_rounded, size: size, color: color),
  );
  final value = TextSpan(text: formatStoreRating(rating));
  return TextSpan(
    children: starFirst
        ? [star, const TextSpan(text: ' '), value]
        : [value, const TextSpan(text: ' '), star],
  );
}

/// A 36 pt pill (Figma "Chip"): navy when [selected], outlined otherwise.
/// As wide as its label, in a row or a wrap.
class StorePill extends StatelessWidget {
  const StorePill({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(
      side: selected
          ? BorderSide.none
          : BorderSide(color: SearchStyle.chipBorder(context)),
    );
    return Material(
      color: selected
          ? AppColors.brandPrimary
          : (context.isDarkMode ? Colors.transparent : Colors.white),
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                height: 20 / 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : context.scaffoldHeading,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One seller in a list (Figma 12 "Store card", and 09c's Vendors tab): logo,
/// name with the verified mark, a detail line, the rating, a chevron. White
/// in both themes, like the product cards.
class StoreListTile extends StatelessWidget {
  const StoreListTile({
    super.key,
    required this.store,
    required this.detail,
    required this.onTap,
  });

  final HmStoreCard store;

  /// The line under the name — the product count, or how many of a search's
  /// products the seller sells.
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.borderSubtle),
      borderRadius: BorderRadius.circular(16),
    );
    return Material(
      color: Colors.white,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              StoreLogo(store: store, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StoreNameLine(
                      name: store.name,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 22 / 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkHeading,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 16 / 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    StoreRatingLine(store: store),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // chevron_right mirrors itself in RTL.
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A loading stand-in shaped like [StoreListTile].
class StoreListTileSkeleton extends StatelessWidget {
  const StoreListTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 84,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.borderSubtle),
      borderRadius: BorderRadius.circular(16),
    ),
    padding: const EdgeInsets.all(12),
    child: const Shimmer(
      child: Row(
        children: [
          SkeletonBox.circle(size: 56),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: SkeletonBox(height: 14, borderRadius: 4),
                ),
                SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: 0.35,
                  child: SkeletonBox(height: 10, borderRadius: 4),
                ),
                SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: 0.45,
                  child: SkeletonBox(height: 10, borderRadius: 4),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

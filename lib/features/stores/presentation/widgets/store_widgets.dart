import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/hubapp/hubapp.dart';
import '../../../../core/widgets/hub_chip.dart';
import '../../../../core/widgets/hub_icon_button.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/presentation/widgets/search_style.dart';
import '../../domain/store.dart';

/// Opens [store]'s page, handing over the card so the header paints at once.
void openStore(BuildContext context, HmStoreCard store) =>
    context.push(AppRoutes.store(store.code), extra: store);

/// A count with Western digits and grouping ("1,240").
String storeCount(int value) =>
    NumberFormat.decimalPattern('en_US').format(value);

/// A seller card's detail line: its category, when the list carries one,
/// before [detail] ("Furniture · 38 products").
String storeCardDetail(HmStoreCard store, String detail) {
  final category = store.categoryName;
  return category == null ? detail : '$category · $detail';
}

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
    HubIcons.badgeCheck,
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
    final t = AppTextStyles.of(context);
    final muted = t.caption.copyWith(color: AppColors.inkMuted);
    if (!store.isRated) return Text(l10n.storeNoReviews, style: muted);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 12, color: AppColors.ratingStar),
        const SizedBox(width: 4),
        Text(
          formatStoreRating(store.rating!),
          style: t.captionStrong.copyWith(color: AppColors.inkHeading),
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

/// A 36 pt pill (Figma "Chip"): navy when [selected], outlined otherwise —
/// `HubChip`. [semanticLabel] reads out what the label alone doesn't ("Furniture,
/// 3 stores").
class StorePill extends StatelessWidget {
  const StorePill({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final chip = HubChip(label: label, selected: selected, onTap: onTap);
    final spoken = semanticLabel;
    if (spoken == null) return chip;
    return Semantics(
      label: spoken,
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: chip,
    );
  }
}

/// The grey search field of the stores pages (Figma 12 "search", 13
/// "store-search"): [height] px, radius 12, `muted` fill and no outline, an
/// 18 px search icon 14 px in and 10 before the text, a clear button once typed
/// in, and [trailing] (the store page's filter action) at the end.
class StoreSearchField extends StatelessWidget {
  const StoreSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    this.focusNode,
    this.onSubmitted,
    this.trailing,
    this.height = 44,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback onClear;
  final Widget? trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final muted = context.scaffoldMuted;
    const none = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide.none,
    );
    // The text line is 20 px high (22 in Arabic); the rest of [height] is the
    // padding around it.
    final pad = (height - t.body.fontSize! * t.body.height!) / 2;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      style: t.body.copyWith(color: context.scaffoldHeading),
      decoration: InputDecoration(
        hintText: hint,
        hintMaxLines: 1,
        hintStyle: t.body.copyWith(color: muted),
        filled: true,
        fillColor: SearchStyle.pillFill(context),
        // Without it the field is at least 48 px high.
        isDense: true,
        border: none,
        enabledBorder: none,
        focusedBorder: none,
        contentPadding: EdgeInsetsDirectional.fromSTEB(0, pad, 14, pad),
        prefixIcon: Padding(
          padding: const EdgeInsetsDirectional.only(start: 14, end: 10),
          child: Icon(HubIcons.search, size: 18, color: muted),
        ),
        prefixIconConstraints: const BoxConstraints(),
        suffixIcon: controller.text.isEmpty && trailing == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controller.text.isNotEmpty)
                    HubIconButton(
                      icon: HubIcons.x,
                      iconSize: 18,
                      color: muted,
                      tooltip: l10n.searchClearField,
                      onPressed: onClear,
                    ),
                  ?trailing,
                ],
              ),
        suffixIconConstraints: const BoxConstraints(),
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
    final t = AppTextStyles.of(context);
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
          // 12 inside the 1 px outline, as Figma's border-box: 86 px high.
          padding: const EdgeInsets.all(13),
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
                      style: t.title.copyWith(color: AppColors.inkHeading),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption.copyWith(color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 3),
                    StoreRatingLine(store: store),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // chevron_right mirrors itself in RTL.
              const Icon(
                HubIcons.chevronRight,
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
    height: 86,
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/theme_x.dart';
import '../../../core/assets/app_images.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../../core/widgets/network_image.dart';
import '../../../core/widgets/web_view_screen.dart';
import '../../../l10n/l10n.dart';
import '../domain/seller_groups.dart';
import '../../../app/theme/hub_icons.dart';

/// Figma `--hm-subtle` text: store names in the checkout review.
const Color _inkSubtle = Color(0xFF535D70);

/// Opens [seller]'s store page (`/store/:code`, Figma 13). Where this build
/// has no such screen yet, the store's page on the website opens in the
/// in-app browser instead of a dead end. Nothing for Hub Market itself.
void openSellerStore(BuildContext context, HmSellerSummary seller) {
  final code = seller.storeCode;
  if (code == null) return;
  final router = GoRouter.of(context);
  final path = AppRoutes.store(code);
  if (!router.configuration.findMatch(Uri.parse(path)).isError) {
    router.push(path);
    return;
  }
  final url = seller.link?.url ?? '';
  if (url.isEmpty) return;
  router.push(
    AppRoutes.webview,
    extra: WebViewArgs(url: url, title: seller.name),
  );
}

/// A seller's round logo on white; Hub Market's own mark, or the name's
/// initial, when there is no logo.
class SellerLogo extends StatelessWidget {
  const SellerLogo({
    super.key,
    required this.seller,
    this.size = 28,
    this.bordered = true,
  });

  final HmSellerSummary seller;
  final double size;

  /// A hairline ring — on a white card; the "Sold by" row's tinted band
  /// shows the logo without one.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final initial = seller.name.characters.first.toUpperCase();
    Widget fallback(BuildContext _) => seller.isMarketplace
        ? Image.asset(
            AppImages.appIcon,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _Initial(initial, size: size),
          )
        : _Initial(initial, size: size);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: bordered ? Border.all(color: AppColors.borderSubtle) : null,
      ),
      child: HubImage(
        url: seller.logoUrl,
        fit: BoxFit.contain,
        width: size,
        height: size,
        placeholder: (_) => const ColoredBox(color: Colors.white),
        error: fallback,
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial(this.letter, {required this.size});

  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.surfaceTint,
    child: Center(
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
          color: AppColors.brandPrimary,
        ),
      ),
    ),
  );
}

/// The ✓ (Figma "icon/verified", a ticked circle) after an approved seller's
/// name. The backend returns a seller only
/// once it is approved (`hm_seller` is null otherwise), so every named store
/// carries it; Hub Market itself doesn't.
class SellerVerifiedIcon extends StatelessWidget {
  const SellerVerifiedIcon({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppLocalizations.of(context).sellerVerified,
    child: Icon(HubIcons.circleCheck, size: size, color: AppColors.info),
  );
}

/// Figma 14 "sold-by" (16:1020): a `info-subtle` card with a 12 px radius — the
/// seller's 28 px logo, "Sold by" (Caption, muted), the name in Body Strong and
/// the vendor blue, the ✓, and at the end "Visit store" and a chevron. The
/// whole row opens the store. (The frame carries no rating here.)
class SoldByRow extends StatelessWidget {
  const SoldByRow({super.key, required this.seller});

  final HmSellerSummary seller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final canVisit = seller.storeCode != null;
    return Material(
      color: AppColors.infoSubtle,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canVisit ? () => openSellerStore(context, seller) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SellerLogo(seller: seller, bordered: false),
              const SizedBox(width: 8),
              Text(
                l10n.pdpSoldBy,
                style: t.caption.copyWith(color: AppColors.inkMuted),
              ),
              const SizedBox(width: 8),
              // The name gives way (ellipsis) to a long name or a large text
              // size; "Visit store ›" keeps its place at the end.
              Flexible(
                child: Text(
                  seller.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyStrong.copyWith(color: AppColors.info),
                ),
              ),
              if (!seller.isMarketplace) ...[
                const SizedBox(width: 8),
                const SellerVerifiedIcon(),
              ],
              const Spacer(),
              if (canVisit) ...[
                const SizedBox(width: 8),
                Text(
                  l10n.pdpVisitStore,
                  style: t.captionStrong.copyWith(color: AppColors.info),
                ),
                const SizedBox(width: 8),
                const Icon(
                  HubIcons.chevronRight,
                  size: 14,
                  color: AppColors.info,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Figma 16 "store-header" (62:2677): logo, store name and ✓ at the head of a
/// store's lines. Opens the store when it has a page.
class SellerGroupHeader extends StatelessWidget {
  const SellerGroupHeader({super.key, required this.seller, this.title});

  final HmSellerSummary seller;

  /// Replaces the plain store name, e.g. "Package 1 · loly store".
  final String? title;

  @override
  Widget build(BuildContext context) {
    final canVisit = seller.storeCode != null;
    final row = Row(
      children: [
        SellerLogo(seller: seller),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title ?? seller.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.scaffoldHeading,
            ),
          ),
        ),
        if (!seller.isMarketplace) ...[
          const SizedBox(width: 8),
          const SellerVerifiedIcon(),
        ],
      ],
    );
    if (!canVisit) return row;
    return InkWell(
      onTap: () => openSellerStore(context, seller),
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}

/// Figma 18b: the store line above its items in the review's "Items" card —
/// a 22px logo and the name in small grey type. On the checkout's light card.
class SellerCaption extends StatelessWidget {
  const SellerCaption({super.key, required this.seller});

  final HmSellerSummary seller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SellerLogo(seller: seller, size: 22),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            seller.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _inkSubtle,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Figma 16 "split-note" (62:2670): shown when the lines come from more than
/// one store.
class SplitPackagesNote extends StatelessWidget {
  const SplitPackagesNote({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.infoSubtle,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(HubIcons.package, size: 18, color: AppColors.info),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            AppLocalizations.of(context).cartSplitPackagesNote,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.info,
              height: 1.33,
            ),
          ),
        ),
      ],
    ),
  );
}

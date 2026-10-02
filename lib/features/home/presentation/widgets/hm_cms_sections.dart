import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../catalog/presentation/storefront_links.dart';
import '../../../cms/domain/cms_document.dart';
import '../../../cms/presentation/widgets/cms_html_view.dart';
import '../../data/home_content_repository.dart';
import '../../domain/home_content.dart';
import '../../../../app/theme/hub_icons.dart';

/// The delivery-promise strip under the header (Figma 07 "utility-strip"):
/// the first clause of the `hm_delivery_promise` block's line, on one line,
/// and "Track order ›". 8 pt above and below its Caption Strong line (32 pt in
/// English, 34 in Arabic); the track link's hit area runs the strip's height
/// and ends 16 pt from the edge.
class HmDeliveryStrip extends ConsumerWidget {
  const HmDeliveryStrip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTextStyles.of(context);
    final l10n = AppLocalizations.of(context);
    final signedIn = ref.watch(
      authControllerProvider.select((s) => s.isAuthenticated),
    );
    final style = t.captionStrong.copyWith(color: AppColors.accentStrong);
    return Material(
      color: AppColors.accentSubtle,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(
                      HubIcons.truck,
                      size: 14,
                      color: AppColors.accentStrong,
                    ),
                    const SizedBox(width: 6),
                    // One line, as the frame draws it: the admin's copy up to its
                    // first "·" ("… · Fast nationwide shipping" is website copy
                    // and would not fit beside the track link).
                    Expanded(
                      child: Text(
                        HomeContentParser.firstClause(text),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: () => context.push(
                signedIn ? AppRoutes.orders : AppRoutes.guestTrackOrder,
              ),
              // 4 pt on the promise's side, 8 on the edge's: the icon and label
              // keep the frame's place and the promise gets the room (its
              // first clause misses a 360 dp phone by 0.6 pt with 8 on both).
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 8, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      HubIcons.package,
                      size: 14,
                      color: AppColors.accentStrong,
                    ),
                    const SizedBox(width: 6),
                    Text(l10n.homeTrackOrder, style: style),
                    const SizedBox(width: 6),
                    const Icon(
                      HubIcons.chevronRight,
                      size: 14,
                      color: AppColors.accentStrong,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Promo banners from `hm_home_promos` (Figma 07 "Promo banners"): 104 pt
/// gradient cards — emoji + kicker, headline, line, and a white arrow disc.
/// The text takes the width the disc leaves (no gap, as in the frame) and is
/// centred in the card; a longer text grows the card.
class HmPromoBanners extends ConsumerWidget {
  const HmPromoBanners({super.key, required this.promos});

  final List<PromoTile> promos;

  /// The frame's three gradients, start to end: navy, green, purple.
  static const List<List<Color>> _palettes = <List<Color>>[
    <Color>[Color(0xFF0F2144), Color(0xFF1E3A6E)],
    <Color>[Color(0xFF1A4731), Color(0xFF2D7A3A)],
    <Color>[Color(0xFF3B1F6E), Color(0xFF6B3FA0)],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < promos.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Material(
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: _palettes[i % _palettes.length],
                  ),
                ),
                child: InkWell(
                  onTap: promos[i].url.isEmpty
                      ? null
                      : () => openStorefrontUrl(
                          context,
                          ref,
                          promos[i].url,
                          title: promos[i].title,
                        ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 104),
                    // 16 at the sides; a 2-line headline (86 pt of text) fills
                    // the 104 pt card with 9 pt above and below.
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (promos[i].icon.isNotEmpty ||
                                    promos[i].kicker.isNotEmpty) ...[
                                  Row(
                                    children: [
                                      if (promos[i].icon.isNotEmpty) ...[
                                        SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: FittedBox(
                                            child: Text(
                                              promos[i].icon,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                height: 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Flexible(
                                        child: Text(
                                          promos[i].kicker.toUpperCase(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: t.micro.copyWith(
                                            color: AppColors.accentOnDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                ],
                                Text(
                                  promos[i].title,
                                  style: t.heading2.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                                if (promos[i].text.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    promos[i].text,
                                    style: t.caption.copyWith(
                                      color: AppColors.onInverseMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              HubIcons.arrowRight,
                              size: 18,
                              color: AppColors.inkHeading,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Why Hub Market" (Figma 07 trust grid) from `hm_home_trust`: soft tiles,
/// two a row, an odd last one across the width.
class HmTrustGrid extends StatelessWidget {
  const HmTrustGrid({super.key, required this.items});

  final List<TrustItem> items;

  static const List<IconData> _icons = <IconData>[
    HubIcons.shieldCheck,
    HubIcons.creditCard,
    HubIcons.truck,
    HubIcons.rotateCcw,
    HubIcons.messageCircle,
  ];

  /// Words (English and Arabic) that pick an item's glyph; the position in
  /// the row is the fallback.
  static const List<(List<String>, IconData)> _byWord = [
    (['whatsapp', 'support', 'help', 'واتساب', 'دعم', 'مساعدة'], HubIcons.messageCircle),
    (['return', 'refund', 'إرجاع', 'استرجاع', 'استبدال'], HubIcons.rotateCcw),
    (['deliver', 'shipping', 'توصيل', 'شحن'], HubIcons.truck),
    (['pay', 'card', 'دفع', 'بطاق'], HubIcons.creditCard),
    (['seller', 'trust', 'verified', 'بائع', 'موثوق', 'موثّق'], HubIcons.shieldCheck),
  ];

  static IconData iconFor(TrustItem item, int index) {
    // The title decides first: "Secure Payments — Cash on delivery" is about
    // paying, whatever its caption mentions.
    for (final text in [item.title.toLowerCase(), item.text.toLowerCase()]) {
      for (final (words, icon) in _byWord) {
        if (words.any(text.contains)) return icon;
      }
    }
    return _icons[index % _icons.length];
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final half = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < items.length; i++)
                SizedBox(
                  width: (i == items.length - 1 && items.length.isOdd)
                      ? constraints.maxWidth
                      : half,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: AppColors.accentSubtle,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            iconFor(items[i], i),
                            size: 18,
                            color: AppColors.accentStrong,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                items[i].title,
                                style: t.bodyStrong.copyWith(
                                  color: AppColors.inkHeading,
                                ),
                              ),
                              if (items[i].text.isNotEmpty) ...[
                                const SizedBox(height: 1),
                                Text(
                                  items[i].text,
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
                ),
            ],
          );
        },
      ),
    );
  }
}

/// "Sell on Hub Market" (Figma 07): the CMS block `hm_home_sell` — a heading,
/// its line and an optional link — as the navy card: the orange store tile
/// beside the heading, the line, and the link as an accent button. Everything
/// but the tile is the block's own text, so it is edited in Content › Blocks
/// like the rest of the Home; a block with no heading is not this card.
class HmSellCard extends ConsumerWidget {
  const HmSellCard({
    super.key,
    required this.title,
    this.text = '',
    this.ctaLabel,
    this.ctaUrl,
  });

  final String title;
  final String text;

  /// The block's link: its text and target. The button shows only with both.
  final String? ctaLabel;
  final String? ctaUrl;

  /// The card for [blocks]: the first heading is the title, the paragraphs are
  /// its line, and a paragraph that is only a link is the button. Null when
  /// there is no heading.
  static HmSellCard? fromBlocks(List<CmsBlock> blocks) {
    String? title;
    final lines = <String>[];
    String? ctaLabel;
    String? ctaUrl;
    for (final block in blocks) {
      switch (block) {
        case CmsHeading():
          if (title == null && block.text.isNotEmpty) title = block.text;
        case CmsParagraph():
          final link = block.inlines
              .where((i) => i.href != null && i.text.trim().isNotEmpty)
              .firstOrNull;
          if (link != null && ctaUrl == null && block.text == link.text.trim()) {
            ctaLabel = link.text.trim();
            ctaUrl = link.href;
          } else if (block.text.isNotEmpty) {
            lines.add(block.text);
          }
        default:
          break;
      }
    }
    if (title == null) return null;
    return HmSellCard(
      title: title,
      text: lines.join('\n'),
      ctaLabel: ctaLabel,
      ctaUrl: ctaUrl,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTextStyles.of(context);
    final label = ctaLabel;
    final url = ctaUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.brandPrimary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    HubIcons.store,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.heading2.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                text,
                style: t.caption.copyWith(color: AppColors.onInverseMuted),
              ),
            ],
            if (label != null && url != null) ...[
              const SizedBox(height: 10),
              HubButton(
                label: label,
                style: HubButtonStyle.accent,
                expand: false,
                onPressed: () => openStorefrontUrl(
                  context,
                  ref,
                  url,
                  title: title,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Any CMS block (CMS_BLOCK), drawn natively; its links go through the
/// storefront-link router. The Home's `hm_home_sell` block ([identifier]) is
/// the "Sell on Hub Market" card ([HmSellCard]).
class HmCmsBlockView extends ConsumerWidget {
  const HmCmsBlockView({super.key, required this.html, this.identifier});

  final String html;

  /// The block's CMS identifier, when known.
  final String? identifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = CmsDocument.parse(html);
    if (blocks.isEmpty) return const SizedBox.shrink();
    if (identifier == HomeCmsBlocks.sell) {
      final card = HmSellCard.fromBlocks(blocks);
      if (card != null) return card;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CmsHtmlView(
        blocks: blocks,
        mediaBase: Uri.parse(ref.read(appConfigProvider).graphqlEndpoint).origin,
        onLink: (href) => openStorefrontUrl(context, ref, href),
      ),
    );
  }
}

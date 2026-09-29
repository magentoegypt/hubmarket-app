import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/app_config.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../catalog/presentation/storefront_links.dart';
import '../../../cms/domain/cms_document.dart';
import '../../../cms/presentation/widgets/cms_html_view.dart';
import '../../domain/home_content.dart';

/// The delivery-promise strip under the header (Figma 07 "utility-strip"):
/// the `hm_delivery_promise` block's line and "Track order ›".
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
    return Container(
      color: const Color(0xFFFFF4EC),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
      child: Row(
        children: [
          const Icon(
            Icons.local_shipping_outlined,
            size: 14,
            color: AppColors.accentStrong,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          InkWell(
            onTap: () => context.push(
              signedIn ? AppRoutes.orders : AppRoutes.guestTrackOrder,
            ),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 14,
                    color: AppColors.accentStrong,
                  ),
                  const SizedBox(width: 6),
                  Text(l10n.homeTrackOrder, style: style),
                  const Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: AppColors.accentStrong,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Promo banners from `hm_home_promos` (Figma 07 "Promo banners"): gradient
/// cards — emoji + kicker, headline, line, and a white arrow disc.
class HmPromoBanners extends ConsumerWidget {
  const HmPromoBanners({super.key, required this.promos});

  final List<PromoTile> promos;

  static const List<List<Color>> _palettes = <List<Color>>[
    <Color>[Color(0xFF0F2144), Color(0xFF1E3A6E)],
    <Color>[Color(0xFF14532D), Color(0xFF2E7D32)],
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (promos[i].icon.isNotEmpty ||
                                    promos[i].kicker.isNotEmpty)
                                  Text(
                                    [
                                      promos[i].icon,
                                      promos[i].kicker.toUpperCase(),
                                    ].where((s) => s.isNotEmpty).join(' '),
                                    style: t.micro.copyWith(
                                      color: AppColors.accentOnDark,
                                    ),
                                  ),
                                const SizedBox(height: 4),
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
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward,
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
    Icons.verified_user_outlined,
    Icons.credit_card_outlined,
    Icons.local_shipping_outlined,
    Icons.replay_outlined,
    Icons.chat_bubble_outline,
  ];

  /// Words (English and Arabic) that pick an item's glyph; the position in
  /// the row is the fallback.
  static const List<(List<String>, IconData)> _byWord = [
    (['whatsapp', 'support', 'help', 'واتساب', 'دعم', 'مساعدة'], Icons.chat_bubble_outline),
    (['return', 'refund', 'إرجاع', 'استرجاع', 'استبدال'], Icons.replay_outlined),
    (['deliver', 'shipping', 'توصيل', 'شحن'], Icons.local_shipping_outlined),
    (['pay', 'card', 'دفع', 'بطاق'], Icons.credit_card_outlined),
    (['seller', 'trust', 'verified', 'بائع', 'موثوق', 'موثّق'], Icons.verified_user_outlined),
  ];

  static IconData iconFor(TrustItem item, int index) {
    final text = '${item.title} ${item.text}'.toLowerCase();
    for (final (words, icon) in _byWord) {
      if (words.any(text.contains)) return icon;
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
                      borderRadius: BorderRadius.circular(12),
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

/// Any CMS block (CMS_BLOCK), drawn natively; its links go through the
/// storefront-link router.
class HmCmsBlockView extends ConsumerWidget {
  const HmCmsBlockView({super.key, required this.html});

  final String html;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = CmsDocument.parse(html);
    if (blocks.isEmpty) return const SizedBox.shrink();
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

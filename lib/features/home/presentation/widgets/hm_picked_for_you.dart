import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/presentation/search_history.dart';
import '../../domain/hm_home.dart';
import 'hm_product_rail.dart';

/// Picked For You (Figma 07 "Picked For You (AI)"): a tinted band — the
/// engine badge, the admin's title and subtitle, Refresh, the customer's own
/// recent searches as chips, and the products.
class HmPickedForYou extends ConsumerWidget {
  const HmPickedForYou({super.key, required this.section, this.onRefresh});

  final HmHomeSection section;
  final VoidCallback? onRefresh;

  /// Recent searches shown as chips.
  static const int searchLimit = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTextStyles.of(context);
    final l10n = AppLocalizations.of(context);
    final searches = ref
        .watch(searchHistoryProvider)
        .take(searchLimit)
        .toList(growable: false);
    return ColoredBox(
      color: AppColors.infoSubtle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brandPrimary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            children: [
                              const Text(
                                '✨',
                                style: TextStyle(fontSize: 11, height: 1),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  l10n.homeAiEngine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.micro.copyWith(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (section.hasHeader) ...[
                          const SizedBox(height: 6),
                          Text(
                            section.title!,
                            style: t.heading1.copyWith(
                              color: AppColors.inkHeading,
                            ),
                          ),
                        ],
                        if (section.subtitle != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            section.subtitle!,
                            style: t.caption.copyWith(
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onRefresh != null) ...[
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.white,
                      shape: const StadiumBorder(
                        side: BorderSide(color: AppColors.brandPrimary),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onRefresh,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.refresh_rounded,
                                size: 14,
                                color: AppColors.inkHeading,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                l10n.homeRefresh,
                                style: t.captionStrong.copyWith(
                                  color: AppColors.inkHeading,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (searches.isNotEmpty) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l10n.homeYourSearches,
                      style: t.micro.copyWith(color: AppColors.inkMuted),
                    ),
                    for (final term in searches)
                      _SearchChip(
                        term: term,
                        onTap: () => context.push(AppRoutes.search, extra: term),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            HmProductRail(products: section.products),
          ],
        ),
      ),
    );
  }
}

class _SearchChip extends StatelessWidget {
  const _SearchChip({required this.term, required this.onTap});

  final String term;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(side: BorderSide(color: AppColors.borderStrong)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search, size: 12, color: AppColors.inkHeading),
              const SizedBox(width: 4),
              Text(
                term,
                style: t.captionStrong.copyWith(color: AppColors.inkHeading),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

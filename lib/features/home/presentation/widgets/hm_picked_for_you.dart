import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/presentation/search_history.dart';
import '../../../catalog/presentation/search_providers.dart';
import '../../../personalization/domain/personal_picks.dart';
import '../../../personalization/presentation/personal_picks_provider.dart';
import '../../domain/hm_home.dart';
import 'hm_product_rail.dart';
import '../../../../app/theme/hub_icons.dart';

/// Picked For You (Figma 07 "Picked For You (AI)"): a tinted band — the
/// admin's title and subtitle, Refresh, the customer's own recent searches as
/// chips (before they have searched, the store's top searches from Algolia,
/// labelled as such), and the products.
///
/// The Home draws the cached top-rated section first (the server sends 16);
/// Refresh shows the next four of them. Once `hmPickedForYou` says the
/// shopper has a profile ([PersonalPicks.personalized]) its picks replace
/// them, and only then the section carries the admin's badge ("AI ENGINE")
/// and the "Personalised recommendations…" subtitle: the app never labels the
/// generic list as personal.
class HmPickedForYou extends ConsumerStatefulWidget {
  const HmPickedForYou({super.key, required this.section, this.onRefresh});

  final HmHomeSection section;

  /// Reloads the Home: what Refresh does when there are no more picks than
  /// the four on show.
  final VoidCallback? onRefresh;

  /// Recent searches shown as chips.
  static const int searchLimit = 4;

  @override
  ConsumerState<HmPickedForYou> createState() => _HmPickedForYouState();
}

class _HmPickedForYouState extends ConsumerState<HmPickedForYou> {
  /// Where Refresh has got to in the pool.
  int _offset = 0;

  /// Whether the pool on show is the shopper's own: a swap starts it over.
  bool _wasPersonal = false;

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final onRefresh = widget.onRefresh;
    final t = AppTextStyles.of(context);
    final l10n = AppLocalizations.of(context);
    final own = ref
        .watch(searchHistoryProvider)
        .take(HmPickedForYou.searchLimit)
        .toList(growable: false);
    // Before the shopper has searched, the store's top searches from Algolia
    // take the row, under a label of their own: they are not "your" searches.
    final searches = own.isNotEmpty
        ? own
        : (ref.watch(topSearchesProvider).valueOrNull ?? const <String>[])
              .take(HmPickedForYou.searchLimit)
              .toList(growable: false);
    final personal = section.personalizable
        ? ref.watch(personalPicksProvider).valueOrNull
        : null;
    final isPersonal = personal != null;
    if (isPersonal != _wasPersonal) {
      _wasPersonal = isPersonal;
      _offset = 0;
    }
    final pool = personal?.items ?? section.products;
    final rotates = pool.length > kPickedPageSize;
    final badge = isPersonal ? (section.badge ?? '').trim() : '';
    final subtitle = isPersonal
        ? l10n.homePickedPersonalSubtitle
        : section.subtitle;
    final refresh = rotates
        ? () => setState(
            () => _offset = nextPickedOffset(_offset, pool.length),
          )
        : onRefresh;
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
                        if (badge.isNotEmpty) ...[
                          _Badge(label: badge.toUpperCase()),
                          const SizedBox(height: 6),
                        ],
                        if (section.hasHeader)
                          Text(
                            section.title!,
                            style: t.heading1.copyWith(
                              color: AppColors.inkHeading,
                            ),
                          ),
                        if (subtitle != null) ...[
                          if (section.hasHeader) const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: t.caption.copyWith(
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // The text takes the width Refresh leaves (267 + 91 in the
                  // frame, nothing between).
                  if (refresh != null) ...[
                    Material(
                      color: Colors.white,
                      shape: const StadiumBorder(
                        side: BorderSide(color: AppColors.brandPrimary),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: refresh,
                        // 1 pt border + 12 / 8 pt of padding: 34 pt high.
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 9,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                HubIcons.rotateCcw,
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
                      own.isNotEmpty
                          ? l10n.homeYourSearches
                          : l10n.homeTopSearches,
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
            // A new key on every Refresh: the rail starts from its first card.
            HmProductRail(
              key: ValueKey('$isPersonal-$_offset'),
              products: pickedPage(pool, _offset),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pill above the title (Figma `ai-badge`): the admin's badge text in
/// capitals after a sparkle, white on the brand navy, as wide as the text
/// column.
class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.brandPrimary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: FittedBox(
              child: Text('✨', style: TextStyle(fontSize: 12, height: 1)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.micro.copyWith(color: Colors.white),
            ),
          ),
        ],
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
        // 1 pt border + 10 / 5 pt of padding: 28 pt high.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(HubIcons.search, size: 12, color: AppColors.inkHeading),
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

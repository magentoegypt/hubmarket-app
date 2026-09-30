import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/hubapp/hubapp_models.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';

/// Opens a seller's store page (`/store/:code`).
void openStore(BuildContext context, HmStoreCard store) =>
    context.push(AppRoutes.store(store.code));

/// Featured Stores rail (Figma 07, component "Featured store card"): logo with
/// the verified badge, rating, product count, dispatch time, Visit Store.
class HmFeaturedStoresRail extends StatelessWidget {
  const HmFeaturedStoresRail({super.key, required this.stores});

  final List<HmStoreCard> stores;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 212,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: stores.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => HmFeaturedStoreCard(store: stores[i]),
      ),
    );
  }
}

class HmFeaturedStoreCard extends StatelessWidget {
  const HmFeaturedStoreCard({super.key, required this.store});

  final HmStoreCard store;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final l10n = AppLocalizations.of(context);
    final dispatch = store.dispatchTime?.label;
    return SizedBox(
      width: 148,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openStore(context, store),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
            child: Column(
              children: [
                _VerifiedAvatar(store: store, size: 64, badge: 22),
                const SizedBox(height: 6),
                Text(
                  store.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: t.title.copyWith(color: AppColors.inkHeading),
                ),
                const SizedBox(height: 4),
                if (store.rating != null)
                  _Rating(
                    rating: store.rating!,
                    style: t.bodyStrong,
                    size: 14,
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 13,
                      color: Color(0xFF535D70),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${store.productCount}',
                      style: t.caption.copyWith(color: const Color(0xFF535D70)),
                    ),
                    if (dispatch != null) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: Color(0xFF535D70),
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          dispatch,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption.copyWith(
                            color: const Color(0xFF535D70),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const Spacer(),
                Container(
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.brandPrimary),
                  ),
                  child: Text(
                    l10n.homeVisitStore,
                    style: t.captionStrong.copyWith(
                      color: AppColors.inkHeading,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Top Vendors This Month (Figma 07, component "Top vendor card"): navy
/// cover, "#1 VENDOR" on the first, logo + verified, rating · products.
class HmTopVendorsRail extends StatelessWidget {
  const HmTopVendorsRail({super.key, required this.stores});

  final List<HmStoreCard> stores;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 154,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: stores.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) =>
            HmTopVendorCard(store: stores[i], first: i == 0),
      ),
    );
  }
}

class HmTopVendorCard extends StatelessWidget {
  const HmTopVendorCard({super.key, required this.store, this.first = false});

  final HmStoreCard store;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: 150,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openStore(context, store),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 86,
                child: Stack(
                  children: [
                    const PositionedDirectional(
                      top: 0,
                      start: 0,
                      end: 0,
                      height: 54,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: AlignmentDirectional.centerStart,
                            end: AlignmentDirectional.centerEnd,
                            colors: [AppColors.brandPrimary, Color(0xFF1E3A6E)],
                          ),
                        ),
                      ),
                    ),
                    if (first)
                      PositionedDirectional(
                        top: 10,
                        start: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFACC15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            l10n.homeTopVendorBadge,
                            style: t.micro.copyWith(color: AppColors.inkHeading),
                          ),
                        ),
                      ),
                    PositionedDirectional(
                      top: 28,
                      start: 12,
                      child: _VerifiedAvatar(store: store, size: 56, badge: 20),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.title.copyWith(color: AppColors.inkHeading),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (store.rating != null) ...[
                          _Rating(
                            rating: store.rating!,
                            style: t.captionStrong,
                            size: 13,
                          ),
                          Text(
                            ' · ',
                            style: t.caption.copyWith(color: AppColors.inkMuted),
                          ),
                        ],
                        Flexible(
                          child: Text(
                            l10n.hmProductCount(store.productCount),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.caption.copyWith(color: AppColors.inkMuted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// New Stores on Hub Market (Figma 07 "new-stores"): one bordered list of
/// sellers — avatar, name, product count, Verified, chevron.
class HmNewStoresList extends StatelessWidget {
  const HmNewStoresList({super.key, required this.stores});

  final List<HmStoreCard> stores;

  static const List<Color> _avatarColors = <Color>[
    AppColors.info,
    AppColors.accent,
    AppColors.successStrong,
    AppColors.brandPrimary,
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          children: [
            for (var i = 0; i < stores.length; i++)
              InkWell(
                onTap: () => openStore(context, stores[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: i == stores.length - 1
                        ? null
                        : const Border(
                            bottom: BorderSide(color: AppColors.borderSubtle),
                          ),
                  ),
                  child: Row(
                    children: [
                      StoreAvatar(
                        store: stores[i],
                        size: 40,
                        color: _avatarColors[i % _avatarColors.length],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stores[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodyStrong.copyWith(
                                color: AppColors.inkHeading,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  l10n.hmProductCount(stores[i].productCount),
                                  style: t.caption.copyWith(
                                    color: AppColors.inkMuted,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const HmVerifiedPill(),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.inkMuted,
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

/// The green "✓ Verified" pill.
class HmVerifiedPill extends StatelessWidget {
  const HmVerifiedPill({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.successSubtle,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check, size: 11, color: AppColors.successStrong),
        const SizedBox(width: 3),
        Text(
          AppLocalizations.of(context).homeVerified,
          style: AppTextStyles.of(
            context,
          ).micro.copyWith(color: AppColors.successStrong),
        ),
      ],
    ),
  );
}

/// A seller's round logo, or its initial on [color] when it has none.
class StoreAvatar extends StatelessWidget {
  const StoreAvatar({
    super.key,
    required this.store,
    required this.size,
    this.color = AppColors.brandPrimary,
    this.border = false,
  });

  final HmStoreCard store;
  final double size;
  final Color color;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final initial = store.name.trim().isEmpty
        ? '?'
        : store.name.trim().characters.first.toUpperCase();
    final letter = Container(
      color: color,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.of(
          context,
        ).title.copyWith(color: Colors.white, fontSize: size * 0.4),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: border
            ? Border.all(color: AppColors.borderSubtle, width: 1)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: (store.logoUrl ?? '').isEmpty
          ? letter
          : HubImage(
              url: store.logoUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              error: (_) => letter,
            ),
    );
  }
}

class _VerifiedAvatar extends StatelessWidget {
  const _VerifiedAvatar({
    required this.store,
    required this.size,
    required this.badge,
  });

  final HmStoreCard store;
  final double size;
  final double badge;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        StoreAvatar(store: store, size: size, border: true),
        PositionedDirectional(
          end: -2,
          bottom: -2,
          child: Container(
            width: badge,
            height: badge,
            decoration: BoxDecoration(
              color: AppColors.info,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(Icons.check, size: badge * 0.55, color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

class _Rating extends StatelessWidget {
  const _Rating({required this.rating, required this.style, required this.size});

  final double rating;
  final TextStyle style;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.star_rounded, size: size + 2, color: AppColors.accentGold),
      const SizedBox(width: 4),
      Text(
        rating.toStringAsFixed(1),
        style: style.copyWith(color: AppColors.inkHeading),
      ),
    ],
  );
}

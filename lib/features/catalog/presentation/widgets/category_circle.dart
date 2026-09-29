import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/network_image.dart';
import '../../domain/category.dart';
import '../catalog_providers.dart';

/// The "Shop by Category" circle rail, reused for category navigation on the
/// product listing (CL042-DEV14).
///
/// Geometry is deliberately identical to the home screen's Shop by Category
/// rail (`_CategoryGrid` / `_CategoryCircle` in `home_screen.dart`) — 72px
/// circle on an 80px card, 14px apart, 12px single-line label — so the two read
/// as the same control in two places. Keep them in step if either moves.
///
/// It replaces the old text pills because the storefront draws its
/// `beauty-subcats` rail on *every* category page, the top level included, so
/// pills were the wrong shape at every depth rather than only the deepest.
///
/// Categories below the top level have no `image` on this store, so the rail
/// resolves stand-ins from [categoryThumbnailsProvider] — the first product in
/// each, the same substitution the website makes.
class CategoryCircleRail extends ConsumerWidget {
  const CategoryCircleRail({
    super.key,
    required this.categories,
    required this.onTap,
  });

  final List<Category> categories;

  /// Opens the tapped category. The rail navigates rather than filters, so
  /// there is no selected state to carry and no "All" control to return to —
  /// each level is its own page, left via back, exactly like the storefront.
  final ValueChanged<Category> onTap;

  /// Home's Shop by Category measurements.
  static const double _circle = 72;
  static const double _cardWidth = 80;
  static const double _gap = 14;
  static const double railHeight = 116;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (categories.isEmpty) return const SizedBox.shrink();
    // Only the ones missing an image cost a lookup; an empty key short-circuits
    // inside the provider, so a fully illustrated level issues no query at all.
    final thumbnails =
        ref
            .watch(categoryThumbnailsProvider(categoryThumbnailKey(categories)))
            .valueOrNull ??
        const <String, String>{};

    return SizedBox(
      height: railHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: _gap),
        itemBuilder: (context, index) {
          final category = categories[index];
          final url = (category.image ?? '').isNotEmpty
              ? category.image
              : thumbnails[category.uid];
          return _RailTile(
            label: category.name,
            onTap: () => onTap(category),
            child: HubImage(
              url: url,
              width: _circle,
              height: _circle,
              decodeWidth: _circle,
              // Same neutral tile home falls back to when a category has no
              // usable image — here that means a category with no products to
              // borrow one from.
              placeholder: (_) => const _CategoryFallback(),
              error: (_) => const _CategoryFallback(),
            ),
          );
        },
      ),
    );
  }
}

/// One rail card: round media well + label.
class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: CategoryCircleRail._cardWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: SizedBox(
                width: CategoryCircleRail._circle,
                height: CategoryCircleRail._circle,
                child: child,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Blush tile with a burgundy spa glyph — the same stand-in the home rail uses
/// for a category with no usable image.
class _CategoryFallback extends StatelessWidget {
  const _CategoryFallback();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.surfaceTint,
    child: Center(
      child: Icon(Icons.spa_outlined, color: AppColors.brandPrimary),
    ),
  );
}

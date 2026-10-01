import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The disk cache behind every network image in the app.
///
/// `DefaultCacheManager` holds 200 objects; a single PLP page is 20 images, so a
/// normal browse session evicts the top of the grid before the user has scrolled
/// back to it — the image then re-downloads and the screen looks slow again.
///
/// Product media on `hub-market.magento2.click` is served `Cache-Control:
/// public, max-age=604800` (verified 2026-10-01; only the uncached `multi.`
/// origin says a year, `immutable`), and a replaced image gets a new file name,
/// so a long local TTL can never serve a stale image.
///
/// Note [Config.maxNrOfCacheObjects] caps the object *count*, not bytes: 600 ×
/// ~40KB ≈ 24MB in the typical case. Before the WebP copies (see `HubImage`)
/// the store's PNGs ran to 300KB+ each. Revisit the count if/when the backend
/// adds per-role image presets: today every role gets the one 800-1600px
/// derivative.
class HubImageCacheManager extends CacheManager with ImageCacheManager {
  HubImageCacheManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 600,
        ),
      );

  static const String key = 'hubmarketImageCache';

  static final HubImageCacheManager instance = HubImageCacheManager._();
}

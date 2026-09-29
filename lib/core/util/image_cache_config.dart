import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The disk cache behind every network image in the app.
///
/// `DefaultCacheManager` holds 200 objects; a single PLP page is 20 images, so a
/// normal browse session evicts the top of the grid before the user has scrolled
/// back to it — the image then re-downloads and the screen looks slow again.
///
/// Product media is served `Cache-Control: public, max-age=31536000, immutable`
/// (verified against the CDN on 2026-08-21), and the URL carries a content hash,
/// so a long local TTL can never serve a stale image.
///
/// Note [Config.maxNrOfCacheObjects] caps the object *count*, not bytes: 600 ×
/// ~40KB ≈ 24MB in the typical case, but the store currently serves some 300KB+
/// PNGs. Revisit the count if/when the backend adds per-role image presets.
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

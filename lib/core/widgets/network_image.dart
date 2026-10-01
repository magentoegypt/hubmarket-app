import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../config/app_config.dart';
import '../util/image_cache_config.dart';
import '../util/media.dart';
import 'shimmer.dart';
import '../../app/theme/hub_icons.dart';

/// The single entry point for every network image in the app.
///
/// Feature code must not construct [CachedNetworkImage] directly — this widget
/// owns four things that were previously left to each call site (and were
/// therefore wrong almost everywhere):
///
/// 1. **No fade.** `cached_network_image` defaults to a 500ms fade-in *and* a
///    1000ms placeholder fade-out, so even an image already on disk stayed
///    visibly veiled for about a second. A hard cut reads as "instant"; a
///    dissolve reads as "slow". Both are pinned to [kFadeIn] / [kFadeOut].
/// 2. **Decode sizing.** The store serves one large derivative for every image
///    role (verified 2026-08-21 — `image`, `small_image` and `thumbnail` return
///    the same URL), so an 823px asset lands in a 44pt row. Every image decodes
///    at its on-screen size × DPR instead of full resolution.
/// 3. **A shared [ImageProvider] identity.** [provider] builds the *exact* same
///    provider the widget uses, so `precacheImage` warms the key the widget
///    later looks up. A mismatched decode width silently re-decodes.
/// 4. **The WebP copy.** A resized product image on the store's own host is
///    requested as its `.webp` twin ([webpTwinUrl]) — a third to a tenth of
///    the bytes at the same pixel size, the same file the website's
///    `<picture>` serves. Not every image has one (a copy appears within about
///    ten minutes of an upload, and the "no image" placeholder never gets
///    one), so a failed load falls back to the original URL, and the miss is
///    remembered for the session instead of asking again at every scroll.
class HubImage extends StatelessWidget {
  const HubImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.decodeWidth,
    this.placeholder,
    this.error,
    this.shimmer = false,
    this.borderRadius,
    this.semanticLabel,
  });

  /// A cached image must appear with no transition at all — see the class doc.
  static const Duration kFadeIn = Duration.zero;
  static const Duration kFadeOut = Duration.zero;

  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Logical width to decode at (× DPR applied internally). Defaults to [width],
  /// and falls back to the laid-out width when neither is given.
  final double? decodeWidth;

  /// Shown while the bytes load. Defaults to a flat tint (or a shimmering one
  /// when [shimmer] is set).
  final WidgetBuilder? placeholder;

  /// Shown when the image fails *and* when [url] is null/empty. Defaults to a
  /// tint with a muted glyph.
  final WidgetBuilder? error;

  /// Animate the default placeholder. Opt-in: each [Shimmer] runs its own
  /// ticker, so it is worth it only where the placeholder genuinely persists
  /// (heroes, banners, category/brand tiles) — never across a grid of cells
  /// that paint from cache immediately.
  final bool shimmer;

  final BorderRadiusGeometry? borderRadius;
  final String? semanticLabel;

  /// The host whose resized product images have a WebP copy: the store's own,
  /// the one the GraphQL endpoint is on. A variable only so a test can pin it.
  @visibleForTesting
  static String webpHost =
      Uri.tryParse(AppConfig.current.graphqlEndpoint)?.host ?? '';

  /// Images whose WebP copy failed to load this session — asked for as they
  /// are from then on.
  static final Set<String> _withoutWebp = <String>{};

  @visibleForTesting
  static void forgetWebpMisses() => _withoutWebp.clear();

  /// What to request for [url]: its WebP copy where it has one and that copy
  /// hasn't failed this session, otherwise [url] itself.
  static String _requested(String url) {
    if (_withoutWebp.contains(url)) return url;
    return webpTwinUrl(url, storeHost: webpHost) ?? url;
  }

  /// The provider [HubImage] itself resolves — use it for `precacheImage`.
  ///
  /// Mirrors what `CachedNetworkImage` builds internally (octo_image applies
  /// `memCacheWidth` via [ResizeImage.resizeIfNeeded]), so the two share an
  /// [ImageCache] key. [decodeWidth] here is in **physical** pixels, i.e.
  /// already multiplied by the device pixel ratio.
  static ImageProvider provider(String url, {int? decodeWidth}) {
    return ResizeImage.resizeIfNeeded(
      (decodeWidth != null && decodeWidth > 0) ? decodeWidth : null,
      null,
      CachedNetworkImageProvider(
        _requested(url),
        cacheManager: HubImageCacheManager.instance,
      ),
    );
  }

  /// Converts a logical size to the physical decode width used by [provider].
  static int? decodePixels(BuildContext context, double? logicalWidth) {
    if (logicalWidth == null || !logicalWidth.isFinite || logicalWidth <= 0) {
      return null;
    }
    return (logicalWidth * MediaQuery.devicePixelRatioOf(context)).round();
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    Widget child = hasUrl ? _image(context) : _sized(_error(context));
    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius!, child: child);
    }
    if (semanticLabel != null) {
      child = Semantics(image: true, label: semanticLabel, child: child);
    }
    return child;
  }

  Widget _image(BuildContext context) {
    final explicit = decodeWidth ?? width;
    if (explicit != null) {
      return _cached(context, decodePixels(context, explicit));
    }
    // No size known up front (grid cells, flexible rows) — take it from layout.
    return LayoutBuilder(
      builder: (context, constraints) =>
          _cached(context, decodePixels(context, constraints.maxWidth)),
    );
  }

  Widget _cached(BuildContext context, int? memCacheWidth) {
    final original = url!;
    final requested = _requested(original);
    return _load(requested, memCacheWidth, (context) {
      if (requested == original) return _sized(_error(context));
      // The WebP copy isn't there (yet): remember that, load the original.
      _withoutWebp.add(original);
      return _load(
        original,
        memCacheWidth,
        (context) => _sized(_error(context)),
      );
    });
  }

  Widget _load(String imageUrl, int? memCacheWidth, WidgetBuilder onError) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheManager: HubImageCacheManager.instance,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      fadeInDuration: kFadeIn,
      fadeOutDuration: kFadeOut,
      placeholderFadeInDuration: kFadeIn,
      placeholder: (context, _) => _sized(_placeholder(context)),
      errorWidget: (context, _, __) => onError(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    if (placeholder != null) return placeholder!(context);
    const tint = ColoredBox(color: AppColors.surfaceTint, child: SizedBox.expand());
    return shimmer ? const Shimmer(child: tint) : tint;
  }

  Widget _error(BuildContext context) {
    if (error != null) return error!(context);
    return const ColoredBox(
      color: AppColors.surfaceTint,
      child: Center(child: Icon(HubIcons.image, color: AppColors.inkMuted)),
    );
  }

  /// Keeps the placeholder/error states the same size as the image would be.
  Widget _sized(Widget child) => (width == null && height == null)
      ? child
      : SizedBox(width: width, height: height, child: child);
}

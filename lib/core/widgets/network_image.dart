import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../util/image_cache_config.dart';
import 'shimmer.dart';

/// The single entry point for every network image in the app.
///
/// Feature code must not construct [CachedNetworkImage] directly — this widget
/// owns three things that were previously left to each call site (and were
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
        url,
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
    return CachedNetworkImage(
      imageUrl: url!,
      cacheManager: HubImageCacheManager.instance,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      fadeInDuration: kFadeIn,
      fadeOutDuration: kFadeOut,
      placeholderFadeInDuration: kFadeIn,
      placeholder: (context, _) => _sized(_placeholder(context)),
      errorWidget: (context, _, __) => _sized(_error(context)),
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
      child: Center(child: Icon(Icons.image_outlined, color: AppColors.inkMuted)),
    );
  }

  /// Keeps the placeholder/error states the same size as the image would be.
  Widget _sized(Widget child) => (width == null && height == null)
      ? child
      : SizedBox(width: width, height: height, child: child);
}

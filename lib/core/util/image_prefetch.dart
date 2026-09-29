import 'dart:async';

import 'package:flutter/widgets.dart';

import '../widgets/network_image.dart';

/// Warms images the user is about to see, so they paint from cache instead of
/// starting a download at the moment they scroll into view.
///
/// Always bounded. Prefetching a whole grid — or every gallery image — costs
/// mobile data the user did not ask to spend and evicts the images they are
/// actually looking at from a finite [ImageCache]. Prefetch the *next* few
/// things, never the rest of the catalogue.
///
/// [decodeWidth] must match the width the eventual widget decodes at, or the
/// two produce different cache keys and this work is thrown away — see
/// [HubImage.provider].
///
/// Fire-and-forget: failures are swallowed, since a pre-warm that fails simply
/// means the widget loads the image itself.
Future<void> prefetchImages(
  BuildContext context,
  Iterable<String?> urls, {
  required int? decodeWidth,
  int limit = 6,
}) async {
  if (limit <= 0) return;
  final seen = <String>{};
  for (final url in urls) {
    if (url == null || url.isEmpty) continue;
    if (!seen.add(url)) continue;
    if (seen.length > limit) break;
    if (!context.mounted) return;
    unawaited(
      precacheImage(
        HubImage.provider(url, decodeWidth: decodeWidth),
        context,
      ).catchError((_) {}),
    );
  }
}

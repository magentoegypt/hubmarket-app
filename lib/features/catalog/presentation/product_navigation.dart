import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/widgets/network_image.dart';
import '../domain/product.dart';
import '../domain/product_preview.dart';

/// The logical width the PDP hero paints at — the full screen width.
///
/// Both the gallery and anything that pre-warms the hero must decode at the
/// *same* width, or the two produce different [ImageCache] keys and the
/// pre-warm silently buys nothing. Keep this the single definition.
double pdpImageWidth(BuildContext context) => MediaQuery.sizeOf(context).width;

/// [pdpImageWidth] in physical pixels, for [HubImage.provider].
int? pdpImagePixels(BuildContext context) =>
    HubImage.decodePixels(context, pdpImageWidth(context));

/// Opens the PDP for a product the user tapped in a listing.
///
/// Two things happen before the route pushes, and both exist because the PDP
/// used to show a bare spinner while it re-fetched an image the listing was
/// already displaying:
///
/// * the hero image starts decoding at PDP size immediately, so it is usually
///   ready before the new route's first frame;
/// * the listing's name/price/image ride along as a [ProductPreview], so the
///   loading state paints the real top of the page instead of a spinner.
///
/// The pre-warm is fire-and-forget — a failure here must never block navigation
/// (the gallery will simply load the image itself).
void openProduct(BuildContext context, Product product) {
  final url = product.imageUrl;
  if (url != null && url.isNotEmpty) {
    unawaited(
      precacheImage(
        HubImage.provider(url, decodeWidth: pdpImagePixels(context)),
        context,
      ).catchError((_) {}),
    );
  }
  context.push(
    AppRoutes.product(product.urlKey),
    extra: ProductPreview.of(product),
  );
}

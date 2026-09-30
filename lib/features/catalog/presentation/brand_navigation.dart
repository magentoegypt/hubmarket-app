import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/hubapp/hubapp_providers.dart';
import '../data/brands_provider.dart';
import '../domain/brand.dart';
import 'screens/search_screen.dart';

/// The brand in [brands] a product's brand line names: by its `mgs_brand`
/// option id when the product carries one, else by title (case aside). Null
/// when none matches.
Brand? brandForProduct(
  List<Brand> brands, {
  required String name,
  int? optionId,
}) {
  if (optionId != null) {
    for (final brand in brands) {
      if (brand.optionId == optionId) return brand;
    }
  }
  final title = name.trim().toLowerCase();
  if (title.isEmpty) return null;
  for (final brand in brands) {
    if (brand.title.trim().toLowerCase() == title) return brand;
  }
  return null;
}

/// Opens the brand of a product page:
///
/// * with the Hub Market App (Build 2) and the brand in `hmBrands` — its page
///   (Figma 10e, [AppRoutes.brandPage]);
/// * otherwise — the catalogue's own brand results ([SearchScreen] with a
///   brand): the `mgs_brand` option's products when the product carries its
///   id, a search for the brand's name when not.
///
/// Never throws: a brands feed that can't be read counts as "not listed".
Future<void> openProductBrand(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  int? optionId,
}) async {
  if (ref.read(hubAppStatusProvider) == HubAppStatus.available) {
    List<Brand> brands;
    try {
      brands =
          ref.read(brandsProvider).valueOrNull ??
          await ref
              .read(brandsProvider.future)
              .timeout(const Duration(seconds: 8));
    } on Object {
      brands = const <Brand>[];
    }
    if (!context.mounted) return;
    final brand = brandForProduct(brands, name: name, optionId: optionId);
    if (brand != null && brand.urlKey.isNotEmpty) {
      unawaited(context.push(AppRoutes.brandPage(brand.urlKey), extra: brand));
      return;
    }
  }
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SearchScreen(
          brand: Brand(
            brandId: 0,
            title: name.trim(),
            urlKey: '',
            url: '',
            imageUrl: '',
            optionId: optionId,
            position: 0,
          ),
        ),
      ),
    ),
  );
}

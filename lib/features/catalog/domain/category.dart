import 'dart:convert';

/// A category's GraphQL uid from its numeric id — Magento's uid is base64 of
/// the id, so `74` → `NzQ=`. Algolia records and category URLs carry ids.
String categoryUidFromId(String id) => base64.encode(utf8.encode(id.trim()));

/// The numeric id behind a category [uid], or null when it isn't one.
String? categoryIdFromUid(String uid) {
  try {
    final id = utf8.decode(base64.decode(uid.trim()));
    return RegExp(r'^\d+$').hasMatch(id) ? id : null;
  } on FormatException {
    return null;
  }
}

/// A catalogue category (menu tree node / category landing).
class Category {
  const Category({
    required this.uid,
    required this.name,
    required this.urlKey,
    this.image,
    this.productCount = 0,
    this.includeInMenu = true,
    this.children = const <Category>[],
  });

  final String uid;
  final String name;
  final String urlKey;
  final String? image;
  final int productCount;

  /// Whether Magento flags this category for navigation surfaces.
  final bool includeInMenu;
  final List<Category> children;
}

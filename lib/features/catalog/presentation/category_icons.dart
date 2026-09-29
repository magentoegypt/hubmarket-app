import 'package:flutter/material.dart';

/// Icons for Hub Market's categories, by `url_key` — the same in both store
/// views (verified against the live `categoryList`, 29 Sep 2026: the menu's
/// top level is super-market, pharmacy, furniture, clothes, games, fmcg,
/// health, electronics, home-appliances, fresh-food).
const Map<String, IconData> _byUrlKey = <String, IconData>{
  'super-market': Icons.local_grocery_store_outlined, // Grocery
  'grocery': Icons.local_grocery_store_outlined,
  'fresh-food': Icons.eco_outlined,
  'pharmacy': Icons.local_pharmacy_outlined,
  'furniture': Icons.chair_outlined,
  'clothes': Icons.checkroom_outlined, // Fashion
  'games': Icons.toys_outlined, // Kids & Toys
  'fmcg': Icons.shopping_basket_outlined,
  'health': Icons.face_retouching_natural_outlined, // Cosmetics
  'electronics': Icons.devices_outlined, // Electronics & Tech
  'home-appliances': Icons.kitchen_outlined,
  'mobile-tablet': Icons.smartphone_outlined,
  'computer': Icons.computer_outlined,
  'bags': Icons.shopping_bag_outlined,
  'sports': Icons.sports_soccer_outlined,
  'gear': Icons.fitness_center_outlined,
  'lamps': Icons.lightbulb_outline, // Lighting
  'building-materials': Icons.construction_outlined,
  'sale': Icons.local_offer_outlined,
};

/// Keywords for categories added later, matched in the url_key or the
/// English name; first match wins.
const List<(List<String>, IconData)> _byKeyword = <(List<String>, IconData)>[
  (['grocer', 'market', 'supermarket'], Icons.local_grocery_store_outlined),
  (['fresh', 'food', 'dairy'], Icons.eco_outlined),
  (['pharma', 'medic'], Icons.local_pharmacy_outlined),
  (['furnit', 'sofa'], Icons.chair_outlined),
  (['fashion', 'cloth', 'wear'], Icons.checkroom_outlined),
  (['toy', 'kid', 'game'], Icons.toys_outlined),
  (['cosmet', 'beauty', 'perfum'], Icons.face_retouching_natural_outlined),
  (['applian', 'kitchen'], Icons.kitchen_outlined),
  (['mobile', 'phone', 'tablet'], Icons.smartphone_outlined),
  (['comput', 'laptop'], Icons.computer_outlined),
  (['electr', 'tech'], Icons.devices_outlined),
  (['bag'], Icons.shopping_bag_outlined),
  (['sport', 'fitness'], Icons.sports_soccer_outlined),
  (['lamp', 'light'], Icons.lightbulb_outline),
  (['build', 'construct'], Icons.construction_outlined),
  (['sale', 'offer', 'deal'], Icons.local_offer_outlined),
];

/// The icon for a category: by its url_key, else a keyword in the url_key or
/// name, else the neutral category glyph.
IconData categoryIcon(String urlKey, String name) {
  final key = urlKey.trim().toLowerCase();
  final known = _byUrlKey[key];
  if (known != null) return known;
  final text = '$key ${name.toLowerCase()}';
  for (final (words, icon) in _byKeyword) {
    if (words.any(text.contains)) return icon;
  }
  return Icons.category_outlined;
}

import 'package:flutter/material.dart';
import '../../../app/theme/hub_icons.dart';

/// Icons for Hub Market's categories, by `url_key` — the same in both store
/// views (verified against the live `categoryList`, 29 Sep 2026: the menu's
/// top level is super-market, pharmacy, furniture, clothes, games, fmcg,
/// health, electronics, home-appliances, fresh-food).
const Map<String, IconData> _byUrlKey = <String, IconData>{
  'super-market': HubIcons.shoppingCart, // Grocery
  'grocery': HubIcons.shoppingCart,
  'fresh-food': HubIcons.leaf,
  'pharmacy': HubIcons.pill,
  'furniture': HubIcons.armchair,
  'clothes': HubIcons.shirt, // Fashion
  'games': HubIcons.puzzle, // Kids & Toys
  'fmcg': HubIcons.shoppingBasket,
  'health': HubIcons.sparkles, // Cosmetics
  'electronics': HubIcons.monitorSmartphone, // Electronics & Tech
  'home-appliances': HubIcons.refrigerator,
  'mobile-tablet': HubIcons.smartphone,
  'computer': HubIcons.laptop,
  'bags': HubIcons.shoppingBag,
  'sports': HubIcons.trophy,
  'gear': HubIcons.dumbbell,
  'lamps': HubIcons.lightbulb, // Lighting
  'building-materials': HubIcons.construction,
  'sale': HubIcons.tag,
};

/// Keywords for categories added later, matched in the url_key or the
/// English name; first match wins.
const List<(List<String>, IconData)> _byKeyword = <(List<String>, IconData)>[
  (['grocer', 'market', 'supermarket'], HubIcons.shoppingCart),
  (['fresh', 'food', 'dairy'], HubIcons.leaf),
  (['pharma', 'medic'], HubIcons.pill),
  (['furnit', 'sofa'], HubIcons.armchair),
  (['fashion', 'cloth', 'wear'], HubIcons.shirt),
  (['toy', 'kid', 'game'], HubIcons.puzzle),
  (['cosmet', 'beauty', 'perfum'], HubIcons.sparkles),
  (['applian', 'kitchen'], HubIcons.refrigerator),
  (['mobile', 'phone', 'tablet'], HubIcons.smartphone),
  (['comput', 'laptop'], HubIcons.laptop),
  (['electr', 'tech'], HubIcons.monitorSmartphone),
  (['bag'], HubIcons.shoppingBag),
  (['sport', 'fitness'], HubIcons.trophy),
  (['lamp', 'light'], HubIcons.lightbulb),
  (['build', 'construct'], HubIcons.construction),
  (['sale', 'offer', 'deal'], HubIcons.tag),
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
  return HubIcons.layoutGrid;
}

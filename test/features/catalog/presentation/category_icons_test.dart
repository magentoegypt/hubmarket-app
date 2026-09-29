import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/catalog/presentation/category_icons.dart';

void main() {
  test("every top-level Hub Market category has its own icon", () {
    // The menu's top level on the live store (categoryList, en), 29 Sep 2026.
    const topLevel = <String, String>{
      'super-market': 'Grocery',
      'pharmacy': 'Pharmacy',
      'furniture': 'Furniture',
      'clothes': 'Fashion',
      'games': 'Kids & Toys',
      'fmcg': 'FMCG',
      'health': 'Cosmetics',
      'electronics': 'Electronics & Tech',
      'home-appliances': 'Home Appliances',
      'fresh-food': 'Fresh Food',
    };
    final icons = {
      for (final entry in topLevel.entries)
        entry.key: categoryIcon(entry.key, entry.value),
    };

    expect(icons['super-market'], Icons.local_grocery_store_outlined);
    expect(icons['pharmacy'], Icons.local_pharmacy_outlined);
    expect(icons['furniture'], Icons.chair_outlined);
    expect(icons['clothes'], Icons.checkroom_outlined);
    expect(icons['games'], Icons.toys_outlined);
    expect(icons['health'], Icons.face_retouching_natural_outlined);
    expect(icons['electronics'], Icons.devices_outlined);
    expect(icons['home-appliances'], Icons.kitchen_outlined);
    expect(icons['fresh-food'], Icons.eco_outlined);
    expect(icons.values.toSet(), hasLength(topLevel.length),
        reason: 'no two top-level categories share an icon');
    expect(icons.values, isNot(contains(Icons.category_outlined)));
  });

  test('url_keys are the same in Arabic, so the icon does not change', () {
    expect(categoryIcon('furniture', 'اثاث'), Icons.chair_outlined);
    expect(categoryIcon('games', 'الاطفال والالعاب'), Icons.toys_outlined);
  });

  test('new categories match by keyword, anything else is neutral', () {
    expect(categoryIcon('kids-toys', 'Kids Toys'), Icons.toys_outlined);
    expect(categoryIcon('mens-wear', 'Menswear'), Icons.checkroom_outlined);
    expect(categoryIcon('amira', 'Amira'), Icons.category_outlined);
    expect(categoryIcon('', ''), Icons.category_outlined);
  });
}

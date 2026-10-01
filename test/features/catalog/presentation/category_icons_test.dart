import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/catalog/presentation/category_icons.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';

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

    expect(icons['super-market'], HubIcons.shoppingCart);
    expect(icons['pharmacy'], HubIcons.pill);
    expect(icons['furniture'], HubIcons.armchair);
    expect(icons['clothes'], HubIcons.shirt);
    expect(icons['games'], HubIcons.puzzle);
    expect(icons['health'], HubIcons.sparkles);
    expect(icons['electronics'], HubIcons.monitorSmartphone);
    expect(icons['home-appliances'], HubIcons.refrigerator);
    expect(icons['fresh-food'], HubIcons.leaf);
    expect(icons.values.toSet(), hasLength(topLevel.length),
        reason: 'no two top-level categories share an icon');
    expect(icons.values, isNot(contains(HubIcons.layoutGrid)));
  });

  test('url_keys are the same in Arabic, so the icon does not change', () {
    expect(categoryIcon('furniture', 'اثاث'), HubIcons.armchair);
    expect(categoryIcon('games', 'الاطفال والالعاب'), HubIcons.puzzle);
  });

  test('new categories match by keyword, anything else is neutral', () {
    expect(categoryIcon('kids-toys', 'Kids Toys'), HubIcons.puzzle);
    expect(categoryIcon('mens-wear', 'Menswear'), HubIcons.shirt);
    expect(categoryIcon('amira', 'Amira'), HubIcons.layoutGrid);
    expect(categoryIcon('', ''), HubIcons.layoutGrid);
  });
}

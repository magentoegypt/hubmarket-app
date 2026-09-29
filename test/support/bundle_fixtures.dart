import 'package:hubmarket_app/features/catalog/data/product_marketplace_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/bundle_product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_marketplace.dart';

import 'marketplace_fakes.dart';

/// Bundle data as `HmProductMarketplace` returns it.

Map<String, dynamic> _money(double value) => {'value': value, 'currency': 'AED'};

Map<String, dynamic> _range(double regular, double finalPrice) => {
  'minimum_price': {
    'regular_price': _money(regular),
    'final_price': _money(finalPrice),
  },
};

/// A simple child product.
Map<String, dynamic> childJson(
  String sku,
  String name, {
  required double regular,
  double? finalPrice,
  bool inStock = true,
  String? image,
}) => {
  '__typename': 'SimpleProduct',
  'sku': sku,
  'name': name,
  'url_key': sku.toLowerCase(),
  'stock_status': inStock ? 'IN_STOCK' : 'OUT_OF_STOCK',
  // No picture by default: a network image can't load in a widget test.
  'image': image == null ? null : {'url': image},
  'price_range': _range(regular, finalPrice ?? regular),
};

/// A configurable child with sizes S (AED 30) and M (AED 34, out of stock
/// when [mSoldOut]).
Map<String, dynamic> configurableChildJson({bool mSoldOut = false}) => {
  '__typename': 'ConfigurableProduct',
  'sku': 'TOP',
  'name': 'Training Top',
  'url_key': 'training-top',
  'stock_status': 'IN_STOCK',
  'image': null,
  'price_range': _range(30, 30),
  'configurable_options': [
    {
      'attribute_code': 'size',
      'label': 'Size',
      'values': [
        {'uid': 'Y29uZmlndXJhYmxlLzE0NC8xNjc=', 'value_index': 167, 'label': 'S'},
        {'uid': 'Y29uZmlndXJhYmxlLzE0NC8xNjg=', 'value_index': 168, 'label': 'M'},
      ],
    },
  ],
  'variants': [
    {
      'attributes': [
        {'code': 'size', 'value_index': 167},
      ],
      'product': {
        'sku': 'TOP-S',
        'stock_status': 'IN_STOCK',
        'price_range': _range(30, 30),
      },
    },
    {
      'attributes': [
        {'code': 'size', 'value_index': 168},
      ],
      'product': {
        'sku': 'TOP-M',
        'stock_status': mSoldOut ? 'OUT_OF_STOCK' : 'IN_STOCK',
        'price_range': _range(34, 34),
      },
    },
  ],
};

Map<String, dynamic> selectionJson(
  String uid,
  Map<String, dynamic> product, {
  bool isDefault = false,
  int position = 1,
  double quantity = 1,
  bool canChangeQuantity = false,
}) => {
  'uid': uid,
  'label': product['name'],
  'quantity': quantity,
  'can_change_quantity': canChangeQuantity,
  'is_default': isDefault,
  'position': position,
  'price': 0,
  'price_type': 'FIXED',
  'product': product,
};

Map<String, dynamic> optionJson(
  String uid,
  String title,
  List<Map<String, dynamic>> selections, {
  String type = 'checkbox',
  bool required = true,
  int position = 1,
}) => {
  'uid': uid,
  'title': title,
  'required': required,
  'type': type,
  'position': position,
  'options': selections,
};

/// Live `home-fitness-starter-pack` (29 Sep 2026): four required options of
/// one default selection each; AED 72 at regular prices, AED 60.56 with the
/// bundle's discount.
Map<String, dynamic> fitnessPackJson({String? sellerCode = 'test-1'}) => {
  '__typename': 'BundleProduct',
  'sku': 'HM-DEMO-BUNDLE-FITNESS',
  'hm_seller': sellerCode == null ? null : sellerJson(sellerCode, 'Test 1'),
  'dynamic_price': true,
  'price_range': {
    'minimum_price': {
      'regular_price': _money(72),
      'final_price': _money(60.56),
    },
    'maximum_price': {
      'regular_price': _money(72),
      'final_price': _money(60.56),
    },
  },
  'items': [
    optionJson('YnVuZGxlLzIw', 'Yoga Bag', [
      selectionJson(
        'YnVuZGxlLzIwLzYzLzE=',
        childJson('24-WB01', 'Voyage Yoga Bag', regular: 32),
        isDefault: true,
      ),
    ]),
    optionJson('YnVuZGxlLzIx', 'Cardio Ball', position: 2, [
      selectionJson(
        'YnVuZGxlLzIxLzY0LzE=',
        childJson('24-UG07', 'Dual Handle Cardio Ball', regular: 12),
        isDefault: true,
      ),
    ]),
    optionJson('YnVuZGxlLzIy', 'Yoga Brick', position: 3, [
      selectionJson(
        'YnVuZGxlLzIyLzY1LzE=',
        childJson('24-WG084', 'Sprite Foam Yoga Brick', regular: 5, finalPrice: 4.25),
        isDefault: true,
      ),
    ]),
    optionJson('YnVuZGxlLzIz', 'Stasis Ball', position: 4, [
      selectionJson(
        'YnVuZGxlLzIzLzY2LzE=',
        childJson('24-WG081-gray', 'Sprite Stasis Ball 55 cm', regular: 23),
        isDefault: true,
      ),
    ]),
  ],
};

/// A bundle with choices: a radio "Top" (a configurable, or a cheaper plain
/// tee), a required "Mat" with no default, an optional checkbox "Extras" and
/// a "Bottle" whose quantity the shopper sets. Cheapest package AED 44 →
/// AED 39.60 (10% off).
Map<String, dynamic> kitBuilderJson({bool mSoldOut = false}) => {
  '__typename': 'BundleProduct',
  'sku': 'KIT-BUILDER',
  'hm_seller': sellerJson('loly', 'loly store'),
  'dynamic_price': true,
  'price_range': {
    'minimum_price': {
      'regular_price': _money(44),
      'final_price': _money(39.6),
    },
    'maximum_price': {
      'regular_price': _money(95),
      'final_price': _money(85.5),
    },
  },
  'items': [
    optionJson('b3B0L3RvcA==', 'Top', type: 'radio', [
      selectionJson('c2VsL3RvcA==', configurableChildJson(mSoldOut: mSoldOut), isDefault: true),
      selectionJson('c2VsL3RlZQ==', childJson('TEE', 'Plain Tee', regular: 20), position: 2),
    ]),
    optionJson('b3B0L21hdA==', 'Mat', type: 'select', position: 2, [
      selectionJson('c2VsL21hdA==', childJson('MAT', 'Yoga Mat', regular: 18)),
      selectionJson('c2VsL3Bybw==', childJson('MAT-PRO', 'Pro Mat', regular: 40), position: 2),
    ]),
    optionJson('b3B0L2V4dA==', 'Extras', required: false, position: 3, [
      selectionJson('c2VsL3N0cmFw', childJson('STRAP', 'Yoga Strap', regular: 6)),
      selectionJson('c2VsL3Rvd2Vs', childJson('TOWEL', 'Gym Towel', regular: 9), position: 2),
    ]),
    optionJson('b3B0L2JvdA==', 'Bottle', position: 4, [
      selectionJson(
        'c2VsL2JvdA==',
        childJson('BOTTLE', 'Water Bottle', regular: 3, inStock: true),
        isDefault: true,
        canChangeQuantity: true,
        quantity: 2,
      ),
    ]),
  ],
};

ProductMarketplace marketplaceOf(Map<String, dynamic> json) =>
    productMarketplaceFromJson(json);

BundleProduct bundleOf(Map<String, dynamic> json) =>
    productMarketplaceFromJson(json).bundle!;

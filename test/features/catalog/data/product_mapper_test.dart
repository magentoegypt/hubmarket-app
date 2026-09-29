import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/catalog/data/product_mapper.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';

Map<String, dynamic> _json({Object? isNew, Object? isBestseller}) => {
  'sku': 'SKU1',
  'name': 'Test Product',
  'url_key': 'test-product',
  'stock_status': 'IN_STOCK',
  if (isNew != null) 'is_new_arrival': isNew,
  if (isBestseller != null) 'is_bestseller': isBestseller,
};

void main() {
  group('productFromJson badge mapping', () {
    test('no flags => no badge', () {
      expect(productFromJson(_json()).badge, ProductBadge.none);
    });

    test('is_new_arrival => isNew', () {
      expect(
        productFromJson(_json(isNew: true)).badge,
        ProductBadge.isNew,
      );
    });

    test('is_bestseller => bestseller', () {
      expect(
        productFromJson(_json(isBestseller: true)).badge,
        ProductBadge.bestseller,
      );
    });

    test('both flags => bestseller wins', () {
      expect(
        productFromJson(_json(isNew: true, isBestseller: true)).badge,
        ProductBadge.bestseller,
      );
    });

    test('tolerates Magento Int (1/0) flags', () {
      expect(productFromJson(_json(isNew: 1)).badge, ProductBadge.isNew);
      expect(productFromJson(_json(isBestseller: 0)).badge, ProductBadge.none);
    });
  });
}

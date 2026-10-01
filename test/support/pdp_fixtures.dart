import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';

import 'marketplace_fakes.dart';

/// Call from `main`: gives the image cache a temporary folder, so a network image
/// (the gallery's photos) fails quietly — HTTP is stubbed to 400 in widget tests —
/// instead of on a missing `path_provider` plugin. The photos never arrive; their
/// error tile is drawn in their place.
void quietNetworkImages() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => Directory.systemTemp.createTempSync('hm_img').path,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}

/// The product of the Figma product-page frames (14, 14c, 15, 15b): loly store's
/// Floral Print Corset-Waist Tie Dress, with the colours and sizes, the 27 reviews
/// and the neighbours the frames draw — as English and Arabic store views serve it.
/// Pictures are left out: a network image can't load in a widget test.

Money _aed(double amount) => Money(amount: amount, currency: 'AED');

/// The live `hm_home_trust` block (Content › Blocks), English and Arabic: what the
/// product page's delivery card is made from.
const String kTrustBlockEn =
    '<div class="hm-trust">'
    '<div class="hm-trust__item"><span class="hm-trust__title">Trusted Sellers'
    '</span><span class="hm-trust__text">Verified &amp; approved</span></div>'
    '<div class="hm-trust__item"><span class="hm-trust__title">Secure Payments'
    '</span><span class="hm-trust__text">Cash on delivery, Visa, Mastercard'
    '</span></div>'
    '<div class="hm-trust__item"><span class="hm-trust__title">Fast Delivery'
    '</span><span class="hm-trust__text">Nationwide</span></div>'
    '<div class="hm-trust__item"><span class="hm-trust__title">Easy Returns'
    '</span><span class="hm-trust__text">14-day return policy</span></div>'
    '</div>';
const String kTrustBlockAr =
    '<div class="hm-trust">'
    '<div class="hm-trust__item"><span class="hm-trust__title">بائعون موثوقون'
    '</span><span class="hm-trust__text">تمت المراجعة والاعتماد</span></div>'
    '<div class="hm-trust__item"><span class="hm-trust__title">مدفوعات آمنة'
    '</span><span class="hm-trust__text">الدفع عند الاستلام وفيزا وماستركارد'
    '</span></div>'
    '<div class="hm-trust__item"><span class="hm-trust__title">توصيل سريع'
    '</span><span class="hm-trust__text">لجميع المناطق</span></div>'
    '<div class="hm-trust__item"><span class="hm-trust__title">إرجاع سهل'
    '</span><span class="hm-trust__text">سياسة إرجاع خلال 14 يومًا</span></div>'
    '</div>';

/// Colour option values: valueIndex → (English, Arabic, swatch).
const List<(int, String, String, String)> _colours = [
  (11, 'Beige floral', 'بيج مزهر', '#d9c2a3'),
  (12, 'Charcoal', 'فحمي', '#1f2937'),
  (13, 'Sky blue', 'أزرق سماوي', '#9db4d0'),
];

const List<(int, String)> _sizes = [
  (21, 'XS'),
  (22, 'S'),
  (23, 'M'),
  (24, 'L'),
  (25, 'XL'),
];

/// The dress. XL is sold out; three are left in M (the store's "Only X left"
/// threshold). [gallery] gives the photo count the pager shows; [withCategory]
/// files it under a category, which is what shows "See all" on its rail.
ProductDetail floralDressDetail({
  String locale = 'en',
  int gallery = 4,
  List<ProductReview>? reviews,
  int reviewCount = 27,
  bool withNeighbours = true,
  bool withCategory = false,
}) {
  final ar = locale == 'ar';
  String text(String en, String arabic) => ar ? arabic : en;
  return ProductDetail(
    sku: 'LOLY-DR-0231',
    name: text(
      'Floral Print Corset-Waist Tie Dress',
      'فستان صدر طباعة الأزهار رباط مشد خصر',
    ),
    urlKey: 'floral-dress',
    typeId: 'configurable',
    description: text(
      'A soft crepe dress with a corset waist that ties at the back.',
      'فستان كريب ناعم بخصر مشد يُربط من الخلف.',
    ),
    attributes: [
      ProductAttribute(
        code: 'material',
        value: text('Polyester crepe', 'كريب بوليستر'),
      ),
      ProductAttribute(
        code: 'sleeve_length',
        value: text('Short sleeve', 'كم قصير'),
      ),
      ProductAttribute(
        code: 'color',
        value: text('Beige floral', 'بيج مزهر'),
      ),
    ],
    gallery: [
      for (var i = 0; i < gallery; i++)
        'https://hub-market.magento2.click/media/catalog/product/f/d/dress-$i.jpg',
    ],
    regularPrice: _aed(50),
    finalPrice: _aed(50),
    options: [
      ConfigurableOption(
        attributeCode: 'color',
        label: text('Colour', 'اللون'),
        values: [
          for (final (index, en, arabic, hex) in _colours)
            SwatchValue(
              valueIndex: index,
              label: text(en, arabic),
              uid: 'uid-color-$index',
              swatchColor: hex,
            ),
        ],
      ),
      ConfigurableOption(
        attributeCode: 'size',
        label: text('Size', 'المقاس'),
        values: [
          for (final (index, label) in _sizes)
            SwatchValue(
              valueIndex: index,
              label: label,
              uid: 'uid-size-$index',
            ),
        ],
      ),
    ],
    variants: [
      for (final (colour, _, _, _) in _colours)
        for (final (size, _) in _sizes)
          ProductVariant(
            sku: 'LOLY-DR-0231-$colour-$size',
            attributes: {'color': colour, 'size': size},
            price: _aed(50),
            inStock: size != 25,
            onlyLeft: size == 23 ? 3 : null,
          ),
    ],
    ratingSummary: 86,
    reviewCount: reviewCount,
    reviews: reviews ?? floralDressReviews(locale: locale),
    alsoLike: withNeighbours ? floralDressNeighbours(locale: locale) : const [],
    // Filed under Dresses: "Looking similar" then has somewhere to send "See all".
    categories: withCategory
        ? [
            ProductCategoryRef(
              uid: 'dresses',
              name: text('Dresses', 'فساتين'),
              level: 3,
            ),
          ]
        : const [],
  );
}

/// 27 reviews, as the 15 frame counts them: 15 × 5★, 7 × 4★, 3 × 3★, 1 × 2★,
/// 1 × 1★ — the newest being Nour A.'s.
List<ProductReview> floralDressReviews({String locale = 'en'}) {
  final ar = locale == 'ar';
  // After the two named reviews below (5★ and 3★): the other 25.
  final stars = [
    for (var i = 0; i < 14; i++) 5,
    for (var i = 0; i < 7; i++) 4,
    for (var i = 0; i < 2; i++) 3,
    2,
    1,
  ];
  return [
    ProductReview(
      nickname: ar ? 'نور أ.' : 'Nour A.',
      summary: '',
      text: ar
          ? 'قماش جميل والمقاس مضبوط. رباط الخصر يعطي شكلًا رائعًا. وصل خلال يومين.'
          : 'Beautiful fabric and the fit is true to size. The tie waist is very flattering. Arrived in 2 days.',
      averageRating: 100,
      date: '2026-09-12 10:24:33',
    ),
    ProductReview(
      nickname: ar ? 'ريم ك.' : 'Reem K.',
      summary: '',
      text: ar
          ? 'الطبعة جميلة لكن الطول أقصر مما توقعت لمقاس M.'
          : 'Nice print but the length was shorter than I expected for size M.',
      averageRating: 60,
      date: '2026-09-03 18:02:11',
    ),
    for (var i = 0; i < stars.length; i++)
      ProductReview(
        nickname: 'Reviewer ${i + 3}',
        summary: '',
        text: '',
        averageRating: stars[i] * 20,
        date: '2026-08-${(i % 27 + 1).toString().padLeft(2, '0')} 09:00:00',
      ),
  ];
}

/// The three cards of "Looking similar" / "You might also like".
List<Product> floralDressNeighbours({String locale = 'en'}) {
  final ar = locale == 'ar';
  final seller = ar ? 'متجر لولي' : 'loly store';
  return [
    Product(
      sku: 'TSHIRT',
      name: ar ? 'تيشيرت قصير ياقة مربع' : 'Short Square-Neck T-Shirt',
      urlKey: 'short-square-neck-t-shirt',
      regularPrice: _aed(43),
      finalPrice: _aed(43),
      typeId: 'simple',
      sellerKnown: true,
      sellerName: seller,
    ),
    Product(
      sku: 'SHORTS',
      name: ar ? 'شورت قصير جيب جانبي' : 'Short Shorts with Flap Side Pocket',
      urlKey: 'short-shorts',
      regularPrice: _aed(15),
      finalPrice: _aed(13),
      typeId: 'simple',
      sellerKnown: true,
      sellerName: seller,
    ),
    Product(
      sku: 'POLO',
      name: ar ? 'تيشيرت بولو' : 'Polo Shirt',
      urlKey: 'polo-shirt',
      regularPrice: _aed(13),
      finalPrice: _aed(13),
      typeId: 'simple',
      sellerKnown: true,
      sellerName: seller,
    ),
  ];
}

/// `HmProductMarketplace`: loly store sells the dress; ronza and moo store offer
/// it too.
Map<String, dynamic> floralDressMarketplaceItem({String locale = 'en'}) {
  final ar = locale == 'ar';
  Map<String, dynamic> offer(
    int id,
    String code,
    String name,
    double price,
    double rating,
  ) => {
    '__typename': 'HmProductOffer',
    'uid': 'uid-$id',
    'sku': 'SKU-$id',
    'url_key': 'offer-$id',
    'type_id': 'simple',
    'seller': sellerJson(code, name, rating: rating),
    'price': {'value': price, 'currency': 'AED'},
    'regular_price': {'value': price, 'currency': 'AED'},
    'stock_status': 'IN_STOCK',
    'dispatch_time': null,
  };
  return {
    '__typename': 'ConfigurableProduct',
    'sku': 'LOLY-DR-0231',
    'hm_seller': sellerJson('loly', ar ? 'متجر لولي' : 'loly store', rating: 4.3),
    'hm_offer_count': 2,
    'hm_other_offers': [
      offer(2287, 'ronza', 'ronza', 55, 4.4),
      offer(2150, 'moo', 'moo store', 58, 4.8),
    ],
  };
}

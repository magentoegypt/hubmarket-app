/// `hmAppHome` as the contract serves it, one section of every type, in the
/// order the backend seeds them (MagentoEgypt_HubApp SeedHomeSections). Images
/// are left out so widget tests never touch the network.
library;

Map<String, dynamic> _link(
  String type,
  String url, {
  String? uid,
  String? code,
}) => {'type': type, 'url': url, 'path': null, 'uid': uid, 'code': code};

Map<String, dynamic> _money(double value) => {
  'value': value,
  'currency': 'AED',
};

Map<String, dynamic> product(
  String name,
  double price, {
  double? was,
  String type = 'SimpleProduct',
  String? seller,
  double? rating,
  int reviews = 0,
}) => {
  '__typename': type,
  'sku': name.toUpperCase().replaceAll(' ', '-'),
  'name': name,
  'url_key': name.toLowerCase().replaceAll(' ', '-'),
  'stock_status': 'IN_STOCK',
  'new_from_date': null,
  'new_to_date': null,
  'image': {'url': null},
  'price_range': {
    'minimum_price': {
      'regular_price': _money(was ?? price),
      'final_price': _money(price),
    },
  },
  'hm_seller': seller == null ? null : {'code': seller, 'name': seller},
  // Magento's rating_summary is a percentage: 4.7 stars is 94.
  if (rating != null) 'rating_summary': rating * 20,
  if (rating != null) 'review_count': reviews,
};

Map<String, dynamic> store(
  String code,
  String name, {
  double? rating,
  int products = 8,
  String? dispatch,
}) => {
  'code': code,
  'vendor_entity_id': code.length,
  'name': name,
  'logo_url': null,
  'rating': rating,
  'review_count': 12,
  'product_count': products,
  'dispatch_time': dispatch == null
      ? null
      : {'code': 'next_day', 'label': dispatch, 'source': 'DECLARED'},
  'is_featured': true,
  'joined_at': '2026-08-01T08:00:00Z',
  'link': _link(
    'STORE',
    'https://hub-market.magento2.click/en/shop/$code',
    code: code,
  ),
};

Map<String, dynamic> _section(
  int id,
  String type, {
  String? title,
  String? subtitle,
  String? endsAt,
  String? countdown,
  Map<String, dynamic>? more,
  List<Map<String, dynamic>>? banners,
  List<Map<String, dynamic>>? categories,
  Map<String, dynamic>? block,
  List<Map<String, dynamic>>? brands,
  List<Map<String, dynamic>>? bundles,
  List<Map<String, dynamic>>? stores,
  List<Map<String, dynamic>>? products,
}) => {
  'id': id,
  'type': type,
  'title': title,
  'subtitle': subtitle,
  'limit': 8,
  'ends_at': endsAt,
  'countdown_ends_at': countdown,
  'personalizable': type == 'PICKED_FOR_YOU',
  'more_link': more,
  'banners': banners,
  'categories': categories,
  'cms_block': block,
  'brands': brands,
  'bundles': bundles,
  'stores': stores,
  'products': products,
};

const String kPromosHtml =
    '<div class="hm-promos"><a class="hm-promo" href="https://hub-market.magento2.click/en/electronics.html"><span class="hm-promo__icon">⚡</span><span class="hm-promo__kicker">Flash Sale</span><span class="hm-promo__title">Up to 50% Off Electronics &amp; Tech</span><span class="hm-promo__text">Today only</span></a></div>';

const String kTrustHtml =
    '<div class="hm-trust"><div class="hm-trust__item"><span class="hm-trust__title">Trusted Sellers</span><span class="hm-trust__text">Verified &amp; approved</span></div><div class="hm-trust__item"><span class="hm-trust__title">Secure Payments</span><span class="hm-trust__text">Cash on delivery and cards</span></div><div class="hm-trust__item"><span class="hm-trust__title">WhatsApp Support</span><span class="hm-trust__text">24/7 customer care</span></div></div>';

/// The whole Home. [countdown] is when Today's Deals ends.
Map<String, dynamic> hmHomeJson({
  required DateTime countdown,
  bool arabic = false,
}) {
  String t(String en, String ar) => arabic ? ar : en;
  return {
    'store_code': arabic ? 'ar' : 'en',
    'generated_at': '2026-09-30T06:00:00Z',
    'sections': [
      _section(
        1,
        'DELIVERY_STRIP',
        block: {
          'identifier': 'hm_delivery_promise',
          'title': null,
          'content': t(
            '<p>Free delivery on qualifying orders</p>',
            '<p>توصيل مجاني للطلبات المؤهلة</p>',
          ),
        },
      ),
      _section(
        2,
        'HERO_BANNERS',
        banners: [
          {
            'id': 1,
            'slot': 'SLIDE',
            'title': t(
              'Fresh Groceries From Local Vendors',
              'بقالة طازجة من بائعين محليين',
            ),
            'kicker': t('SAME-DAY DELIVERY', 'توصيل في نفس اليوم'),
            'subtitle': t(
              'Organic produce, dairy and pantry essentials, delivered in hours.',
              'منتجات عضوية وألبان ومستلزمات تصلك خلال ساعات.',
            ),
            'cta_label': t('Shop Grocery', 'تسوّق البقالة'),
            'image_url': null,
            'tone': '#123620',
            'accent': '#0F7B3F',
            'link': _link(
              'CATEGORY',
              'https://hub-market.magento2.click/en/super-market.html',
              uid: 'Mw==',
            ),
          },
          {
            'id': 2,
            'slot': 'SLIDE',
            'title': t('Top Deals in Electronics', 'أفضل عروض الإلكترونيات'),
            'kicker': null,
            'subtitle': null,
            'cta_label': null,
            'image_url': null,
            'tone': '#0F2144',
            'accent': null,
            'link': _link(
              'DEALS',
              'https://hub-market.magento2.click/en/deals',
            ),
          },
          {
            'id': 3,
            'slot': 'TILE',
            'title': t('Electronics Deals', 'عروض الإلكترونيات'),
            'kicker': null,
            'subtitle': t(
              'Phones, tablets & accessories',
              'هواتف وأجهزة لوحية وإكسسوارات',
            ),
            'cta_label': null,
            'image_url': null,
            'tone': '#0F2144',
            'accent': null,
            'link': _link(
              'CATEGORY',
              'https://hub-market.magento2.click/en/electronics.html',
              uid: 'MTM=',
            ),
          },
          {
            'id': 4,
            'slot': 'TILE',
            'title': t('Bundle Deals', 'عروض الباقات'),
            'kicker': t('🎁 This week only', '🎁 هذا الأسبوع فقط'),
            'subtitle': t('Buy more, pay less', 'اشترِ أكثر وادفع أقل'),
            'cta_label': null,
            'image_url': null,
            'tone': null,
            'accent': '#F26522',
            'link': _link(
              'BUNDLES',
              'https://hub-market.magento2.click/en/bundles',
            ),
          },
        ],
      ),
      _section(
        3,
        'CATEGORY_CHIPS',
        title: t('Shop by category', 'تسوّق حسب الفئة'),
        categories: [
          for (final (i, c) in [
            ('super-market', t('Grocery', 'البقالة'), '🛒', 7),
            ('pharmacy', t('Pharmacy', 'الصيدلية'), '💊', 8),
            ('furniture', t('Furniture', 'الأثاث'), '🛋️', 7),
            ('clothes', t('Fashion', 'الأزياء'), '👗', 19),
            ('fmcg', 'FMCG', '📦', 5),
          ].indexed)
            {
              'id': 3 + i,
              'uid': 'uid-${c.$1}',
              'name': c.$2,
              'url_key': c.$1,
              'product_count': c.$4,
              'icon': c.$3,
              'tint': i,
              'link': _link(
                'CATEGORY',
                'https://hub-market.magento2.click/en/${c.$1}.html',
                uid: 'uid-${c.$1}',
              ),
            },
        ],
      ),
      _section(
        4,
        'TODAYS_DEALS',
        title: t("Today's Deals", 'عروض اليوم'),
        countdown: countdown.toUtc().toIso8601String(),
        more: _link('DEALS', 'https://hub-market.magento2.click/en/deals'),
        products: [
          product(
            t('Egyptian Rice 1 kg', 'أرز مصري ١ كجم'),
            25,
            was: 35,
            seller: 'walmart',
          ),
          product(
            t('Modern Executive Desk', 'مكتب تنفيذي حديث'),
            263,
            was: 350,
            seller: 'MIA CO',
          ),
        ],
      ),
      _section(
        5,
        'PICKED_FOR_YOU',
        title: t('Picked For You', 'مختارات لك'),
        subtitle: t(
          'Personalised recommendations based on your search history & behaviour',
          'توصيات مخصّصة حسب عمليات بحثك',
        ),
        products: [
          product(t('Dual Handle Cardio Ball', 'كرة تمارين بمقبضين'), 12),
        ],
      ),
      _section(
        6,
        'FEATURED_STORES',
        title: t('Featured Stores', 'متاجر مميّزة'),
        subtitle: t(
          'Verified sellers on Hub Market',
          'بائعون موثّقون على هب ماركت',
        ),
        stores: [
          store('ENARA', 'ENARA', rating: 4.4, products: 8, dispatch: '24h'),
          store('loly', 'loly', rating: 4.8, products: 7, dispatch: '~2 days'),
        ],
      ),
      _section(
        7,
        'CATEGORY_RAIL',
        title: t('Grocery Essentials', 'أساسيات البقالة'),
        subtitle: t('Fresh & delivered today', 'طازجة وتصل اليوم'),
        more: _link(
          'CATEGORY',
          'https://hub-market.magento2.click/en/super-market.html',
          uid: 'Mw==',
        ),
        products: [
          product(t('Dolphin Tuna Chunks', 'قطع تونة دولفين'), 43, was: 48),
        ],
      ),
      // Emptied by the backend (a provider with nothing to show): never drawn.
      _section(
        8,
        'CATEGORY_RAIL',
        title: t('Empty Rail', 'قسم فارغ'),
        products: [],
      ),
      _section(
        9,
        'BUNDLE_DEALS',
        title: t('Bundle Deals', 'عروض الباقات'),
        subtitle: t(
          'Buy together, save more — curated multi-item bundles',
          'اشترِ معًا ووفّر أكثر',
        ),
        bundles: [
          {
            'uid': 'MTAw',
            'sku': 'fitness-pack',
            'name': t('Home Fitness Starter Pack', 'حزمة اللياقة المنزلية'),
            'url_key': 'home-fitness-starter-pack',
            'image_url': null,
            'seller': {'code': 'test1', 'name': 'Test 1', 'link': null},
            'description': t(
              'Everything you need to start training at home.',
              'كل ما تحتاجه لبدء التمرين في المنزل.',
            ),
            'is_kit': true,
            'item_count': 4,
            'thumbnails': [],
            'more_thumbnails': 1,
            'price': _money(61),
            'price_is_from': false,
            'regular_total': _money(72),
            'saving': _money(11),
            'discount_percent': 16,
            'rating_percent': 90,
            'review_count': 12,
            'category_ids': [3],
          },
        ],
      ),
      _section(
        10,
        'CMS_PROMOS',
        block: {
          'identifier': 'hm_home_promos',
          'title': null,
          'content': kPromosHtml,
        },
      ),
      _section(
        11,
        'BEST_SELLERS',
        title: t('Best Selling Items', 'الأكثر مبيعًا'),
        subtitle: t(
          'Top-rated across all categories this month',
          'الأعلى تقييمًا هذا الشهر',
        ),
        products: [
          product(
            t('Canvas Handbag', 'حقيبة قماشية'),
            1000,
            seller: 'magentoo',
          ),
          product(t('Corner Sofa Bed', 'كنبة سرير زاوية'), 425, was: 500),
        ],
      ),
      // "-" hides the header; the products still show.
      _section(
        12,
        'POPULAR_PRODUCTS',
        title: '-',
        products: [product(t('Joust Duffle Bag', 'حقيبة جوست'), 29, was: 34)],
      ),
      _section(
        13,
        'TOP_BRANDS',
        title: t('Top Brands on Hub Market', 'أفضل العلامات التجارية'),
        brands: [
          for (final (i, b) in ['Samsung', 'SanDisk', 'KIOXIA'].indexed)
            {
              'id': i + 1,
              'option_id': 220 + i,
              'name': b,
              'url_key': b.toLowerCase(),
              'logo_url': null,
              'image_url': null,
              'is_featured': true,
              'link': _link(
                'BRAND',
                'https://hub-market.magento2.click/en/brand/${b.toLowerCase()}.html',
                code: b.toLowerCase(),
              ),
            },
        ],
      ),
      _section(
        14,
        'TOP_VENDORS',
        title: t('Top Vendors This Month', 'أفضل البائعين هذا الشهر'),
        subtitle: t(
          'Highest-rated sellers verified by Hub Market',
          'البائعون الأعلى تقييمًا',
        ),
        stores: [
          store('alrawda', 'Al-Rawda', rating: 4.9, products: 4),
          store('mega', 'mega store', rating: 4.8, products: 10),
        ],
      ),
      _section(
        15,
        'NEW_STORES',
        title: t('New Stores on Hub Market', 'متاجر جديدة على هب ماركت'),
        subtitle: t(
          'Recently joined verified sellers',
          'بائعون موثّقون انضموا حديثًا',
        ),
        stores: [
          store('dev8', 'Test Dev8', products: 3),
          store('magento', 'magento', products: 6),
        ],
      ),
      _section(
        16,
        'TRUST_ROW',
        block: {
          'identifier': 'hm_home_trust',
          'title': null,
          'content': kTrustHtml,
        },
      ),
      _section(
        17,
        'CMS_BLOCK',
        block: {
          'identifier': 'hm_home_sell',
          'title': null,
          'content': t(
            '<h3>Sell on Hub Market</h3><p>Open your store and reach customers nationwide.</p>',
            '<h3>بِع على هب ماركت</h3><p>افتح متجرك وتواصل مع العملاء في كل مكان.</p>',
          ),
        },
      ),
      // Past its end: hidden by the app even when a cached copy still has it.
      _section(
        18,
        'PRODUCT_LIST',
        title: t('Ended Campaign', 'حملة منتهية'),
        endsAt: '2020-01-01T00:00:00Z',
        products: [product('Old Promo', 10)],
      ),
      // A type this build doesn't know: skipped.
      {
        ..._section(19, 'FLASH_SALE', title: 'Flash sale'),
        'type': 'FLASH_SALE',
      },
    ],
  };
}

/// The ids of [hmAuditHomeJson]'s sections, so the audit can find each one.
abstract final class AuditSection {
  static const int strip = 1;
  static const int hero = 2;
  static const int chips = 3;
  static const int deals = 4;
  static const int picked = 5;
  static const int stores = 6;
  static const int railGrocery = 7;
  static const int railFashion = 8;
  static const int railBeauty = 9;
  static const int railFurniture = 10;
  static const int bundles = 11;
  static const int promos = 12;
  static const int best = 13;
  static const int popular = 14;
  static const int brands = 15;
  static const int vendors = 16;
  static const int newStores = 17;
  static const int trust = 18;
  static const int sell = 19;
}

/// The Home as the Figma frame 07 draws it (the live store's sections with the
/// frame's wording): the dataset the UI audit renders so a section can be laid
/// next to its piece of the frame. Images are left out (tests have no network).
Map<String, dynamic> hmAuditHomeJson({
  required DateTime countdown,
  bool arabic = false,
}) {
  String t(String en, String ar) => arabic ? ar : en;
  Map<String, dynamic> banner(
    int id,
    String slot,
    String title, {
    String? kicker,
    String? subtitle,
    String? cta,
    String? tone,
    String? accent,
    String type = 'CATEGORY',
  }) => {
    'id': id,
    'slot': slot,
    'title': title,
    'kicker': kicker,
    'subtitle': subtitle,
    'cta_label': cta,
    'image_url': null,
    'tone': tone,
    'accent': accent,
    'link': _link(
      type,
      'https://hub-market.magento2.click/en/c$id.html',
      uid: 'c$id',
    ),
  };

  Map<String, dynamic> chip(
    int i,
    String key,
    String name,
    String icon,
    int count,
  ) => {
    'id': 100 + i,
    'uid': 'uid-$key',
    'name': name,
    'url_key': key,
    'product_count': count,
    'icon': icon,
    'tint': i,
    'link': _link(
      'CATEGORY',
      'https://hub-market.magento2.click/en/$key.html',
      uid: 'uid-$key',
    ),
  };

  List<Map<String, dynamic>> rail(
    String seller,
    List<(String, double, double?)> items, {
    double? rated,
  }) => [
    for (final (i, item) in items.indexed)
      product(
        item.$1,
        item.$2,
        was: item.$3,
        seller: seller,
        rating: i == 0 ? rated : null,
        reviews: 3,
      ),
  ];

  Map<String, dynamic> bundle(
    String uid,
    String name,
    String seller,
    String description, {
    required int items,
    required int more,
    required double price,
    required double regular,
    required double saving,
    required int percent,
    bool from = false,
  }) => {
    'uid': uid,
    'sku': uid,
    'name': name,
    'url_key': uid,
    'image_url': null,
    'seller': {'code': uid, 'name': seller, 'link': null},
    'description': description,
    'is_kit': true,
    'item_count': items,
    'thumbnails': [
      for (var i = 0; i < 3; i++)
        'https://hub-market.invalid/media/$uid-$i.png',
    ],
    'more_thumbnails': more,
    'price': _money(price),
    'price_is_from': from,
    'regular_total': _money(regular),
    'saving': _money(saving),
    'discount_percent': percent,
    'rating_percent': 90,
    'review_count': 12,
    'category_ids': [3],
  };

  const promosHtml =
      '<div class="hm-promos">'
      '<a class="hm-promo" href="https://hub-market.magento2.click/en/electronics.html/"><span class="hm-promo__icon">⚡</span><span class="hm-promo__kicker">Flash Sale</span><span class="hm-promo__title">Up to 50% Off Electronics &amp; Tech</span><span class="hm-promo__text">Today only</span></a>'
      '<a class="hm-promo" href="https://hub-market.magento2.click/en/super-market.html/"><span class="hm-promo__icon">🌙</span><span class="hm-promo__kicker">Seasonal Offers</span><span class="hm-promo__title">Fresh Grocery Deals</span><span class="hm-promo__text">Same-day delivery &middot; Free over AED 150</span></a>'
      '<a class="hm-promo" href="https://hub-market.magento2.click/en/all.html/"><span class="hm-promo__icon">💳</span><span class="hm-promo__kicker">Buy Now Pay Later</span><span class="hm-promo__title">Split in 4 with Tabby</span><span class="hm-promo__text">0% interest &middot; Instant approval</span></a>'
      '</div>';
  const promosHtmlAr =
      '<div class="hm-promos">'
      '<a class="hm-promo" href="https://hub-market.magento2.click/ar/electronics.html/"><span class="hm-promo__icon">⚡</span><span class="hm-promo__kicker">عروض سريعة</span><span class="hm-promo__title">خصم حتى 50٪ الإلكترونيات والتقنية</span><span class="hm-promo__text">اليوم فقط</span></a>'
      '<a class="hm-promo" href="https://hub-market.magento2.click/ar/super-market.html/"><span class="hm-promo__icon">🌙</span><span class="hm-promo__kicker">عروض الموسم</span><span class="hm-promo__title">عروض بقالة طازجة</span><span class="hm-promo__text">توصيل في نفس اليوم · مجاناً فوق 150 درهم</span></a>'
      '<a class="hm-promo" href="https://hub-market.magento2.click/ar/all.html/"><span class="hm-promo__icon">💳</span><span class="hm-promo__kicker">اشترِ الآن وادفع لاحقاً</span><span class="hm-promo__title">قسّمها على 4 دفعات مع تابي</span><span class="hm-promo__text">بدون فوائد · موافقة فورية</span></a>'
      '</div>';
  const trustHtml =
      '<div class="hm-trust">'
      '<div class="hm-trust__item"><span class="hm-trust__title">Trusted Sellers</span><span class="hm-trust__text">Verified &amp; approved</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">Secure Payments</span><span class="hm-trust__text">Cards, cash on delivery, Tabby &amp; Tamara</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">Fast Delivery</span><span class="hm-trust__text">Across all seven emirates</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">Easy Returns</span><span class="hm-trust__text">14-day return policy</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">WhatsApp Support</span><span class="hm-trust__text">24/7 customer care</span></div>'
      '</div>';
  const trustHtmlAr =
      '<div class="hm-trust">'
      '<div class="hm-trust__item"><span class="hm-trust__title">بائعون موثوقون</span><span class="hm-trust__text">تمت المراجعة والاعتماد</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">مدفوعات آمنة</span><span class="hm-trust__text">البطاقات والدفع عند الاستلام وتابي وتمارا</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">توصيل سريع</span><span class="hm-trust__text">لجميع الإمارات السبع</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">إرجاع سهل</span><span class="hm-trust__text">إرجاع خلال 14 يومًا</span></div>'
      '<div class="hm-trust__item"><span class="hm-trust__title">دعم عبر واتساب</span><span class="hm-trust__text">خدمة العملاء على مدار الساعة</span></div>'
      '</div>';

  return {
    'store_code': arabic ? 'ar' : 'en',
    'generated_at': '2026-09-30T06:00:00Z',
    'sections': [
      _section(
        AuditSection.strip,
        'DELIVERY_STRIP',
        block: {
          'identifier': 'hm_delivery_promise',
          'title': null,
          'content': t(
            '<p>Free delivery on qualifying orders</p>',
            '<p>توصيل مجاني على الطلبات المؤهلة</p>',
          ),
        },
      ),
      _section(
        AuditSection.hero,
        'HERO_BANNERS',
        banners: [
          banner(
            1,
            'SLIDE',
            t(
              'Fresh Groceries From Local Vendors',
              'بقالة طازجة من بائعين محليين',
            ),
            kicker: t('SAME-DAY DELIVERY', 'توصيل في نفس اليوم'),
            subtitle: t(
              'Organic produce, dairy and pantry essentials, delivered in hours.',
              'خضروات وفواكه طازجة ومنتجات الألبان وأساسيات المطبخ، تصلك خلال ساعات.',
            ),
            cta: t('Shop Grocery', 'تسوّق البقالة'),
            tone: '#123620',
            accent: '#0F7B3F',
          ),
          banner(
            2,
            'SLIDE',
            t(
              'Fashion From Approved Egyptian Sellers',
              'أزياء من بائعين مصريين معتمدين',
            ),
            kicker: t('NEW SEASON', 'موسم جديد'),
            subtitle: t(
              'Everyday wear and international labels.',
              'ملابس يومية وماركات عالمية.',
            ),
            cta: t('Shop Fashion', 'تسوّق الأزياء'),
            tone: '#0F2144',
            accent: '#F26522',
          ),
          banner(
            3,
            'SLIDE',
            t('Furniture and Decor for Every Home', 'أثاث وديكور لكل منزل'),
            kicker: t('PREMIUM HOME', 'منزل مميز'),
            subtitle: t(
              'Sofas, beds and lighting from local makers.',
              'كنب وأسرّة وإضاءة من صنّاع محليين.',
            ),
            cta: t('Shop Furniture', 'تسوّق الأثاث'),
            tone: '#2A1200',
            accent: '#F26522',
          ),
          banner(
            4,
            'TILE',
            t('Electronics Deals', 'عروض الإلكترونيات'),
            subtitle: t(
              'Phones, tablets & accessories',
              'موبايلات وتابلت وإكسسوارات',
            ),
            tone: '#0F2144',
          ),
          banner(
            5,
            'TILE',
            t('Beauty & Cosmetics', 'الجمال والعطور'),
            subtitle: t('New arrivals daily', 'وصل حديثًا كل يوم'),
            tone: '#3D1A36',
          ),
          banner(
            6,
            'TILE',
            t('Bundle Deals', 'عروض الباقات'),
            kicker: t('🎁 This week only', '🎁 هذا الأسبوع فقط'),
            subtitle: t('Buy more, pay less', 'اشترِ أكثر وادفع أقل'),
            accent: '#F26522',
            type: 'BUNDLES',
          ),
          banner(
            7,
            'TILE',
            t('Kids & Toys', 'الأطفال والألعاب'),
            subtitle: t('Safe & educational', 'آمنة وتعليمية'),
            tone: '#1E2E14',
          ),
        ],
      ),
      _section(
        AuditSection.chips,
        'CATEGORY_CHIPS',
        title: t('Shop by category', 'تسوّق حسب القسم'),
        categories: [
          chip(0, 'super-market', t('Grocery', 'سوبر ماركت'), '🛒', 7),
          chip(1, 'pharmacy', t('Pharmacy', 'صيدلية'), '💊', 8),
          chip(2, 'furniture', t('Furniture', 'أثاث'), '🛋️', 7),
          chip(3, 'clothes', t('Fashion', 'أزياء'), '👗', 19),
          chip(4, 'fmcg', 'FMCG', '📦', 5),
          chip(5, 'kids', t('Kids & Toys', 'الأطفال والألعاب'), '🧸', 4),
          chip(6, 'cosmetics', t('Cosmetics', 'مستحضرات التجميل'), '💄', 7),
          chip(
            7,
            'electronics',
            t('Electronics & Tech', 'الإلكترونيات والتقنية'),
            '📱',
            5,
          ),
        ],
      ),
      _section(
        AuditSection.deals,
        'TODAYS_DEALS',
        title: t("Today's Deals", 'عروض اليوم'),
        countdown: countdown.toUtc().toIso8601String(),
        more: _link('DEALS', 'https://hub-market.magento2.click/en/deals'),
        products: [
          product(
            t('Egyptian Rice 1 kg', 'أرز مصري ريحانة 1كجم'),
            25,
            was: 35,
            seller: 'walmart',
            rating: 4.7,
            reviews: 3,
          ),
          product(
            t('Modern Executive Desk 160 cm', 'مكتب مدير مودرن 160 سم'),
            263,
            was: 350,
            seller: 'MIA CO',
          ),
          product(
            t('Fine Plastering Sand for Construction', 'رمل ناعم للبناء والتلييس'),
            2250,
            was: 3000,
            seller: t('Future Building Materials', 'المستقبل لمواد البناء'),
          ),
        ],
      ),
      _section(
        AuditSection.picked,
        'PICKED_FOR_YOU',
        title: t('Picked For You', 'مختارة لك'),
        subtitle: t(
          'Personalised recommendations based on your search history & behaviour',
          'توصيات مخصّصة بناءً على سجل بحثك وسلوكك',
        ),
        products: [
          product(
            t('Dual Handle Cardio Ball', 'كرة كارديو بمقبضين'),
            12,
            seller: 'Test 1',
            rating: 5,
            reviews: 2,
          ),
          product(
            t('Short Square-Neck T-Shirt', 'تيشيرت قصير بياقة مربعة'),
            43,
            seller: 'loly store',
          ),
          product(
            t('Floral Print Corset-Waist Tie Dress', 'فستان مزهر بخصر مشدود'),
            50,
            seller: 'loly store',
          ),
          product(
            t('20-Piece Eye Makeup Brush Set', 'طقم فرش مكياج للعين 20 قطعة'),
            550,
            seller: 'Test2',
          ),
        ],
      ),
      _section(
        AuditSection.stores,
        'FEATURED_STORES',
        title: t('Featured Stores', 'متاجر مختارة'),
        subtitle: t(
          'Verified sellers on Hub Market',
          'بائعون موثّقون على Hub Market',
        ),
        stores: [
          store('ENARA', 'ENARA', rating: 4.4, products: 8, dispatch: '24h'),
          store('loly', 'loly', rating: 4.8, products: 7, dispatch: '~2 days'),
          store('MIA', 'MIA', rating: 4.3, products: 6),
          store('ronza', 'ronza', rating: 4.4, products: 10),
        ],
      ),
      _section(
        AuditSection.railGrocery,
        'CATEGORY_RAIL',
        title: t('Grocery Essentials', 'أساسيات البقالة'),
        subtitle: t('Fresh & delivered today', 'طازج ويصلك اليوم'),
        more: _link(
          'CATEGORY',
          'https://hub-market.magento2.click/en/super-market.html',
          uid: 'Mw==',
        ),
        products: rail('walmart', [
          (t('Egyptian Rice 1 kg', 'أرز مصري ريحانة 1كجم'), 25, 35),
          (t('Dolphin Tuna Chunks in Water', 'قطع تونة دولفين'), 43, 48),
          (t('Coca-Cola Original Taste Can', 'كوكاكولا علبة'), 12, 15),
          (t('Fresh Whole Milk 1 L', 'حليب كامل الدسم 1 لتر'), 9, null),
        ], rated: 4.7),
      ),
      _section(
        AuditSection.railFashion,
        'CATEGORY_RAIL',
        title: t('Fashion Trends', 'أحدث صيحات الموضة'),
        subtitle: t('New arrivals this week', 'وصل حديثًا هذا الأسبوع'),
        more: _link(
          'CATEGORY',
          'https://hub-market.magento2.click/en/clothes.html',
          uid: 'Ng==',
        ),
        products: rail('loly store', [
          (t('Short Square-Neck T-Shirt', 'تيشيرت قصير بياقة مربعة'), 43, null),
          (
            t('Floral Print Corset-Waist Tie Dress', 'فستان مزهر بخصر مشدود'),
            50,
            null,
          ),
          (t('Short Cargo Jacket', 'جاكيت كارجو قصير'), 13, 15),
          (t('Linen Wide-Leg Trousers', 'بنطلون كتان واسع'), 70, null),
        ]),
      ),
      _section(
        AuditSection.railBeauty,
        'CATEGORY_RAIL',
        title: t('Beauty & Cosmetics', 'الجمال ومستحضرات التجميل'),
        subtitle: t('Curated beauty picks', 'مختارات الجمال'),
        more: _link(
          'CATEGORY',
          'https://hub-market.magento2.click/en/cosmetics.html',
          uid: 'Nw==',
        ),
        products: rail('Test2', [
          (t('Mini Safety Shaver', 'ماكينة حلاقة صغيرة'), 85, null),
          (
            t('20-Piece Eye Makeup Brush Set', 'طقم فرش مكياج للعين 20 قطعة'),
            550,
            null,
          ),
          (t('Tinted Lip Gloss', 'ملمع شفاه ملون'), 65, null),
          (t('Hydrating Face Cream', 'كريم مرطب للوجه'), 120, null),
        ]),
      ),
      _section(
        AuditSection.railFurniture,
        'CATEGORY_RAIL',
        title: t('Furniture Picks', 'مختارات الأثاث'),
        subtitle: t('For your home', 'لمنزلك'),
        more: _link(
          'CATEGORY',
          'https://hub-market.magento2.click/en/furniture.html',
          uid: 'NQ==',
        ),
        products: rail('MIA CO', [
          (t('Corner Sofa Bed', 'كنبة سرير زاوية'), 425, 500),
          (t('3-Piece Living Room Set', 'طقم غرفة معيشة 3 قطع'), 255, 300),
          (t('Dining Table Set 6 Seats', 'طقم سفرة 6 كراسي'), 340, 400),
          (t('Oak Bookshelf', 'مكتبة بلوط'), 190, 220),
        ]),
      ),
      _section(
        AuditSection.bundles,
        'BUNDLE_DEALS',
        title: t('Bundle Deals', 'عروض الباقات'),
        subtitle: t(
          'Buy together, save more — curated multi-item bundles',
          'اشترِ معًا ووفّر أكثر — باقات مختارة متعددة المنتجات',
        ),
        bundles: [
          bundle(
            'home-fitness',
            t('Home Fitness Starter Pack', 'باقة اللياقة المنزلية'),
            'Test 1',
            t(
              'Everything you need to start training at home — four essentials from one seller, bundled at a saving over buying them one by one.',
              'كل ما تحتاجه لبدء التمرين في المنزل — أربع أساسيات من بائع واحد بسعر أوفر من شرائها منفصلة.',
            ),
            items: 4,
            more: 1,
            price: 61,
            regular: 72,
            saving: 11,
            percent: 16,
          ),
          bundle(
            'house-tools',
            'house tools',
            'Test3',
            t(
              'Includes Grado Galvanised Steel Tying Wire, Marseille Wall Sconce 1 Bulb, Villa Table Lamp 1 Bulb and 3 more.',
              'يشمل سلك تربيط جرادو حديد مجلفن، أبليك مارسيليا 1 لمبة، أباجورة فيلا 1 لمبة و3 أخرى.',
            ),
            items: 6,
            more: 3,
            price: 170,
            regular: 200,
            saving: 30,
            percent: 15,
            from: true,
          ),
        ],
      ),
      _section(
        AuditSection.promos,
        'CMS_PROMOS',
        block: {
          'identifier': 'hm_home_promos',
          'title': null,
          'content': t(promosHtml, promosHtmlAr),
        },
      ),
      _section(
        AuditSection.best,
        'BEST_SELLERS',
        title: t('Best Selling Items', 'الأكثر مبيعًا'),
        subtitle: t(
          'Top-rated across all categories this month',
          'الأعلى تقييمًا في كل الأقسام هذا الشهر',
        ),
        products: [
          product(
            t('Canvas Handbag', 'حقيبة قماشية'),
            1000,
            seller: 'magentoo',
            rating: 4.5,
            reviews: 12,
          ),
          product(
            t('Corner Sofa Bed', 'كنبة سرير زاوية'),
            425,
            was: 500,
            seller: 'MIA CO',
          ),
          product(
            t('Floral Print Corset-Waist Tie Dress', 'فستان مزهر بخصر مشدود'),
            50,
            seller: 'loly store',
          ),
          product(
            t('Wide Brim Straw Hat', 'قبعة قش واسعة'),
            35,
            seller: 'magentoo',
            rating: 4.2,
            reviews: 5,
          ),
        ],
      ),
      _section(
        AuditSection.popular,
        'POPULAR_PRODUCTS',
        title: t('Popular Products', 'منتجات رائجة'),
        products: [
          product(
            t('Joust Duffle Bag', 'حقيبة جوست'),
            29,
            was: 34,
            seller: 'Test 1',
            rating: 2.5,
            reviews: 2,
          ),
          product(
            t('Strive Shoulder Pack', 'حقيبة كتف سترايف'),
            32,
            seller: 'Test 1',
          ),
          product(
            t('Crown Summit Backpack', 'حقيبة ظهر كراون'),
            38,
            seller: 'Test 1',
          ),
          product(
            t('Driven Backpack', 'حقيبة ظهر درايفن'),
            36,
            seller: 'Test 1',
          ),
        ],
      ),
      _section(
        AuditSection.brands,
        'TOP_BRANDS',
        title: t(
          'Top Brands on Hub Market',
          'أشهر العلامات التجارية على Hub Market',
        ),
        brands: [
          for (final (i, b) in [
            'Western Digital',
            'SanDisk',
            'KIOXIA',
            'Netgear',
            'Samsung',
            'Lenovo',
            'HP',
            'Dell',
          ].indexed)
            {
              'id': i + 1,
              'option_id': 220 + i,
              'name': b,
              'url_key': b.toLowerCase().replaceAll(' ', '-'),
              'logo_url': null,
              'image_url': null,
              'is_featured': true,
              'link': _link(
                'BRAND',
                'https://hub-market.magento2.click/en/brand/${b.toLowerCase()}.html',
                code: b.toLowerCase(),
              ),
            },
        ],
      ),
      _section(
        AuditSection.vendors,
        'TOP_VENDORS',
        title: t('Top Vendors This Month', 'أفضل البائعين هذا الشهر'),
        subtitle: t(
          'Highest-rated sellers verified by Hub Market',
          'أعلى البائعين تقييمًا والموثّقون من Hub Market',
        ),
        stores: [
          store('alrawda', 'Al-Rawda', rating: 4.9, products: 4),
          store('mega', 'mega store', rating: 4.8, products: 10),
          store('lolystore', 'loly store', rating: 4.8, products: 14),
          store('moo', 'moo store', rating: 4.8, products: 2),
        ],
      ),
      _section(
        AuditSection.newStores,
        'NEW_STORES',
        title: t('New Stores on Hub Market', 'متاجر جديدة على Hub Market'),
        subtitle: t(
          'Recently joined verified sellers',
          'بائعون موثّقون انضموا حديثًا',
        ),
        stores: [
          store('dev8', 'Test Dev8', products: 3),
          store('magento', 'magento', products: 6),
          store('v1s2', 'V1S2', products: 1),
        ],
      ),
      _section(
        AuditSection.trust,
        'TRUST_ROW',
        block: {
          'identifier': 'hm_home_trust',
          'title': null,
          'content': t(trustHtml, trustHtmlAr),
        },
      ),
      _section(
        AuditSection.sell,
        'CMS_BLOCK',
        block: {
          'identifier': 'hm_home_sell',
          'title': null,
          'content': t(
            '<h3>Sell on Hub Market</h3><p>Open your store and reach customers nationwide — list products, manage orders and get paid from the vendor app.</p><p><a href="https://hub-market.magento2.click/en/vendors/seller/register">Start selling</a></p>',
            '<h3>بِع على Hub Market</h3><p>افتح متجرك ووصّل منتجاتك للعملاء في كل مكان — أضف منتجاتك وتابع طلباتك واستلم أرباحك من تطبيق البائع.</p><p><a href="https://hub-market.magento2.click/ar/vendors/seller/register">ابدأ البيع</a></p>',
          ),
        },
      ),
    ],
  };
}

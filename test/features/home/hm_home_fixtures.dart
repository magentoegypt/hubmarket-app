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

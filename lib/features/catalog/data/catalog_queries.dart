/// Hand-written Magento 2.4.8 catalogue GraphQL documents, parsed by
/// `product_mapper.dart` / `CatalogRepository`.
///
/// The browse ops also live as standalone codegen sources in
/// `lib/features/catalog/data/graphql/` (`category_tree`, `category_by_uid`,
/// `products`, `search_products`, `product_detail` — keep them identical to the strings
/// below). They are
/// checked against Hub Market's introspected `schema.graphql`
/// (`tool/validate_ops.py`, `dart run build_runner build`); moving the
/// repository onto the generated types is still to do. See
/// `docs/zoonze-reference/decisions/codegen.md`.
abstract final class CatalogQueries {
  /// Resolves a store-relative URL (a friendly `.html` category/product path) to
  /// its entity, so a hero CTA opens the right in-app screen instead of guessing.
  static const String urlResolve = r'''
query ResolveUrl($url: String!) {
  urlResolver(url: $url) {
    type
    entity_uid
    relative_url
  }
}
''';

  /// Stand-in thumbnails for categories that carry no `image` of their own.
  ///
  /// On Hub Market most categories have none (2026-09-29: 15 of 27 top-level,
  /// 9 of 46 second-level and none of the third-level ones carry an image), so
  /// the first product inside the category stands in: one aliased query so N
  /// categories cost one round trip, not N.
  ///
  /// A category with no products resolves to an empty `items` list — the caller
  /// renders the neutral placeholder.
  static String categoryThumbnails(int count) {
    // A bare `$` so the GraphQL variable sigil survives Dart interpolation.
    const v = r'$';
    final args = List.generate(count, (i) => '${v}u$i: String!').join(', ');
    final buffer = StringBuffer('query CategoryThumbnails($args) {');
    for (var i = 0; i < count; i++) {
      buffer.writeln();
      buffer.write(
        '  c$i: products(filter: {category_uid: {eq: ${v}u$i}}, pageSize: 1) '
        '{ items { image { url } } }',
      );
    }
    buffer.writeln();
    buffer.write('}');
    return buffer.toString();
  }

  /// Top-level category tree (menu / home "shop by category").
  static const String categoryTree = r'''
query CategoryTree {
  categoryList {
    uid
    name
    url_key
    children {
      uid
      name
      url_key
      image
      include_in_menu
      product_count
      children {
        uid
        name
        url_key
        image
        include_in_menu
        product_count
        children {
          uid
          name
          url_key
          image
          include_in_menu
          product_count
        }
      }
    }
  }
}
''';

  /// One category by its uid, with the two levels below it — wherever it sits,
  /// also a category the admin keeps out of the menu (`include_in_menu` 0: on
  /// Hub Market Shoes, Bags, Mobile & Tablet ...), which [categoryTree] leaves
  /// out. Backs the title and the sub-category rail of a listing opened by uid.
  static const String categoryByUid = r'''
query CategoryByUid($uid: String!) {
  categories(filters: {category_uid: {eq: $uid}}) {
    items {
      uid
      name
      url_key
      image
      include_in_menu
      product_count
      children {
        uid
        name
        url_key
        image
        include_in_menu
        product_count
        children {
          uid
          name
          url_key
          image
          include_in_menu
          product_count
        }
      }
    }
  }
}
''';

  /// Product listing — drives home featured, PLP, and search. `filter`/`search`
  /// are mutually optional but Magento requires at least one of them.
  static const String products = r'''
query Products(
  $search: String
  $filter: ProductAttributeFilterInput
  $sort: ProductAttributeSortInput
  $pageSize: Int!
  $currentPage: Int!
) {
  products(
    search: $search
    filter: $filter
    sort: $sort
    pageSize: $pageSize
    currentPage: $currentPage
  ) {
    total_count
    page_info {
      current_page
      total_pages
      page_size
    }
    items {
      sku
      name
      url_key
      stock_status
      new_from_date
      new_to_date
      rating_summary
      review_count
      image {
        url
        label
      }
      price_range {
        minimum_price {
          regular_price {
            value
            currency
          }
          final_price {
            value
            currency
          }
        }
      }
    }
    aggregations {
      attribute_code
      label
      options {
        label
        value
        count
      }
    }
  }
}
''';

  /// Product search — [products] plus each hit's `categories`, which the
  /// type-ahead names ("in Home Furniture") and ranks its category links by.
  /// Kept separate so the PLP and Home rails don't pay for the category lists
  /// (a bag on Hub Market sits in eleven).
  ///
  /// Search goes to Algolia first (`CatalogSearch`); this is the fallback.
  /// Hub Market answers `products(search:)` from OpenSearch (the backend's
  /// AlgoliaVendor EngineResolverPlugin), so its ranking can differ from the
  /// website's.
  static const String searchProducts = r'''
query SearchProducts(
  $search: String!
  $filter: ProductAttributeFilterInput
  $sort: ProductAttributeSortInput
  $pageSize: Int!
  $currentPage: Int!
) {
  products(
    search: $search
    filter: $filter
    sort: $sort
    pageSize: $pageSize
    currentPage: $currentPage
  ) {
    total_count
    page_info {
      current_page
      total_pages
      page_size
    }
    items {
      sku
      name
      url_key
      stock_status
      new_from_date
      new_to_date
      rating_summary
      review_count
      image {
        url
        label
      }
      price_range {
        minimum_price {
          regular_price {
            value
            currency
          }
          final_price {
            value
            currency
          }
        }
      }
      categories {
        uid
        name
        level
        include_in_menu
      }
    }
    aggregations {
      attribute_code
      label
      options {
        label
        value
        count
      }
    }
  }
}
''';

  /// Single product by url_key for the PDP, including configurable options +
  /// variants, gallery, description, reviews, and the "You may also like"
  /// candidates (core `related_products` + `upsell_products`; merged,
  /// de-duplicated and capped app-side by `alsoLikeFromJson`).
  static const String productDetail = r'''
query ProductDetail($urlKey: String!) {
  products(filter: { url_key: { eq: $urlKey } }, pageSize: 1) {
    items {
      __typename
      sku
      name
      url_key
      stock_status
      new_from_date
      new_to_date
      rating_summary
      review_count
      only_x_left_in_stock
      categories {
        uid
        name
        level
        include_in_menu
      }
      related_products {
        ...LinkedProductFields
      }
      upsell_products {
        ...LinkedProductFields
      }
      reviews(pageSize: 20) {
        items {
          nickname
          summary
          text
          average_rating
          created_at
        }
      }
      description {
        html
      }
      short_description {
        html
      }
      custom_attributesV2(filters: { is_visible_on_front: true }) {
        items {
          code
          ... on AttributeValue {
            value
          }
          ... on AttributeSelectedOptions {
            selected_options {
              label
              value
            }
          }
        }
      }
      image {
        url
      }
      media_gallery {
        url
        label
      }
      price_range {
        minimum_price {
          regular_price {
            value
            currency
          }
          final_price {
            value
            currency
          }
        }
      }
      ... on ConfigurableProduct {
        configurable_options {
          attribute_code
          label
          values {
            uid
            value_index
            label
            swatch_data {
              value
            }
          }
        }
        variants {
          attributes {
            code
            value_index
          }
          product {
            sku
            stock_status
            only_x_left_in_stock
            image {
              url
            }
            price_range {
              minimum_price {
                regular_price {
                  value
                  currency
                }
                final_price {
                  value
                  currency
                }
              }
            }
          }
        }
      }
    }
  }
}

# "You may also like" card: the same small field set as a listing card.
fragment LinkedProductFields on ProductInterface {
  sku
  name
  url_key
  stock_status
  new_from_date
  new_to_date
  rating_summary
  review_count
  image {
    url
  }
  price_range {
    minimum_price {
      regular_price {
        value
        currency
      }
      final_price {
        value
        currency
      }
    }
  }
}
''';

  static const String reviewRatingsMetadata = r'''
query ReviewRatingsMetadata {
  productReviewRatingsMetadata {
    items {
      id
      name
      values { value_id value }
    }
  }
}
''';

  static const String createReview = r'''
mutation CreateReview($input: CreateProductReviewInput!) {
  createProductReview(input: $input) {
    review { nickname summary text }
  }
}
''';
}

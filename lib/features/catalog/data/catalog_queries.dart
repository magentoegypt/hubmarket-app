/// Hand-written Magento 2.4.8 catalogue GraphQL documents.
///
/// These extend the Phase 0 bootstrap exception: until `tool/introspect.sh`
/// produces `schema.graphql` (origin is blocked in CI), catalogue ops are
/// hand-written + mapped. Phase 1.x migrates them to graphql_codegen.
///
/// The codegen sources for the browse ops now live as standalone operations in
/// `lib/features/catalog/data/graphql/` (`category_tree`, `products`,
/// `product_detail` — mirrored from the strings below). Once `schema.graphql`
/// lands, `dart run build_runner build` generates their typed Dart and this
/// file is replaced by the generated documents. See `docs/decisions/codegen.md`.
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
  /// Only top-level categories have an image assigned on this store — every
  /// second- and third-level one comes back `null` (verified live, 2026-08-27).
  /// The storefront papers over that by showing the first product inside the
  /// category instead (`beauty-subcats__media`), and this reproduces it: one
  /// aliased query so N categories cost one round trip, not N.
  ///
  /// A category with no products resolves to an empty `items` list — the caller
  /// renders the neutral placeholder, exactly as the website does.
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
      is_new_arrival
      is_bestseller
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

  /// Single product by url_key for the PDP, including configurable options +
  /// variants, gallery, description, and review metadata.
  static const String productDetail = r'''
query ProductDetail($urlKey: String!) {
  products(filter: { url_key: { eq: $urlKey } }, pageSize: 1) {
    items {
      __typename
      sku
      name
      url_key
      stock_status
      is_new_arrival
      is_bestseller
      rating_summary
      review_count
      rating_histogram {
        stars
        count
        percent
      }
      also_like_products(pageSize: 8) {
        sku
        name
        url_key
        stock_status
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

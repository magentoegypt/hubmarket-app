/// Hand-written Magento 2.4.8 wishlist operations (customer-scoped).
abstract final class WishlistQueries {
  static const String _wishlistFields = r'''
fragment WishlistFields on Wishlist {
  id
  items_v2 {
    items {
      id
      product {
        sku
        name
        url_key
        stock_status
        is_new_arrival
        is_bestseller
        image { url }
        price_range {
          minimum_price {
            regular_price { value currency }
            final_price { value currency }
          }
        }
      }
    }
  }
}
''';

  static String _doc(String operation) => '$operation\n$_wishlistFields';

  static final String getWishlist = _doc(r'''
query Wishlist {
  customer {
    wishlists { ...WishlistFields }
  }
}''');

  static final String addToWishlist = _doc(r'''
mutation AddToWishlist($wishlistId: ID!, $items: [WishlistItemInput!]!) {
  addProductsToWishlist(wishlistId: $wishlistId, wishlistItems: $items) {
    wishlist { ...WishlistFields }
    user_errors { code message }
  }
}''');

  static final String removeFromWishlist = _doc(r'''
mutation RemoveFromWishlist($wishlistId: ID!, $itemIds: [ID!]!) {
  removeProductsFromWishlist(wishlistId: $wishlistId, wishlistItemsIds: $itemIds) {
    wishlist { ...WishlistFields }
    user_errors { code message }
  }
}''');
}

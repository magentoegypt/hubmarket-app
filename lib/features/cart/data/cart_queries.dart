import '../../../core/hubapp/hubapp_models.dart';
import '../../marketplace/data/seller_selections.dart';

/// Hand-written Magento 2.4.8 cart operations (codegen migration is Phase 1.x).
/// All mutations return the full `CartFields` so the controller can refresh
/// state from a single response.
abstract final class CartQueries {
  static const String _cartFields = r'''
fragment CartFields on Cart {
  id
  total_quantity
  items {
    uid
    quantity
    product {
      sku
      name
      image { url }
      price_range {
        minimum_price {
          regular_price { value currency }
        }
      }
    }
    prices {
      price { value currency }
      row_total { value currency }
    }
    ... on ConfigurableCartItem {
      configurable_options { option_label value_label }
    }
  }
  applied_coupons { code }
  shipping_addresses {
    selected_shipping_method { amount { value currency } }
  }
  prices {
    grand_total { value currency }
    subtotal_including_tax { value currency }
    discounts { amount { value currency } label }
  }
}
''';

  static String _doc(String operation) => '$operation\n$_cartFields';

  /// Each line's seller (HubAppVendors `hm_seller`), which the cart and the
  /// checkout review group lines by. GraphQL merges these `items` with the
  /// ones [_cartFields] selects.
  static const String hmCartSellers = r'''
fragment HmCartSellers on Cart {
  items {
    uid
    hm_seller {
      ...HmSellerFields
    }
  }
}
''';

  /// The HubApp twin of a cart [document]: `...HmCartSellers` beside each
  /// `...CartFields`. Sent only while HubApp serves `hm_seller`; today's
  /// server gets [document] itself — see `SellerSelections`.
  static String withSellers(String document) => SellerSelections.beside(
    document,
    anchor: 'CartFields',
    spread: 'HmCartSellers',
    fragments: '$hmCartSellers\n${HmFragments.seller}\n${HmFragments.link}',
  );

  static const String createEmptyCart =
      'mutation CreateEmptyCart { createEmptyCart }';

  static const String customerCart =
      'query CustomerCart { customerCart { id } }';

  static final String getCart = _doc(r'''
query GetCart($cartId: String!) {
  cart(cart_id: $cartId) { ...CartFields }
}''');

  static final String addProducts = _doc(r'''
mutation AddProducts($cartId: String!, $items: [CartItemInput!]!) {
  addProductsToCart(cartId: $cartId, cartItems: $items) {
    cart { ...CartFields }
    user_errors { code message }
  }
}''');

  /// `hmAddBundleToCart` (HubAppBundle) with its selections still empty:
  /// `BundleCartMutation` writes one inline selection object per chosen
  /// selection, each with its own scalar variables. The input is never a
  /// variable — see `BundleCartMutation`.
  static final String addBundle = _doc(r'''
mutation HmAddBundleToCart($cartId: String!, $sku: String!, $quantity: Float) {
  hmAddBundleToCart(
    input: { cart_id: $cartId, sku: $sku, quantity: $quantity, selections: [] }
  ) {
    cart { ...CartFields }
    user_errors { code message }
  }
}''');

  static final String updateItems = _doc(r'''
mutation UpdateItems($cartId: String!, $items: [CartItemUpdateInput!]!) {
  updateCartItems(input: { cart_id: $cartId, cart_items: $items }) {
    cart { ...CartFields }
  }
}''');

  static final String removeItem = _doc(r'''
mutation RemoveItem($cartId: String!, $uid: ID!) {
  removeItemFromCart(input: { cart_id: $cartId, cart_item_uid: $uid }) {
    cart { ...CartFields }
  }
}''');

  static final String applyCoupon = _doc(r'''
mutation ApplyCoupon($cartId: String!, $code: String!) {
  applyCouponToCart(input: { cart_id: $cartId, coupon_code: $code }) {
    cart { ...CartFields }
  }
}''');

  static final String removeCoupon = _doc(r'''
mutation RemoveCoupon($cartId: String!) {
  removeCouponFromCart(input: { cart_id: $cartId }) {
    cart { ...CartFields }
  }
}''');

  static final String mergeCarts = _doc(r'''
mutation MergeCarts($source: String!, $destination: String!) {
  mergeCarts(source_cart_id: $source, destination_cart_id: $destination) {
    ...CartFields
  }
}''');
}

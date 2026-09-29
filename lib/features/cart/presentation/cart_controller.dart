import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_cache.dart';
import '../../../core/store/store_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/cart_repository.dart';
import '../domain/cart.dart';

class CartState {
  const CartState({
    this.cart = Cart.empty,
    this.isLoading = false,
    this.isMutating = false,
    this.error,
  });

  final Cart cart;
  final bool isLoading;
  final bool isMutating;
  final Object? error;

  int get itemCount => cart.itemCount;

  static const Object _keep = Object();

  CartState copyWith({
    Cart? cart,
    bool? isLoading,
    bool? isMutating,
    Object? error = _keep,
  }) => CartState(
    cart: cart ?? this.cart,
    isLoading: isLoading ?? this.isLoading,
    isMutating: isMutating ?? this.isMutating,
    error: identical(error, _keep) ? this.error : error,
  );
}

/// Owns the cart: lazily creates a guest cart (id persisted in Hive), add /
/// update / remove / coupon, and merges the guest cart into the customer cart
/// on login (and clears it on logout).
class CartController extends Notifier<CartState> {
  static const String _guestKey = 'guest_cart_id';
  String? _cartId;

  @override
  CartState build() {
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      final wasAuthed = prev?.isAuthenticated ?? false;
      if (next.isAuthenticated && !wasAuthed) {
        _onLogin();
      } else if (next.status == AuthStatus.guest) {
        if (wasAuthed) {
          _onLogout();
        } else {
          _restoreGuestCart();
        }
      }
    });
    // A language/store switch flips the `Store` header and resets the GraphQL
    // cache; refetch the cart so item names/prices reflect the new store view
    // (CLAUDE.md §3.2 — "re-evaluate cart after a store switch").
    ref.listen<String>(
      storeControllerProvider.select((s) => s.activeStoreCode),
      (prev, next) {
        if (prev != null && prev != next && _cartId != null) {
          Future.microtask(_reload);
        }
      },
    );
    // Handle an already-settled auth state (no transition for the listener to
    // observe) so the guest and customer restore paths never race.
    final auth = ref.read(authControllerProvider);
    if (auth.isAuthenticated) {
      Future.microtask(_onLogin);
    } else if (auth.status == AuthStatus.guest) {
      Future.microtask(_restoreGuestCart);
    }
    return const CartState();
  }

  LocalCache get _cache => ref.read(localCacheProvider);
  CartRepository get _repo => ref.read(cartRepositoryProvider);

  Future<void> _restoreGuestCart() async {
    if (_cartId != null) return;
    final id = _cache.readString(_guestKey);
    if (id == null) return;
    _cartId = id;
    await _reload();
  }

  Future<String> _ensureCartId() async {
    final existing = _cartId;
    if (existing != null) return existing;
    // Logged-in customers add to their own (Magento-managed) cart; guests get a
    // lazily-created guest cart whose id is persisted in Hive.
    if (ref.read(authControllerProvider).isAuthenticated) {
      final customerId = await _repo.customerCartId();
      if (customerId != null && customerId.isNotEmpty) {
        _cartId = customerId;
        return customerId;
      }
    }
    final id = await _repo.createGuestCart();
    _cartId = id;
    await _cache.writeString(_guestKey, id);
    return id;
  }

  /// Drops the active cart id (and the persisted guest id) so the next
  /// [_ensureCartId] creates a fresh cart. Used when a cart is consumed
  /// server-side (e.g. after placing an order) or found to be stale.
  Future<void> _resetCart() async {
    _cartId = null;
    if (!ref.read(authControllerProvider).isAuthenticated) {
      await _cache.deleteKey(_guestKey);
    }
  }

  Future<void> _reload() async {
    final id = _cartId;
    if (id == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      state = state.copyWith(cart: await _repo.getCart(id), isLoading: false);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> addToCart({
    required String sku,
    int quantity = 1,
    List<String> selectedOptionUids = const [],
  }) async {
    state = state.copyWith(isMutating: true, error: null);
    final item = <String, dynamic>{
      'sku': sku,
      'quantity': quantity,
      if (selectedOptionUids.isNotEmpty) 'selected_options': selectedOptionUids,
    };
    try {
      // If a *cached* cart id fails, it may be consumed/expired (e.g. the cart
      // was just turned into an order) — reset and retry once with a fresh cart
      // so add-to-cart self-heals instead of failing on every tap.
      final hadCachedId = _cartId != null;
      Cart cart;
      try {
        cart = await _repo.addProducts(await _ensureCartId(), [item]);
      } catch (error) {
        if (!hadCachedId) rethrow;
        await _resetCart();
        cart = await _repo.addProducts(await _ensureCartId(), [item]);
      }
      state = state.copyWith(cart: cart, isMutating: false);
    } catch (error) {
      state = state.copyWith(isMutating: false, error: error);
      rethrow;
    }
  }

  /// Batch add (one round-trip) — used by the wishlist "Add all to Bag" so it's
  /// no longer N sequential requests. Best-effort: items the server can't add
  /// (configurables needing options) are skipped, not fatal.
  Future<void> addManyToCart(List<String> skus) async {
    if (skus.isEmpty) return;
    state = state.copyWith(isMutating: true, error: null);
    final items = <Map<String, dynamic>>[
      for (final sku in skus) <String, dynamic>{'sku': sku, 'quantity': 1},
    ];
    try {
      final hadCachedId = _cartId != null;
      Cart cart;
      try {
        cart = await _repo.addProducts(
          await _ensureCartId(),
          items,
          throwOnUserError: false,
        );
      } catch (error) {
        if (!hadCachedId) rethrow;
        await _resetCart();
        cart = await _repo.addProducts(
          await _ensureCartId(),
          items,
          throwOnUserError: false,
        );
      }
      state = state.copyWith(cart: cart, isMutating: false);
    } catch (error) {
      state = state.copyWith(isMutating: false, error: error);
      rethrow;
    }
  }

  /// The order consumed the cart server-side — reset to an empty cart so it
  /// reads empty and the next add creates a fresh one.
  Future<void> clearAfterOrder() async {
    await _resetCart();
    state = const CartState();
  }

  Future<void> setQuantity(String uid, int quantity) async {
    final id = _cartId;
    if (id == null) return;
    state = state.copyWith(isMutating: true, error: null);
    try {
      final cart = quantity <= 0
          ? await _repo.removeItem(id, uid)
          : await _repo.updateItem(id, uid, quantity);
      state = state.copyWith(cart: cart, isMutating: false);
    } catch (error) {
      state = state.copyWith(isMutating: false, error: error);
    }
  }

  Future<void> removeItem(String uid) => setQuantity(uid, 0);

  Future<void> applyCoupon(String code) async {
    state = state.copyWith(isMutating: true, error: null);
    try {
      final id = await _ensureCartId();
      state = state.copyWith(
        cart: await _repo.applyCoupon(id, code),
        isMutating: false,
      );
    } catch (error) {
      state = state.copyWith(isMutating: false, error: error);
      rethrow;
    }
  }

  Future<void> removeCoupon() async {
    final id = _cartId;
    if (id == null) return;
    state = state.copyWith(isMutating: true, error: null);
    try {
      state = state.copyWith(
        cart: await _repo.removeCoupon(id),
        isMutating: false,
      );
    } catch (error) {
      state = state.copyWith(isMutating: false, error: error);
    }
  }

  Future<void> refresh() => _reload();

  Future<void> _onLogin() async {
    try {
      final customerId = await _repo.customerCartId();
      if (customerId == null) return;
      final guestId = _cartId;
      if (guestId != null && guestId != customerId) {
        try {
          await _repo.mergeCarts(guestId, customerId);
        } on Object {
          // Merge is best-effort; fall through to the customer cart.
        }
      }
      _cartId = customerId;
      await _cache.deleteKey(_guestKey);
      await _reload();
    } on Object {
      // ignore: keep current state on merge failure
    }
  }

  Future<void> _onLogout() async {
    _cartId = null;
    await _cache.deleteKey(_guestKey);
    state = const CartState();
  }
}

final cartControllerProvider = NotifierProvider<CartController, CartState>(
  CartController.new,
);

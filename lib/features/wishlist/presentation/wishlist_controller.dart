import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/wishlist_repository.dart';
import '../domain/wishlist_entry.dart';

class WishlistState {
  const WishlistState({
    this.id,
    this.entries = const <WishlistEntry>[],
    this.isLoading = false,
    this.error,
  });

  final String? id;
  final List<WishlistEntry> entries;
  final bool isLoading;
  final Object? error;

  Set<String> get skus => {for (final e in entries) e.product.sku};
  bool contains(String sku) => skus.contains(sku);

  String? itemIdForSku(String sku) {
    for (final entry in entries) {
      if (entry.product.sku == sku) return entry.id;
    }
    return null;
  }

  static const Object _keep = Object();

  WishlistState copyWith({
    String? id,
    List<WishlistEntry>? entries,
    bool? isLoading,
    Object? error = _keep,
  }) => WishlistState(
    id: id ?? this.id,
    entries: entries ?? this.entries,
    isLoading: isLoading ?? this.isLoading,
    error: identical(error, _keep) ? this.error : error,
  );
}

/// Customer-scoped wishlist. Loads on login, clears on logout. Toggling while
/// signed out returns false so the UI can prompt sign-in.
class WishlistController extends Notifier<WishlistState> {
  @override
  WishlistState build() {
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      final wasAuthed = prev?.isAuthenticated ?? false;
      if (next.isAuthenticated && !wasAuthed) {
        _load();
      } else if (next.status == AuthStatus.guest && wasAuthed) {
        state = const WishlistState();
      }
    });
    // A language/store switch flips the `Store` header and resets the GraphQL
    // cache; refetch so item names/prices (and the per-store-view item set)
    // reflect the new store, matching the cart controller's store listener.
    ref.listen<String>(
      storeControllerProvider.select((s) => s.activeStoreCode),
      (prev, next) {
        if (prev != null && prev != next && _isAuthed) {
          Future.microtask(_load);
        }
      },
    );
    if (ref.read(authControllerProvider).isAuthenticated) {
      Future.microtask(_load);
    }
    return const WishlistState();
  }

  WishlistRepository get _repo => ref.read(wishlistRepositoryProvider);
  bool get _isAuthed => ref.read(authControllerProvider).isAuthenticated;

  Future<void> _load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _repo.fetchWishlist();
      state = WishlistState(id: data?.id, entries: data?.entries ?? const []);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> refresh() => _load();

  /// Removes several products by sku in one round-trip — e.g. after they were
  /// added to the cart, so bought items leave the wishlist. No-op for skus not
  /// currently saved.
  Future<void> removeSkus(List<String> skus) async {
    if (skus.isEmpty || !_isAuthed) return;
    final wishlistId = state.id;
    if (wishlistId == null) return;
    final itemIds = <String>[];
    for (final sku in skus) {
      final id = state.itemIdForSku(sku);
      if (id != null) itemIds.add(id);
    }
    if (itemIds.isEmpty) return;
    try {
      final data = await _repo.removeItems(wishlistId, itemIds);
      state = WishlistState(id: data.id, entries: data.entries);
    } catch (error) {
      state = state.copyWith(error: error);
    }
  }

  /// Adds or removes [sku]. Returns false when the user must sign in first.
  Future<bool> toggle(String sku) async {
    if (!_isAuthed) return false;
    if (state.id == null) await _load();
    final wishlistId = state.id;
    if (wishlistId == null) return true;
    try {
      final WishlistData data;
      if (state.contains(sku)) {
        final itemId = state.itemIdForSku(sku);
        if (itemId == null) return true;
        data = await _repo.removeItem(wishlistId, itemId);
      } else {
        data = await _repo.addProduct(wishlistId, sku);
      }
      state = WishlistState(id: data.id, entries: data.entries);
    } catch (error) {
      state = state.copyWith(error: error);
    }
    return true;
  }
}

final wishlistControllerProvider =
    NotifierProvider<WishlistController, WishlistState>(WishlistController.new);

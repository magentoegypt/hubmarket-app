import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../personalization/data/insights_tracker.dart';
import '../data/wishlist_repository.dart';
import '../domain/wishlist_entry.dart';

class WishlistState {
  const WishlistState({
    this.id,
    this.entries = const <WishlistEntry>[],
    this.itemsCount,
    this.isLoading = false,
    this.error,
  });

  final String? id;
  final List<WishlistEntry> entries;

  /// The store's own count of what is saved, when it said (see
  /// [WishlistData.itemsCount]).
  final int? itemsCount;
  final bool isLoading;
  final Object? error;

  /// How many products are saved: what the Wishlist tab's badge shows. The
  /// store's count when it is larger than the entries on hand, otherwise the
  /// entries themselves. Zero for a guest, who has no wishlist.
  int get count => math.max(entries.length, itemsCount ?? 0);

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
    int? itemsCount,
    bool? isLoading,
    Object? error = _keep,
  }) => WishlistState(
    id: id ?? this.id,
    entries: entries ?? this.entries,
    itemsCount: itemsCount ?? this.itemsCount,
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
    // cache; refetch so item names/prices reflect the new store's language,
    // matching the cart controller's store listener. The set of items is the
    // same in every language: what was saved under the other store view is
    // listed too (see [WishlistQueries]).
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
      state = _from(data);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  /// The state an answer from the store makes (the wishlist's id, its first
  /// page of items and the store's count of all of them); none is an empty one.
  WishlistState _from(WishlistData? data) => WishlistState(
    id: data?.id,
    entries: data?.entries ?? const <WishlistEntry>[],
    itemsCount: data?.itemsCount,
  );

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
      state = _from(data);
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
        // "Added to Wishlist" for Algolia Personalization.
        trackInsights(
          () => ref.read(insightsTrackerProvider),
          (tracker) => tracker.addedToWishlist(sku),
        );
      }
      state = _from(data);
    } catch (error) {
      state = state.copyWith(error: error);
    }
    return true;
  }
}

final wishlistControllerProvider =
    NotifierProvider<WishlistController, WishlistState>(WishlistController.new);

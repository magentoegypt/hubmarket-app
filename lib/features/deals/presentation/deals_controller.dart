import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../../catalog/domain/product.dart';
import '../data/deals_repository.dart';
import '../domain/deals.dart';

/// How Today's Deals are ordered: the backend's rank (deepest percentage
/// discount first), or by price.
enum DealsSort { biggestDiscount, priceLowHigh, priceHighLow }

/// A top-level category among the loaded deals, with how many it holds.
@immutable
class DealsCategory {
  const DealsCategory({
    required this.uid,
    required this.name,
    required this.count,
  });

  final String uid;
  final String name;
  final int count;
}

@immutable
class DealsState {
  const DealsState({
    this.items = const <Product>[],
    this.totalCount = 0,
    this.countdownEndsAt,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.error,
    this.categoryUid,
    this.sort = DealsSort.biggestDiscount,
  });

  /// Every deal loaded so far, in the backend's rank.
  final List<Product> items;
  final int totalCount;
  final DateTime? countdownEndsAt;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  /// The selected category chip; null is "All deals".
  final String? categoryUid;
  final DealsSort sort;

  /// The deals to show: [categoryUid]'s, in [sort] order.
  List<Product> get visible {
    final picked = categoryUid == null
        ? items
        : [
            for (final p in items)
              if (p.categories.any((c) => c.uid == categoryUid)) p,
          ];
    double price(Product p) =>
        (p.finalPrice ?? p.regularPrice)?.amount ?? double.infinity;
    return switch (sort) {
      DealsSort.biggestDiscount => picked,
      DealsSort.priceLowHigh => [...picked]
        ..sort((a, b) => price(a).compareTo(price(b))),
      DealsSort.priceHighLow => [...picked]
        ..sort((a, b) => price(b).compareTo(price(a))),
    };
  }

  /// The count line: the backend's total for "All deals", else the
  /// category's own.
  int get visibleCount => categoryUid == null ? totalCount : visible.length;

  /// Chips: the top-level menu categories the loaded deals sit in, the
  /// busiest first.
  List<DealsCategory> get categories {
    final counts = <String, int>{};
    final names = <String, String>{};
    for (final product in items) {
      final seen = <String>{};
      for (final c in product.categories) {
        if (c.level != 2 || !c.inMenu || !seen.add(c.uid)) continue;
        counts[c.uid] = (counts[c.uid] ?? 0) + 1;
        names[c.uid] = c.name;
      }
    }
    final chips = [
      for (final MapEntry(key: uid, value: count) in counts.entries)
        DealsCategory(uid: uid, name: names[uid]!, count: count),
    ]..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.name.compareTo(b.name);
      });
    return chips;
  }

  DealsState copyWith({
    List<Product>? items,
    int? totalCount,
    DateTime? countdownEndsAt,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _keep,
    Object? categoryUid = _keep,
    DealsSort? sort,
  }) => DealsState(
    items: items ?? this.items,
    totalCount: totalCount ?? this.totalCount,
    countdownEndsAt: countdownEndsAt ?? this.countdownEndsAt,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: identical(error, _keep) ? this.error : error,
    categoryUid: identical(categoryUid, _keep)
        ? this.categoryUid
        : categoryUid as String?,
    sort: sort ?? this.sort,
  );

  static const Object _keep = Object();
}

/// Today's Deals (10b): every live deal, read in pages of 50 — the ranking
/// stops at 200 — so the category chips and the price sorts work on the whole
/// list. The first page shows as soon as it arrives.
class DealsController extends AutoDisposeNotifier<DealsState> {
  static const int pageSize = DealsRepository.maxPageSize;

  /// The backend ranks at most 200 deals.
  static const int maxPages = 4;

  int _generation = 0;

  @override
  DealsState build() {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    Future.microtask(_load);
    return const DealsState();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final repository = ref.read(dealsRepositoryProvider);
    state = state.copyWith(isLoading: true, error: null);
    DealsPage page;
    try {
      page = await repository.fetchDeals(pageSize: pageSize);
    } catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(isLoading: false, error: error);
      return;
    }
    if (generation != _generation) return;
    state = state.copyWith(
      items: page.items,
      totalCount: page.totalCount,
      countdownEndsAt: page.countdownEndsAt,
      isLoading: false,
      isLoadingMore: page.pageInfo.hasMore,
    );
    var current = page.pageInfo.currentPage;
    while (page.pageInfo.hasMore && current < maxPages) {
      try {
        page = await repository.fetchDeals(
          pageSize: pageSize,
          currentPage: current + 1,
        );
      } catch (_) {
        break; // What arrived stays; a refresh reads the rest.
      }
      if (generation != _generation) return;
      current = page.pageInfo.currentPage;
      state = state.copyWith(items: [...state.items, ...page.items]);
    }
    if (generation == _generation) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh() => _load();

  void selectCategory(String? uid) => state = state.copyWith(categoryUid: uid);

  void setSort(DealsSort sort) => state = state.copyWith(sort: sort);
}

final dealsControllerProvider =
    NotifierProvider.autoDispose<DealsController, DealsState>(
      DealsController.new,
    );

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_cache.dart';

/// A guest order this device placed (or looked up), kept only so the app can
/// re-fetch it later. Guests have no `customer { orders }` history, so without
/// this the order number and its token are lost the moment checkout state is
/// reset and "Track Order" has nothing to resolve.
///
/// Holds no order *content* — just the credentials Magento's `guestOrder` /
/// `guestOrderByToken` queries need. Status, items and tracking are always
/// re-fetched live.
class GuestOrderRef {
  const GuestOrderRef({
    required this.number,
    this.token,
    this.email,
    this.lastname,
    this.placedAt,
  });

  /// Magento increment id (e.g. `2000000037`).
  final String number;

  /// `placeOrder.orderV2.token` — the preferred lookup key: it authorizes on
  /// its own, with no personal data.
  final String? token;

  /// Billing e-mail + last name from checkout — the fallback lookup key, and
  /// the only one available for an order the guest typed in by hand.
  final String? email;
  final String? lastname;

  /// ISO-8601 timestamp of when this device recorded the order (sort key only;
  /// the real order date comes from the API).
  final String? placedAt;

  bool get hasToken => token != null && token!.isNotEmpty;

  bool get hasEmailPair =>
      (email != null && email!.isNotEmpty) &&
      (lastname != null && lastname!.isNotEmpty);

  /// Usable only when at least one of the two lookup keys is present.
  bool get isResolvable => hasToken || hasEmailPair;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'number': number,
    if (token != null) 'token': token,
    if (email != null) 'email': email,
    if (lastname != null) 'lastname': lastname,
    if (placedAt != null) 'placedAt': placedAt,
  };

  static GuestOrderRef? fromJson(Map<String, dynamic> json) {
    final number = json['number'];
    if (number is! String || number.isEmpty) return null;
    return GuestOrderRef(
      number: number,
      token: json['token'] as String?,
      email: json['email'] as String?,
      lastname: json['lastname'] as String?,
      placedAt: json['placedAt'] as String?,
    );
  }
}

/// Persisted guest order references (most-recent first, de-duped by order
/// number, capped), backed by [LocalCache] (Hive) — same pattern as
/// `SearchHistory`.
class GuestOrderStore extends Notifier<List<GuestOrderRef>> {
  static const String _key = 'guest_orders';
  static const int _max = 10;

  LocalCache get _cache => ref.read(localCacheProvider);

  @override
  List<GuestOrderRef> build() {
    final raw = _cache.readString(_key);
    if (raw == null) return const <GuestOrderRef>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(GuestOrderRef.fromJson)
            .whereType<GuestOrderRef>()
            .toList();
      }
    } on Object {
      // Corrupt payload — start clean.
    }
    return const <GuestOrderRef>[];
  }

  /// Records [order] at the front, replacing any earlier entry for the same
  /// order number. An entry with neither lookup key is ignored — it could never
  /// be resolved and would just render as a permanently failing row.
  Future<void> remember(GuestOrderRef order) async {
    if (!order.isResolvable) return;
    final next = <GuestOrderRef>[
      order,
      ...state.where((e) => e.number != order.number),
    ].take(_max).toList();
    await _write(next);
  }

  /// Drops an order that the backend no longer recognises, so a dead entry
  /// can't wedge the list on every load.
  Future<void> forget(String number) async {
    if (!state.any((e) => e.number == number)) return;
    await _write(state.where((e) => e.number != number).toList());
  }

  Future<void> clear() async {
    state = const <GuestOrderRef>[];
    await _cache.deleteKey(_key);
  }

  Future<void> _write(List<GuestOrderRef> next) async {
    state = next;
    await _cache.writeString(
      _key,
      jsonEncode([for (final e in next) e.toJson()]),
    );
  }
}

final guestOrderStoreProvider =
    NotifierProvider<GuestOrderStore, List<GuestOrderRef>>(GuestOrderStore.new);

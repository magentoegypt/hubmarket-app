import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_cache.dart';

/// Persisted recent search terms (most-recent first, de-duped, capped), backed
/// by [LocalCache] (Hive). Drives the idle search screen's "Recent" list.
class SearchHistory extends Notifier<List<String>> {
  static const String _key = 'search_history';
  static const int _max = 8;

  LocalCache get _cache => ref.read(localCacheProvider);

  @override
  List<String> build() {
    final raw = _cache.readString(_key);
    if (raw == null) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } on Object {
      // Corrupt payload — start clean.
    }
    return const <String>[];
  }

  /// Records a searched term at the front, dropping any case-insensitive dupe
  /// and trimming to [_max].
  Future<void> add(String term) async {
    final t = term.trim();
    if (t.isEmpty) return;
    final next = <String>[
      t,
      ...state.where((e) => e.toLowerCase() != t.toLowerCase()),
    ].take(_max).toList();
    state = next;
    await _cache.writeString(_key, jsonEncode(next));
  }

  Future<void> clear() async {
    state = const <String>[];
    await _cache.deleteKey(_key);
  }
}

final searchHistoryProvider = NotifierProvider<SearchHistory, List<String>>(
  SearchHistory.new,
);

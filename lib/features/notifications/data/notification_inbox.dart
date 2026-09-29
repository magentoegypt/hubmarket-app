import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/local_cache.dart';
import '../domain/notification_item.dart';

/// Local, persisted notification inbox. A long-lived singleton (created in
/// `bootstrap`) that listens to [NotificationService.onNotificationReceived]
/// and appends every push to a Hive-backed list, so the feed survives restarts
/// and captures notifications even when the screen isn't open.
class NotificationInbox {
  NotificationInbox._();
  static final NotificationInbox instance = NotificationInbox._();

  static const String _cacheKey = 'notification_inbox';
  static const int _maxItems = 100;

  LocalCache? _cache;
  StreamSubscription<NotificationMessage>? _sub;

  /// The inbox contents, newest first. The feed binds to this directly.
  final ValueNotifier<List<NotificationItem>> items =
      ValueNotifier<List<NotificationItem>>(const []);

  int get unreadCount => items.value.where((i) => !i.read).length;

  Future<void> init(LocalCache cache) async {
    _cache = cache;
    _load();
    _sub ??= NotificationService.instance.onNotificationReceived.listen(
      _onReceived,
    );
  }

  void _load() {
    final raw = _cache?.readString(_cacheKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      items.value = decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => NotificationItem.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    } catch (_) {
      // Corrupt cache — start clean.
    }
  }

  void _onReceived(NotificationMessage message) {
    final data = message.data;
    final id =
        (data['message_id'] ?? data['google.message_id'])?.toString() ??
        DateTime.now().microsecondsSinceEpoch.toString();
    // Dedup (the same push can arrive via onMessage and onMessageOpenedApp).
    if (items.value.any((i) => i.id == id)) return;
    final item = NotificationItem(
      id: id,
      kind: NotificationItem.kindFrom(data),
      title: message.title ?? '',
      body: message.body ?? '',
      receivedAt: DateTime.now(),
      data: data,
    );
    add(item);
  }

  void add(NotificationItem item) {
    final next = [item, ...items.value];
    items.value = next.length > _maxItems ? next.sublist(0, _maxItems) : next;
    _persist();
  }

  void markAllRead() {
    if (items.value.every((i) => i.read)) return;
    items.value = [for (final i in items.value) i.copyWith(read: true)];
    _persist();
  }

  void markRead(String id) {
    items.value = [
      for (final i in items.value) i.id == id ? i.copyWith(read: true) : i,
    ];
    _persist();
  }

  void clear() {
    items.value = const [];
    _persist();
  }

  void _persist() {
    _cache?.writeString(
      _cacheKey,
      jsonEncode([for (final i in items.value) i.toJson()]),
    );
  }
}

/// Exposes the singleton inbox to the widget tree.
final notificationInboxProvider = Provider<NotificationInbox>(
  (ref) => NotificationInbox.instance,
);

/// A single received notification, persisted in the local inbox.
enum NotificationKind { order, promo, wishlist, delivered, welcome, general }

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.receivedAt,
    this.read = false,
    this.data = const <String, dynamic>{},
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime receivedAt;
  final bool read;

  /// Original push data payload — used to route when tapped.
  final Map<String, dynamic> data;

  NotificationItem copyWith({bool? read}) => NotificationItem(
    id: id,
    kind: kind,
    title: title,
    body: body,
    receivedAt: receivedAt,
    read: read ?? this.read,
    data: data,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'body': body,
    'receivedAt': receivedAt.toIso8601String(),
    'read': read,
    'data': data,
  };

  factory NotificationItem.fromJson(Map<String, dynamic> json) =>
      NotificationItem(
        id: (json['id'] as String?) ?? '',
        kind: NotificationKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => NotificationKind.general,
        ),
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        receivedAt:
            DateTime.tryParse(json['receivedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        read: (json['read'] as bool?) ?? false,
        data:
            (json['data'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );

  /// Infers a kind from the push `type`/`kind` payload (falls back to general).
  static NotificationKind kindFrom(Map<String, dynamic> data) {
    final t = (data['type'] ?? data['kind'] ?? '').toString().toLowerCase();
    if (t.contains('deliver')) return NotificationKind.delivered;
    if (t.contains('order') || t.contains('shipment')) {
      return NotificationKind.order;
    }
    if (t.contains('promo') || t.contains('offer') || t.contains('sale')) {
      return NotificationKind.promo;
    }
    if (t.contains('wishlist') || t.contains('price')) {
      return NotificationKind.wishlist;
    }
    if (t.contains('welcome')) return NotificationKind.welcome;
    return NotificationKind.general;
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/returns/data/return_photo_picker.dart';
import 'package:hubmarket_app/features/returns/data/returns_repository.dart';
import 'package:hubmarket_app/features/returns/domain/return_photo.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';

/// Test doubles and sample data for returns (Figma 23 / 23b / 23c).

const HmSellerSummary kLolyStore = HmSellerSummary(
  name: 'loly store',
  code: 'loly',
  vendorEntityId: 12,
);

const HmSellerSummary kMiaCo = HmSellerSummary(
  name: 'MIA CO',
  code: 'miaco',
  vendorEntityId: 31,
);

const HmSellerSummary kHubMarket = HmSellerSummary(
  name: 'Hub Market',
  isMarketplace: true,
);

const ReturnConfig kSampleReturnConfig = ReturnConfig(
  reasonsEnabled: true,
  otherReasonAllowed: true,
  partialQuantityAllowed: true,
  reasons: [
    ReturnReason(id: 1, label: 'Doesn’t fit — too small'),
    ReturnReason(id: 2, label: 'Arrived damaged'),
    ReturnReason(id: 3, label: 'Not as described'),
  ],
);

/// [kSampleReturnConfig] with the website's default upload rules: photos on.
const ReturnConfig kPhotoReturnConfig = ReturnConfig(
  reasonsEnabled: true,
  otherReasonAllowed: true,
  partialQuantityAllowed: true,
  reasons: [
    ReturnReason(id: 1, label: 'Doesn’t fit — too small'),
    ReturnReason(id: 2, label: 'Arrived damaged'),
    ReturnReason(id: 3, label: 'Not as described'),
  ],
  attachmentExtensions: [
    'txt',
    'jpg',
    'jpeg',
    'png',
    'gif',
    'pdf',
    'zip',
    'rar',
    'csv',
    'doc',
    'docx',
  ],
  attachmentMaxBytes: 2097152,
  attachmentMaxFiles: 5,
);

/// An order of two sellers: a T-shirt (2 returnable of 2, AED 43 each) and a
/// bag already held by return R-000031 from loly store, a sofa bed (AED 425)
/// from MIA CO.
const ReturnableOrder kTwoSellerOrder = ReturnableOrder(
  number: '000000150',
  createdAt: '2026-09-22T08:30:00Z',
  statusLabel: 'Complete',
  items: [
    ReturnableItem(
      orderItemId: 501,
      sku: 'TS-S-GRN',
      name: 'Short Square-Neck T-Shirt',
      options: [
        ReturnOption(label: 'Size', value: 'S'),
        ReturnOption(label: 'Color', value: 'Green'),
      ],
      qtyOrdered: 2,
      qtyReturnable: 2,
      seller: kLolyStore,
      unitPrice: Money(amount: 43, currency: 'AED'),
      rowTotal: Money(amount: 86, currency: 'AED'),
      maxRefund: Money(amount: 86, currency: 'AED'),
    ),
    ReturnableItem(
      orderItemId: 502,
      sku: 'BAG-1',
      name: 'Joust Duffle Bag',
      qtyOrdered: 1,
      qtyReturnable: 0,
      openReturnNumbers: ['R-000031'],
      seller: kLolyStore,
      unitPrice: Money(amount: 29, currency: 'AED'),
      rowTotal: Money(amount: 29, currency: 'AED'),
      maxRefund: Money(amount: 0, currency: 'AED'),
    ),
    ReturnableItem(
      orderItemId: 503,
      sku: 'SOFA-TEAL',
      name: 'Corner Sofa Bed',
      options: [ReturnOption(label: 'Color', value: 'Teal')],
      qtyOrdered: 1,
      qtyReturnable: 1,
      seller: kMiaCo,
      unitPrice: Money(amount: 425, currency: 'AED'),
      rowTotal: Money(amount: 425, currency: 'AED'),
      maxRefund: Money(amount: 425, currency: 'AED'),
    ),
  ],
);

/// An order with one returnable line (it starts ticked).
const ReturnableOrder kSingleLineOrder = ReturnableOrder(
  number: '000000148',
  createdAt: '2026-09-20T10:00:00Z',
  statusLabel: 'Processing',
  items: [
    ReturnableItem(
      orderItemId: 480,
      sku: 'POLO-M',
      name: 'Polo Shirt',
      options: [ReturnOption(label: 'Size', value: 'M')],
      qtyOrdered: 1,
      qtyReturnable: 1,
      seller: kHubMarket,
      unitPrice: Money(amount: 120, currency: 'AED'),
      rowTotal: Money(amount: 120, currency: 'AED'),
      maxRefund: Money(amount: 120, currency: 'AED'),
    ),
  ],
);

/// An order as a server without `unit_price` lists it: its prices come from
/// the core order ([kLegacyUnits]).
const ReturnableOrder kLegacyOrder = ReturnableOrder(
  number: '000000140',
  createdAt: '2026-09-10T10:00:00Z',
  statusLabel: 'Complete',
  items: [
    ReturnableItem(
      orderItemId: 470,
      sku: 'MUG-1',
      name: 'Enamel Mug',
      qtyOrdered: 3,
      qtyReturnable: 3,
      seller: kLolyStore,
    ),
  ],
);

/// Per-unit refund base of [kLegacyOrder]'s line, from the core order.
const Map<int, Money> kLegacyUnits = {470: Money(amount: 55, currency: 'AED')};

/// Photos as the picker hands them over: small PNGs.
final Uint8List kGreenPhoto = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGOQa/GEIwbiOAB7cw6xOo/q1QAAAABJRU5ErkJggg==',
);
final Uint8List kGreyPhoto = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEUlEQVR4nGOYsngHHDEQxwEAIoEe8emzP28AAAAASUVORK5CYII=',
);

/// What the picker hands over for an iPhone photo it didn't convert.
final Uint8List kHeicPhoto = Uint8List.fromList([
  0, 0, 0, 24, ...ascii.encode('ftypheic'), 0, 0, 0, 0, //
]);

/// The photo library and camera, without a device: hands over [photos].
class FakeReturnPhotoPicker implements ReturnPhotoPicker {
  FakeReturnPhotoPicker({List<Uint8List>? photos, this.failure})
    : photos = photos ?? [kGreenPhoto];

  final List<Uint8List> photos;
  final Object? failure;
  final List<({ReturnPhotoSource source, int limit})> calls = [];

  @override
  Future<List<Uint8List>> pick(
    ReturnPhotoSource source, {
    required int limit,
  }) async {
    calls.add((source: source, limit: limit));
    if (failure != null) throw failure!;
    return photos.take(limit).toList();
  }
}

ReturnSummary sampleReturnSummary({
  int id = 31,
  String number = 'R-000031',
  ReturnState state = ReturnState.open,
  String? statusCode,
  String statusLabel = 'Awaiting store',
  ReturnType type = ReturnType.refund,
  bool unread = false,
  HmSellerSummary? seller = kLolyStore,
  String createdAt = '2026-09-24T09:00:00Z',
  Money? refundAmount,
  ReturnSummaryItem? firstItem = const ReturnSummaryItem(
    name: 'Short Square-Neck T-Shirt',
  ),
  int itemCount = 1,
}) => ReturnSummary(
  id: id,
  number: number,
  orderNumber: '000000150',
  createdAt: createdAt,
  updatedAt: createdAt,
  state: state,
  statusCode:
      statusCode ??
      switch (state) {
        ReturnState.open => 'pending',
        ReturnState.closed => 'resolved',
        ReturnState.canceled => 'canceled',
      },
  statusLabel: statusLabel,
  type: type,
  itemCount: itemCount,
  seller: seller,
  hasUnreadReply: unread,
  refundAmount: refundAmount,
  firstItem: firstItem,
);

ReturnDetail sampleReturnDetail({
  int id = 31,
  ReturnState state = ReturnState.open,
  String? statusCode,
  String statusLabel = 'Awaiting store',
  bool arabic = false,
  List<ReturnMessage>? messages,
  bool? canReply,
  bool? canCancel,
  bool? canEscalate,
  ReturnEscalation? escalation,
  bool photo = true,
}) => ReturnDetail(
  id: id,
  number: 'R-000031',
  orderNumber: '000000150',
  createdAt: '2026-09-24T14:02:00Z',
  updatedAt: '2026-09-25T05:15:00Z',
  state: state,
  statusCode:
      statusCode ??
      switch (state) {
        ReturnState.open => 'pending',
        ReturnState.closed => 'resolved',
        ReturnState.canceled => 'canceled',
      },
  statusLabel: statusLabel,
  type: ReturnType.refund,
  reason: ReturnReason(
    id: 1,
    label: arabic ? 'المقاس غير مناسب' : 'Doesn’t fit — too small',
  ),
  packageOpened: true,
  refundAmountType: RefundAmountType.full,
  refundAmount: const Money(amount: 43, currency: 'AED'),
  seller: arabic
      ? const HmSellerSummary(
          name: 'متجر لولي',
          code: 'loly',
          vendorEntityId: 12,
        )
      : kLolyStore,
  items: [
    ReturnItem(
      orderItemId: 501,
      sku: 'TS-S-GRN',
      name: arabic ? 'تيشيرت قصير ياقة مربع' : 'Short Square-Neck T-Shirt',
      quantity: 1,
    ),
  ],
  history: const [
    ReturnHistoryEntry(
      statusCode: 'pending',
      statusLabel: 'Open',
      changedBy: ReturnActor.customer,
      createdAt: '2026-09-24T14:02:00Z',
    ),
  ],
  messages:
      messages ??
      [
        ReturnMessage(
          id: 1,
          author: ReturnActor.customer,
          authorName: 'Sara Ahmed',
          bodyText: arabic
              ? 'المقاس S صغير جدًا، أرجو ترتيب الاستلام. البطاقات ما زالت عليه.'
              : 'Size S is too small, please arrange a pickup. Tags are still on.',
          // Renders pass photo: false — tests can't load network images.
          attachments: [
            if (photo)
              const ReturnAttachment(
                name: 'photo-1-1_k3v9x0q2ab.jpg',
                url:
                    'https://hub-market.magento2.click/media/rma/request/photo-1-1_k3v9x0q2ab.jpg',
              ),
          ],
          createdAt: '2026-09-24T14:02:00Z',
        ),
        ReturnMessage(
          id: 2,
          author: ReturnActor.seller,
          authorName: arabic ? 'متجر لولي' : 'loly store',
          bodyText: arabic
              ? 'أهلًا سارة، نعتذر عن المقاس! سيستلمه المندوب الثلاثاء 30 سبتمبر بين 10:00 و14:00.'
              : 'Hi Sara, sorry about the fit! A courier will collect it on Tue 30 Sep between 10:00 and 14:00.',
          createdAt: '2026-09-25T05:15:00Z',
        ),
        ReturnMessage(
          id: 3,
          author: ReturnActor.hubMarket,
          authorName: 'Hub Market',
          bodyText: arabic
              ? 'تابعنا مع المتجر وسيتواصل معك قريبًا.'
              : 'We followed up with the store; they will be in touch shortly.',
          createdAt: '2026-09-25T09:40:00Z',
        ),
      ],
  // The website's rules, as the server reports them for the sample's status.
  canReply: canReply ?? state == ReturnState.open,
  canCancel: canCancel ?? state == ReturnState.open,
  canEscalate: canEscalate ?? state != ReturnState.canceled,
  escalation: escalation,
);

/// [detail] with some of its fields changed, as the server returns it after
/// a reply, an escalation or a cancellation.
ReturnDetail changedReturn(
  ReturnDetail detail, {
  ReturnState? state,
  String? statusCode,
  String? statusLabel,
  List<ReturnHistoryEntry>? history,
  List<ReturnMessage>? messages,
  bool? canReply,
  bool? canCancel,
  bool? canEscalate,
  ReturnEscalation? escalation,
}) => ReturnDetail(
  id: detail.id,
  number: detail.number,
  orderNumber: detail.orderNumber,
  createdAt: detail.createdAt,
  updatedAt: detail.updatedAt,
  state: state ?? detail.state,
  statusCode: statusCode ?? detail.statusCode,
  statusLabel: statusLabel ?? detail.statusLabel,
  type: detail.type,
  reason: detail.reason,
  otherReason: detail.otherReason,
  packageOpened: detail.packageOpened,
  refundAmountType: detail.refundAmountType,
  refundAmount: detail.refundAmount,
  trackingCode: detail.trackingCode,
  seller: detail.seller,
  items: detail.items,
  history: history ?? detail.history,
  messages: messages ?? detail.messages,
  canReply: canReply ?? detail.canReply,
  canCancel: canCancel ?? detail.canCancel,
  canEscalate: canEscalate ?? detail.canEscalate,
  escalation: escalation ?? detail.escalation,
);

/// Where the server keeps a message's files.
String _fileUrl(ReturnPhoto photo) =>
    'https://hub-market.magento2.click/media/rma/request/${photo.name}';

/// Returns data in memory. Records every write so tests can assert the exact
/// call; [missing] makes every call answer like a server without the module.
class FakeReturnsRepository implements ReturnsRepository {
  FakeReturnsRepository({
    this.config = kSampleReturnConfig,
    List<ReturnableOrder>? orders,
    this.units = const {'000000140': kLegacyUnits},
    this.summaries = const [],
    Map<int, ReturnDetail>? details,
    this.createFailure,
    this.replyFailure,
    this.escalateFailure,
    this.cancelFailure,
    this.missing = false,
    this.pageSize = 20,
  }) : orders = orders ?? [kTwoSellerOrder, kSingleLineOrder],
       details = details ?? <int, ReturnDetail>{};

  final ReturnConfig config;
  final List<ReturnableOrder> orders;
  final Map<String, Map<int, Money>> units;
  final List<ReturnSummary> summaries;
  final Map<int, ReturnDetail> details;
  final Failure? createFailure;
  final Failure? replyFailure;
  final Failure? escalateFailure;
  final Failure? cancelFailure;
  final bool missing;
  final int pageSize;

  final List<Map<String, dynamic>> createInputs = [];
  final List<({int returnId, String message})> replies = [];

  /// The photos of each reply in [replies].
  final List<List<ReturnPhoto>> replyPhotos = [];
  final List<({int returnId, String message, List<ReturnPhoto> photos})>
  escalations = [];
  final List<int> cancellations = [];
  final List<int> returnableOrderPages = [];
  final List<String> returnableOrderLookups = [];
  final List<String> unitRefundLookups = [];

  @override
  void Function()? get onModuleMissing => null;

  void _check() {
    if (missing) {
      throw const HubAppMissing(
        'Cannot query field "hmReturnConfig" on type "Query".',
      );
    }
  }

  ReturnsPage<T> _page<T>(List<T> all, int page) {
    final items = all.skip((page - 1) * pageSize).take(pageSize).toList();
    final pages = all.isEmpty ? 0 : (all.length / pageSize).ceil();
    return ReturnsPage<T>(
      items: items,
      totalCount: all.length,
      currentPage: page,
      totalPages: pages,
    );
  }

  @override
  Future<ReturnConfig> fetchConfig() async {
    _check();
    return config;
  }

  @override
  Future<ReturnsPage<ReturnableOrder>> fetchReturnableOrders({
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    _check();
    returnableOrderPages.add(currentPage);
    return _page(orders, currentPage);
  }

  @override
  Future<ReturnableOrder?> fetchReturnableOrder(String orderNumber) async {
    _check();
    returnableOrderLookups.add(orderNumber);
    final order = orders.where((o) => o.number == orderNumber).firstOrNull;
    return order != null && order.hasReturnableItem ? order : null;
  }

  @override
  Future<Map<int, Money>> fetchUnitRefunds(String orderNumber) async {
    unitRefundLookups.add(orderNumber);
    return units[orderNumber] ?? const <int, Money>{};
  }

  @override
  Future<ReturnsPage<ReturnSummary>> fetchReturns({
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    _check();
    return _page(summaries, currentPage);
  }

  @override
  Future<ReturnDetail?> fetchReturn(int id) async {
    _check();
    return details[id];
  }

  @override
  Future<ReturnDetail> createReturn(Map<String, dynamic> input) async {
    _check();
    createInputs.add(input);
    if (createFailure != null) throw createFailure!;
    final created = sampleReturnDetail(id: 77);
    details[77] = created;
    return created;
  }

  @override
  Future<ReturnDetail> addMessage(
    int returnId,
    String message, {
    List<ReturnPhoto> photos = const <ReturnPhoto>[],
  }) async {
    _check();
    replies.add((returnId: returnId, message: message));
    replyPhotos.add(photos);
    if (replyFailure != null) throw replyFailure!;
    final current = details[returnId]!;
    final updated = changedReturn(
      current,
      messages: [
        ...current.messages,
        ReturnMessage(
          id: 99,
          author: ReturnActor.customer,
          authorName: 'Layla Hassan',
          bodyText: message,
          attachments: [
            for (final photo in photos)
              ReturnAttachment(name: photo.name, url: _fileUrl(photo)),
          ],
          createdAt: '2026-09-29T10:00:00Z',
        ),
      ],
    );
    details[returnId] = updated;
    return updated;
  }

  @override
  Future<ReturnDetail> escalate(
    int returnId,
    String message, {
    List<ReturnPhoto> photos = const <ReturnPhoto>[],
  }) async {
    _check();
    escalations.add((returnId: returnId, message: message, photos: photos));
    if (escalateFailure != null) throw escalateFailure!;
    final current = details[returnId]!;
    final updated = changedReturn(
      current,
      state: ReturnState.open,
      statusCode: 'awaiting',
      statusLabel: 'Escalated',
      history: [
        ...current.history,
        const ReturnHistoryEntry(
          statusCode: 'awaiting',
          statusLabel: 'Escalated',
          changedBy: ReturnActor.customer,
          createdAt: '2026-09-29T11:00:00Z',
        ),
      ],
      canReply: true,
      canCancel: false,
      canEscalate: false,
      escalation: ReturnEscalation(
        bodyText: message,
        attachments: [
          for (final photo in photos)
            ReturnAttachment(name: photo.name, url: _fileUrl(photo)),
        ],
        createdAt: '2026-09-29T11:00:00Z',
      ),
    );
    details[returnId] = updated;
    return updated;
  }

  @override
  Future<ReturnDetail> cancel(int returnId) async {
    _check();
    cancellations.add(returnId);
    if (cancelFailure != null) throw cancelFailure!;
    final current = details[returnId]!;
    final updated = changedReturn(
      current,
      state: ReturnState.canceled,
      statusCode: 'canceled',
      statusLabel: 'Canceled',
      history: [
        ...current.history,
        const ReturnHistoryEntry(
          statusCode: 'canceled',
          statusLabel: 'Canceled',
          changedBy: ReturnActor.customer,
          createdAt: '2026-09-29T12:00:00Z',
        ),
      ],
      canReply: false,
      canCancel: false,
      canEscalate: false,
    );
    details[returnId] = updated;
    return updated;
  }
}

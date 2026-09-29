import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/returns/data/returns_repository.dart';
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

/// An order of two sellers: a T-shirt (2 returnable of 2) and a bag already
/// held by return R-000031 from loly store, a sofa bed from MIA CO.
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
    ),
    ReturnableItem(
      orderItemId: 502,
      sku: 'BAG-1',
      name: 'Joust Duffle Bag',
      qtyOrdered: 1,
      qtyReturnable: 0,
      openReturnNumbers: ['R-000031'],
      seller: kLolyStore,
    ),
    ReturnableItem(
      orderItemId: 503,
      sku: 'SOFA-TEAL',
      name: 'Corner Sofa Bed',
      options: [ReturnOption(label: 'Color', value: 'Teal')],
      qtyOrdered: 1,
      qtyReturnable: 1,
      seller: kMiaCo,
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
    ),
  ],
);

/// Per-unit refund base of [kTwoSellerOrder]'s lines.
const Map<int, Money> kTwoSellerUnits = {
  501: Money(amount: 43, currency: 'AED'),
  502: Money(amount: 29, currency: 'AED'),
  503: Money(amount: 425, currency: 'AED'),
};

ReturnSummary sampleReturnSummary({
  int id = 31,
  String number = 'R-000031',
  ReturnState state = ReturnState.open,
  String statusLabel = 'Awaiting store',
  ReturnType type = ReturnType.refund,
  bool unread = false,
  HmSellerSummary? seller = kLolyStore,
  String createdAt = '2026-09-24T09:00:00Z',
}) => ReturnSummary(
  id: id,
  number: number,
  orderNumber: '000000150',
  createdAt: createdAt,
  updatedAt: createdAt,
  state: state,
  statusLabel: statusLabel,
  type: type,
  itemCount: 1,
  seller: seller,
  hasUnreadReply: unread,
);

ReturnDetail sampleReturnDetail({
  int id = 31,
  ReturnState state = ReturnState.open,
  String statusLabel = 'Awaiting store',
  bool arabic = false,
  List<ReturnMessage>? messages,
}) => ReturnDetail(
  id: id,
  number: 'R-000031',
  orderNumber: '000000150',
  createdAt: '2026-09-24T14:02:00Z',
  updatedAt: '2026-09-25T05:15:00Z',
  state: state,
  statusCode: state == ReturnState.open ? 'pending' : 'resolved',
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
);

/// Returns data in memory. Records every write so tests can assert the exact
/// call; [missing] makes every call answer like a server without the module.
class FakeReturnsRepository implements ReturnsRepository {
  FakeReturnsRepository({
    this.config = kSampleReturnConfig,
    this.orders = const [kTwoSellerOrder, kSingleLineOrder],
    this.units = const {'000000150': kTwoSellerUnits},
    this.summaries = const [],
    Map<int, ReturnDetail>? details,
    this.createFailure,
    this.replyFailure,
    this.missing = false,
    this.pageSize = 20,
  }) : details = details ?? <int, ReturnDetail>{};

  final ReturnConfig config;
  final List<ReturnableOrder> orders;
  final Map<String, Map<int, Money>> units;
  final List<ReturnSummary> summaries;
  final Map<int, ReturnDetail> details;
  final Failure? createFailure;
  final Failure? replyFailure;
  final bool missing;
  final int pageSize;

  final List<Map<String, dynamic>> createInputs = [];
  final List<({int returnId, String message})> replies = [];
  final List<int> returnableOrderPages = [];

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
  Future<Map<int, Money>> fetchUnitRefunds(String orderNumber) async =>
      units[orderNumber] ?? const <int, Money>{};

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
  Future<ReturnDetail> addMessage(int returnId, String message) async {
    _check();
    replies.add((returnId: returnId, message: message));
    if (replyFailure != null) throw replyFailure!;
    final current = details[returnId]!;
    final updated = ReturnDetail(
      id: current.id,
      number: current.number,
      orderNumber: current.orderNumber,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt,
      state: current.state,
      statusCode: current.statusCode,
      statusLabel: current.statusLabel,
      type: current.type,
      reason: current.reason,
      packageOpened: current.packageOpened,
      refundAmountType: current.refundAmountType,
      refundAmount: current.refundAmount,
      seller: current.seller,
      items: current.items,
      history: current.history,
      messages: [
        ...current.messages,
        ReturnMessage(
          id: 99,
          author: ReturnActor.customer,
          authorName: 'Layla Hassan',
          bodyText: message,
          createdAt: '2026-09-29T10:00:00Z',
        ),
      ],
    );
    details[returnId] = updated;
    return updated;
  }
}

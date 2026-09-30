import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../../core/store/store_controller.dart';
import '../../catalog/domain/money.dart';
import '../domain/returns.dart';
import 'returns_mapper.dart';
import 'returns_queries.dart';

/// Returns (RMA) through the HubAppReturns GraphQL. Every call needs the
/// customer token, so this runs on the authenticated client (POST).
///
/// Returns domain entities, or throws:
/// * [HubAppMissing] when the server has no returns API (the module isn't
///   deployed) — callers hide returns rather than report an error, and
///   [onModuleMissing] is told;
/// * a [Failure] otherwise. A store refusal (not eligible, too many units,
///   two sellers, over the refund cap, a closed return) is a `server` failure
///   carrying the store's localized message.
class ReturnsRepository {
  ReturnsRepository(this._client, {this.onModuleMissing});

  final GraphQLClient _client;

  /// Called when a request finds the returns API missing.
  final VoidCallback? onModuleMissing;

  /// Largest page `hmReturnableOrders` serves.
  static const int returnableOrdersPageSize = 20;

  static const int returnsPageSize = 20;

  Future<ReturnConfig> fetchConfig() async {
    final data = await _query(ReturnsQueries.config);
    final config = data['hmReturnConfig'];
    if (config is! Map<String, dynamic>) {
      throw const Failure(FailureKind.unknown, detail: 'hmReturnConfig: none');
    }
    return returnConfigFromJson(config);
  }

  Future<ReturnsPage<ReturnableOrder>> fetchReturnableOrders({
    int pageSize = returnableOrdersPageSize,
    int currentPage = 1,
  }) async {
    final data = await _query(
      ReturnsQueries.returnableOrders,
      variables: {'pageSize': pageSize, 'currentPage': currentPage},
    );
    return returnsPageFromJson(
      data['hmReturnableOrders'] as Map<String, dynamic>?,
      returnableOrderFromJson,
      requestedPage: currentPage,
    );
  }

  /// The per-unit refund base of each line of order [orderNumber]
  /// (`order_item_id` → amount), from the core order — see
  /// [unitRefundsFromOrderJson]. Empty when the order can't be found.
  Future<Map<int, Money>> fetchUnitRefunds(String orderNumber) async {
    final data = await _query(
      ReturnsQueries.orderLinePrices,
      variables: {'number': orderNumber},
    );
    final orders =
        ((data['customer'] as Map<String, dynamic>?)?['orders']
                as Map<String, dynamic>?)?['items']
            as List<dynamic>?;
    for (final order in orders ?? const <dynamic>[]) {
      if (order is Map<String, dynamic> && order['number'] == orderNumber) {
        return unitRefundsFromOrderJson(order);
      }
    }
    return const <int, Money>{};
  }

  Future<ReturnsPage<ReturnSummary>> fetchReturns({
    int pageSize = returnsPageSize,
    int currentPage = 1,
  }) async {
    final data = await _query(
      ReturnsQueries.returns,
      variables: {'pageSize': pageSize, 'currentPage': currentPage},
    );
    return returnsPageFromJson(
      data['hmReturns'] as Map<String, dynamic>?,
      returnSummaryFromJson,
      requestedPage: currentPage,
    );
  }

  /// One of the customer's returns; null when there's no such return or it
  /// isn't theirs. Reading it marks it read.
  Future<ReturnDetail?> fetchReturn(int id) async {
    final data = await _query(
      ReturnsQueries.returnDetail,
      variables: {'id': id},
    );
    final rma = data['hmReturn'];
    return rma is Map<String, dynamic> ? returnDetailFromJson(rma) : null;
  }

  /// Files a return; [input] is an `HmCreateReturnInput`
  /// (`ReturnDraft.toInput`). Returns the new return.
  ///
  /// Only after [fetchConfig] / [fetchReturnableOrders] answered: the
  /// document declares a variable of an `Hm*` input type, which a server
  /// without the module answers with HTTP 500 rather than "Cannot query
  /// field".
  Future<ReturnDetail> createReturn(Map<String, dynamic> input) async {
    final data = await _mutate(ReturnsQueries.createReturn, {'input': input});
    return _rma(data['hmCreateReturn']);
  }

  /// Posts the customer's reply on return [returnId] and returns the return
  /// with it.
  Future<ReturnDetail> addMessage(int returnId, String message) async {
    final data = await _mutate(ReturnsQueries.addMessage, {
      'returnId': returnId,
      'message': message,
    });
    return _rma(data['hmAddReturnMessage']);
  }

  ReturnDetail _rma(Object? output) {
    final rma = output is Map<String, dynamic> ? output['rma'] : null;
    if (rma is! Map<String, dynamic>) {
      throw const Failure(FailureKind.unknown, detail: 'return: no rma');
    }
    return returnDetailFromJson(rma);
  }

  Future<Map<String, dynamic>> _query(
    String document, {
    Map<String, dynamic> variables = const <String, dynamic>{},
  }) async {
    try {
      return await runHubAppQuery(_client, document, variables: variables);
    } on HubAppMissing {
      onModuleMissing?.call();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _mutate(
    String document,
    Map<String, dynamic> variables,
  ) async {
    final QueryResult result;
    try {
      result = await _client.mutate(
        MutationOptions(
          document: gql(document),
          variables: variables,
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
    } on Failure {
      rethrow;
    } catch (error) {
      throw Failure(FailureKind.unknown, detail: error.toString());
    }
    final exception = result.exception;
    if (exception != null) {
      if (isHubAppMissing(exception)) {
        onModuleMissing?.call();
        throw HubAppMissing(
          exception.graphqlErrors.firstOrNull?.message ?? 'returns missing',
        );
      }
      throw mapOperationException(exception);
    }
    return result.data ?? const <String, dynamic>{};
  }
}

/// The session learnt that the server has no returns API (HubApp itself may
/// be there without its returns module): returns stay hidden until the next
/// store switch or launch, as the HubApp probe does.
final returnsModuleMissingProvider = StateProvider<bool>((ref) {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  return false;
});

/// On the authenticated client: returns are the signed-in customer's.
final returnsRepositoryProvider = Provider<ReturnsRepository>(
  (ref) => ReturnsRepository(
    ref.watch(graphqlClientProvider),
    onModuleMissing: () {
      // A request may outlive this repository (a sign-out rebuilds the
      // client); the latch is a hint, so a disposed ref is not an error.
      try {
        ref.read(returnsModuleMissingProvider.notifier).state = true;
      } on Object {
        return;
      }
    },
  ),
);

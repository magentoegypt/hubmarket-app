import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/store_credit/data/store_credit_queries.dart';
import 'package:hubmarket_app/features/store_credit/data/store_credit_repository.dart';
import 'package:hubmarket_app/features/store_credit/domain/store_credit.dart';

import '../../support/hubapp_fakes.dart';

Map<String, dynamic> _money(double value) => {
  '__typename': 'Money',
  'value': value,
  'currency': 'AED',
};

Map<String, dynamic> _account({
  bool canUse = true,
  int page = 1,
  int pages = 2,
}) => {
  'hmStoreCredit': {
    '__typename': 'HmStoreCreditAccount',
    'balance': _money(120),
    'can_use_at_checkout': canUse,
    'total_count': 3,
    'page_info': {
      '__typename': 'SearchResultPageInfo',
      'current_page': page,
      'page_size': 20,
      'total_pages': pages,
    },
    'transactions': [
      {
        '__typename': 'HmStoreCreditTransaction',
        'id': 31,
        'type': 'refund_by_credit',
        'type_label': 'Refund By Credit',
        'amount': _money(43),
        'balance_after': _money(120),
        'description': 'Order refunded #000000031, Creditmemo #000000004',
        'created_at': '2026-09-26T08:14:00Z',
        'order_number': '000000031',
      },
      {
        '__typename': 'HmStoreCreditTransaction',
        'id': 30,
        'type': 'spend_credit',
        'type_label': 'Spend Credit',
        'amount': _money(-23),
        'balance_after': _money(77),
        'description': null,
        'created_at': '2026-09-20T11:02:00Z',
        'order_number': null,
      },
    ],
  },
};

Map<String, dynamic> _cart({
  double applied = 0,
  double grandTotal = 553,
  List<String> methods = const ['cashondelivery'],
}) => {
  '__typename': 'Cart',
  'id': 'cart-1',
  'hm_store_credit': {
    '__typename': 'HmCartStoreCredit',
    'applied': _money(applied),
    'balance': _money(120),
    'max_applicable': _money(120),
    'can_use': true,
  },
  'prices': {'__typename': 'CartPrices', 'grand_total': _money(grandTotal)},
  'available_payment_methods': [
    for (final code in methods)
      {
        '__typename': 'AvailablePaymentMethod',
        'code': code,
        'title': code,
        'is_deferred': false,
      },
  ],
};

OperationDefinitionNode _operation(Request request) => request
    .operation
    .document
    .definitions
    .whereType<OperationDefinitionNode>()
    .first;

void main() {
  group('StoreCreditRepository', () {
    test(
      'reads the balance, the spending rule and a page of transactions',
      () async {
        final client = fakeHubAppClient({'HmStoreCredit': _account()});
        final account = await StoreCreditRepository(
          client,
        ).fetchAccount(currentPage: 1);

        expect(account.balance, const Money(amount: 120, currency: 'AED'));
        expect(account.canUseAtCheckout, isTrue);
        expect(account.totalCount, 3);
        expect(account.hasMore, isTrue);
        expect(account.transactions, hasLength(2));
        final refund = account.transactions.first;
        expect(refund.kind, StoreCreditTransactionKind.refunded);
        expect(refund.isCredit, isTrue);
        expect(refund.typeLabel, 'Refund By Credit');
        expect(refund.createdAt, '2026-09-26T08:14:00Z');
        // The customer's own order it records; none on the other line.
        expect(refund.orderNumber, '000000031');
        final spend = account.transactions.last;
        expect(spend.kind, StoreCreditTransactionKind.spent);
        expect(spend.magnitude.amount, 23);
        expect(spend.description, isNull);
        expect(spend.orderNumber, isNull);
        expect(client.requests.single.variables, {
          'pageSize': 20,
          'currentPage': 1,
        });
        // Customer data: POST through the token client, never a GET.
        expect(_operation(client.requests.single).type, OperationType.query);
      },
    );

    test('a group that may not spend credit reads as such', () async {
      final client = fakeHubAppClient({
        'HmStoreCreditBalance': _account(canUse: false),
      });
      final account = await StoreCreditRepository(client).fetchBalance();
      expect(account.canUseAtCheckout, isFalse);
      expect(account.balance.amount, 120);
    });

    test('a server without the module throws HubAppMissing', () async {
      final client = fakeHubAppClient({
        'HmStoreCredit': hubAppMissingResponse('hmStoreCredit'),
      });
      await expectLater(
        StoreCreditRepository(client).fetchAccount(),
        throwsA(isA<HubAppMissing>()),
      );
    });

    test('a network failure is a Failure, not a missing module', () async {
      final client = fakeHubAppClient({
        'HmStoreCredit': Exception('connection closed'),
      });
      await expectLater(
        StoreCreditRepository(client).fetchAccount(),
        throwsA(isA<Failure>()),
      );
    });

    test('reads the credit on the cart', () async {
      final client = fakeHubAppClient({
        'HmCartStoreCredit': {'cart': _cart(applied: 23)},
      });
      final credit = await StoreCreditRepository(
        client,
      ).fetchCartCredit('cart-1');
      expect(credit!.applied.amount, 23);
      expect(credit.isApplied, isTrue);
      expect(credit.maxApplicable.amount, 120);
      expect(credit.offered, isTrue);
      expect(client.requests.single.variables, {'cartId': 'cart-1'});
    });

    test('a guest cart has no credit', () async {
      final client = fakeHubAppClient({
        'HmCartStoreCredit': {
          'cart': {..._cart(), 'hm_store_credit': null},
        },
      });
      expect(
        await StoreCreditRepository(client).fetchCartCredit('cart-1'),
        isNull,
      );
    });

    test(
      'applying sends the amount and reads the recollected cart back',
      () async {
        final client = fakeHubAppClient({
          'HmApplyStoreCredit': {
            'hmApplyStoreCredit': {
              '__typename': 'HmStoreCreditCartOutput',
              'cart': _cart(applied: 120, grandTotal: 433),
            },
          },
        });
        final update = await StoreCreditRepository(client).apply('cart-1', 120);

        final request = client.requests.single;
        expect(_operation(request).type, OperationType.mutation);
        expect(request.variables, {'cartId': 'cart-1', 'amount': 120.0});
        expect(update.credit!.applied.amount, 120);
        expect(update.grandTotal!.amount, 433);
        expect(update.paymentMethods!.single.code, 'cashondelivery');
      },
    );

    test(
      'credit that covers the order leaves Zero Subtotal Checkout',
      () async {
        final client = fakeHubAppClient({
          'HmApplyStoreCredit': {
            'hmApplyStoreCredit': {
              '__typename': 'HmStoreCreditCartOutput',
              'cart': _cart(applied: 90, grandTotal: 0, methods: ['free']),
            },
          },
        });
        final update = await StoreCreditRepository(client).apply('cart-1', 90);
        expect(update.grandTotal!.amount, 0);
        expect(update.paymentMethods!.single.isFree, isTrue);
      },
    );

    test('a refusal keeps the store message', () async {
      final client = fakeHubAppClient({
        'HmApplyStoreCredit': Response(
          errors: const [
            GraphQLError(
              message: 'You can use at most AED 120.00 of store credit.',
              extensions: {'category': 'graphql-input'},
            ),
          ],
          response: const <String, dynamic>{},
        ),
      });
      await expectLater(
        StoreCreditRepository(client).apply('cart-1', 500),
        throwsA(
          isA<Failure>()
              .having((f) => f.kind, 'kind', FailureKind.server)
              .having(
                (f) => f.detail,
                'detail',
                'You can use at most AED 120.00 of store credit.',
              ),
        ),
      );
    });

    test('removing reads the cart back without credit', () async {
      final client = fakeHubAppClient({
        'HmRemoveStoreCredit': {
          'hmRemoveStoreCredit': {
            '__typename': 'HmStoreCreditCartOutput',
            'cart': _cart(),
          },
        },
      });
      final update = await StoreCreditRepository(client).remove('cart-1');
      expect(update.credit!.isApplied, isFalse);
      expect(client.requests.single.variables, {'cartId': 'cart-1'});
    });

    test('reads the credit an order used, by its number', () async {
      Map<String, dynamic> orders(Map<String, dynamic>? credit) => {
        'customer': {
          '__typename': 'Customer',
          'orders': {
            '__typename': 'CustomerOrders',
            'items': [
              {
                '__typename': 'CustomerOrder',
                'number': '000000248',
                'total': {
                  '__typename': 'OrderTotal',
                  'hm_store_credit': credit,
                },
              },
            ],
          },
        },
      };
      final used = StoreCreditRepository(
        fakeHubAppClient({'HmOrderStoreCredit': orders(_money(23))}),
      );
      expect(
        await used.fetchOrderCredit('000000248'),
        const Money(amount: 23, currency: 'AED'),
      );
      final none = StoreCreditRepository(
        fakeHubAppClient({'HmOrderStoreCredit': orders(null)}),
      );
      expect(await none.fetchOrderCredit('000000248'), isNull);
      final other = StoreCreditRepository(
        fakeHubAppClient({'HmOrderStoreCredit': orders(_money(23))}),
      );
      expect(await other.fetchOrderCredit('000000999'), isNull);
    });
  });

  group('StoreCreditRepository.fetchTopUp', () {
    Map<String, dynamic> topUp(Map<String, dynamic>? json) => {
      'hmStoreCredit': {'__typename': 'HmStoreCreditAccount', 'top_up': json},
    };
    Map<String, dynamic> preset(String sku, double credit, double price) => {
      '__typename': 'HmStoreCreditPreset',
      'sku': sku,
      'credit': _money(credit),
      'price': _money(price),
    };

    test('reads the presets and the custom range', () async {
      final client = fakeHubAppClient({
        'HmStoreCreditTopUp': topUp({
          '__typename': 'HmStoreCreditTopUp',
          'sku': 'hm-credit-any',
          'min': _money(10),
          'max': _money(1000),
          'credit_rate': 1.25,
          'presets': [
            preset('hm-credit-250', 250, 250),
            preset('hm-credit-50', 50, 50),
            preset('hm-credit-100', 100, 90),
          ],
        }),
      });
      final offer = await StoreCreditRepository(client).fetchTopUp();

      expect(offer, isNotNull);
      expect(offer!.sku, 'hm-credit-any');
      expect(offer.presets.map((p) => p.credit.amount), [50, 100, 250]);
      expect(offer.presets[1].price.amount, 90);
      expect(offer.allowsCustomAmount, isTrue);
      expect(offer.min!.amount, 10);
      expect(offer.max!.amount, 1000);
      expect(offer.creditRate, 1.25);
      // Customer data: a query through the token client, never a GET.
      expect(_operation(client.requests.single).type, OperationType.query);
      expect(client.requests.single.variables, isEmpty);
    });

    test('null while the store sells no credit', () async {
      final client = fakeHubAppClient({'HmStoreCreditTopUp': topUp(null)});
      expect(await StoreCreditRepository(client).fetchTopUp(), isNull);
    });

    test('presets only when there is no usable range', () async {
      for (final range in [
        {'min': null, 'max': null, 'credit_rate': null},
        {'min': _money(100), 'max': _money(10), 'credit_rate': 1},
        {'min': _money(10), 'max': _money(100), 'credit_rate': 0},
      ]) {
        final client = fakeHubAppClient({
          'HmStoreCreditTopUp': topUp({
            '__typename': 'HmStoreCreditTopUp',
            'sku': 'hm-credit-50',
            ...range,
            'presets': [preset('hm-credit-50', 50, 50)],
          }),
        });
        final offer = await StoreCreditRepository(client).fetchTopUp();
        expect(offer!.allowsCustomAmount, isFalse, reason: '$range');
        expect(offer.creditRate, isNull);
        expect(offer.presets, hasLength(1));
      }
    });

    test('nothing that can be bought reads as no top-up', () async {
      final client = fakeHubAppClient({
        'HmStoreCreditTopUp': topUp({
          '__typename': 'HmStoreCreditTopUp',
          'sku': 'broken',
          'min': null,
          'max': null,
          'credit_rate': null,
          'presets': [preset('free', 0, 0)],
        }),
      });
      expect(await StoreCreditRepository(client).fetchTopUp(), isNull);
    });

    test('a server without the field throws HubAppMissing', () async {
      final client = fakeHubAppClient({
        'HmStoreCreditTopUp': hubAppMissingResponse(
          'top_up',
          type: 'HmStoreCreditAccount',
        ),
      });
      await expectLater(
        StoreCreditRepository(client).fetchTopUp(),
        throwsA(isA<HubAppMissing>()),
      );
    });
  });

  test('no document declares a variable of an Hm* type', () {
    // While the module is missing Magento answers an unknown variable type
    // with HTTP 500 instead of "Cannot query field" (the Build 1 fallback).
    for (final document in [
      StoreCreditQueries.account,
      StoreCreditQueries.topUp,
      StoreCreditQueries.balance,
      StoreCreditQueries.cartCredit,
      StoreCreditQueries.apply,
      StoreCreditQueries.remove,
      StoreCreditQueries.orderCredit,
    ]) {
      expect(document, isNot(matches(RegExp(r'\$\w+\s*:\s*\[?Hm'))));
    }
  });
}

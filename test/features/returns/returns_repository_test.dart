import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/returns/data/returns_mapper.dart';
import 'package:hubmarket_app/features/returns/data/returns_queries.dart';
import 'package:hubmarket_app/features/returns/data/returns_repository.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';
import 'package:hubmarket_app/features/returns/presentation/returns_providers.dart';

import '../../support/hubapp_fakes.dart';

/// Contract-shaped answers (HubAppReturns section of CONTRACT.graphql).

Map<String, dynamic> _seller(String name, {int? id, String? code}) => {
  '__typename': 'HmSellerSummary',
  'code': code,
  'vendor_entity_id': id,
  'name': name,
  'logo_url': null,
  'rating': null,
  'review_count': 0,
  'product_count': 0,
  'is_marketplace': id == null,
  'link': null,
};

Map<String, dynamic> _pageInfo(int page, int pages) => {
  '__typename': 'SearchResultPageInfo',
  'current_page': page,
  'total_pages': pages,
};

Map<String, dynamic> _returnableOrder(
  String number, {
  String createdAt = '2026-09-22T08:30:00Z',
  double returnable = 2,
}) => {
  '__typename': 'HmReturnableOrder',
  'order_number': number,
  'created_at': createdAt,
  'status_label': 'Complete',
  'items': [
    {
      '__typename': 'HmReturnableItem',
      'order_item_id': 501,
      'sku': 'TS-S-GRN',
      'name': 'Short Square-Neck T-Shirt',
      'image_url': 'http://hub-market.magento2.click/media/t.jpg',
      'options': [
        {'__typename': 'HmLabelValue', 'label': 'Size', 'value': 'S'},
      ],
      'qty_ordered': 2.0,
      'qty_returnable': returnable,
      'open_return_numbers': ['R-000031'],
      'seller': _seller('loly store', id: 12, code: 'loly'),
    },
  ],
};

Map<String, dynamic> _rma({String state = 'OPEN'}) => {
  '__typename': 'HmReturn',
  'id': 31,
  'number': 'R-000031',
  'order_number': '000000150',
  'created_at': '2026-09-24T14:02:00Z',
  'updated_at': '2026-09-25T05:15:00Z',
  'state': state,
  'status_code': 'pending',
  'status_label': 'Open',
  'type': 'REPLACE',
  'reason': {'__typename': 'HmReturnReason', 'id': 1, 'label': 'Too small'},
  'other_reason': null,
  'package_opened': true,
  'refund_amount_type': null,
  'refund_amount': null,
  'tracking_code': 'ARX-1',
  'seller': _seller('loly store', id: 12, code: 'loly'),
  'items': [
    {
      '__typename': 'HmReturnItem',
      'order_item_id': 501,
      'sku': 'TS-S-GRN',
      'name': 'Short Square-Neck T-Shirt',
      'image_url': null,
      'quantity': 1.0,
    },
  ],
  'history': [
    {
      '__typename': 'HmReturnHistoryEntry',
      'status_code': 'pending',
      'status_label': 'Open',
      'changed_by': 'CUSTOMER',
      'created_at': '2026-09-24T14:02:00Z',
    },
  ],
  'messages': [
    {
      '__typename': 'HmReturnMessage',
      'id': 1,
      'author': 'CUSTOMER',
      'author_name': 'Sara Ahmed',
      'body_html': '<p>Too small</p>',
      'body_text': 'Too small',
      'attachment_urls': ['http://hub-market.magento2.click/media/rma/1.jpg'],
      'created_at': '2026-09-24T14:02:00Z',
    },
    {
      '__typename': 'HmReturnMessage',
      'id': 2,
      'author': 'HUB_MARKET',
      'author_name': 'Hub Market',
      'body_html': '<p>On it</p>',
      'body_text': 'On it',
      'attachment_urls': <String>[],
      'created_at': '2026-09-25T05:15:00Z',
    },
  ],
};

String _uid(int id) => base64.encode(utf8.encode('$id'));

Map<String, dynamic> _variables(Request request) =>
    Map<String, dynamic>.of(request.variables);

void main() {
  group('reads', () {
    test('hmReturnConfig', () async {
      final repo = ReturnsRepository(
        fakeHubAppClient({
          'HmReturnConfig': {
            'hmReturnConfig': {
              '__typename': 'HmReturnConfig',
              'enabled': true,
              'reasons_enabled': true,
              'other_reason_allowed': false,
              'partial_quantity_allowed': true,
              'reasons': [
                {'__typename': 'HmReturnReason', 'id': 2, 'label': 'Damaged'},
                {'__typename': 'HmReturnReason', 'id': 0, 'label': 'bad row'},
              ],
              'policy_html': '<p>30 days</p>',
              'window_days': null,
            },
          },
        }),
      );
      final config = await repo.fetchConfig();
      expect(config.enabled, isTrue);
      expect(config.reasonsEnabled, isTrue);
      expect(config.otherReasonAllowed, isFalse);
      expect(config.partialQuantityAllowed, isTrue);
      expect(config.reasons.map((r) => (r.id, r.label)), [(2, 'Damaged')]);
      expect(config.policyHtml, '<p>30 days</p>');
      expect(config.windowDays, isNull);
    });

    test('hmReturnableOrders, paged, with lines and their seller', () async {
      final client = fakeHubAppClient({
        'HmReturnableOrders': {
          'hmReturnableOrders': {
            '__typename': 'HmReturnableOrderPage',
            'total_count': 21,
            'page_info': _pageInfo(2, 2),
            'items': [_returnableOrder('000000150', returnable: 1.9)],
          },
        },
      });
      final page = await ReturnsRepository(
        client,
      ).fetchReturnableOrders(currentPage: 2);

      expect(_variables(client.requests.single), {
        'pageSize': 20,
        'currentPage': 2,
      });
      expect(page.totalCount, 21);
      expect(page.hasMore, isFalse);
      final order = page.items.single;
      expect(order.number, '000000150');
      expect(order.statusLabel, 'Complete');
      final line = order.items.single;
      expect(line.orderItemId, 501);
      expect(line.qtyReturnable, 1, reason: 'whole units only');
      expect(line.imageUrl, startsWith('https://'));
      expect(line.options.single.value, 'S');
      expect(line.openReturnNumbers, ['R-000031']);
      expect(line.seller?.name, 'loly store');
      expect(line.seller?.vendorEntityId, 12);
    });

    test('hmReturns rows', () async {
      final page = await ReturnsRepository(
        fakeHubAppClient({
          'HmReturns': {
            'hmReturns': {
              '__typename': 'HmReturnPage',
              'total_count': 1,
              'page_info': _pageInfo(1, 1),
              'items': [
                {
                  '__typename': 'HmReturnSummary',
                  'id': 31,
                  'number': 'R-000031',
                  'order_number': '000000150',
                  'created_at': '2026-09-24T14:02:00Z',
                  'updated_at': '2026-09-25T05:15:00Z',
                  'state': 'CANCELED',
                  'status_label': 'Canceled',
                  'type': 'REFUND',
                  'item_count': 2,
                  'seller': _seller('Hub Market'),
                  'has_unread_reply': true,
                },
              ],
            },
          },
        }),
      ).fetchReturns();
      final row = page.items.single;
      expect(row.id, 31);
      expect(row.state, ReturnState.canceled);
      expect(row.type, ReturnType.refund);
      expect(row.itemCount, 2);
      expect(row.hasUnreadReply, isTrue);
      expect(row.seller?.isMarketplace, isTrue);
    });

    test(
      'hmReturn: lines, history and the thread; null when not theirs',
      () async {
        final client = fakeHubAppClient({
          'HmReturn': {'hmReturn': _rma()},
        });
        final detail = (await ReturnsRepository(client).fetchReturn(31))!;
        expect(_variables(client.requests.single), {'id': 31});
        expect(detail.type, ReturnType.replace);
        expect(detail.acceptsReplies, isTrue);
        expect(detail.reasonText, 'Too small');
        expect(detail.trackingCode, 'ARX-1');
        expect(detail.items.single.quantity, 1);
        expect(detail.history.single.changedBy, ReturnActor.customer);
        expect(detail.messages.map((m) => m.author), [
          ReturnActor.customer,
          ReturnActor.hubMarket,
        ]);
        expect(detail.messages.last.authorName, 'Hub Market');
        expect(
          detail.messages.first.attachmentUrls.single,
          startsWith('https://'),
        );

        final none = await ReturnsRepository(
          fakeHubAppClient({
            'HmReturn': {'hmReturn': null},
          }),
        ).fetchReturn(99);
        expect(none, isNull);
      },
    );

    test('a closed or cancelled return takes no replies', () {
      expect(
        returnDetailFromJson(_rma(state: 'CLOSED')).acceptsReplies,
        isFalse,
      );
      expect(
        returnDetailFromJson(_rma(state: 'CANCELED')).acceptsReplies,
        isFalse,
      );
    });

    test('the refund base per unit, from the core order lines', () async {
      final repo = ReturnsRepository(
        fakeHubAppClient({
          'ReturnOrderLinePrices': {
            'customer': {
              '__typename': 'Customer',
              'orders': {
                '__typename': 'CustomerOrders',
                'items': [
                  {
                    '__typename': 'CustomerOrder',
                    'number': '000000150',
                    'items': [
                      {
                        '__typename': 'OrderItem',
                        'id': _uid(501),
                        'quantity_ordered': 2.0,
                        'prices': {
                          '__typename': 'OrderItemPrices',
                          'row_total_including_tax': {
                            '__typename': 'Money',
                            'value': 100.0,
                            'currency': 'AED',
                          },
                          'total_item_discount': {
                            '__typename': 'Money',
                            'value': 14.0,
                            'currency': 'AED',
                          },
                        },
                      },
                    ],
                  },
                ],
              },
            },
          },
        }),
      );
      expect(await repo.fetchUnitRefunds('000000150'), {
        501: const Money(amount: 43, currency: 'AED'),
      });
      expect(await repo.fetchUnitRefunds('000000999'), isEmpty);
      expect(orderItemIdFromUid('not base64!'), isNull);
    });
  });

  group('writes', () {
    test('hmCreateReturn sends the input as given', () async {
      final client = fakeHubAppClient({
        'HmCreateReturn': {
          'hmCreateReturn': {'__typename': 'HmReturnOutput', 'rma': _rma()},
        },
      });
      final input = {
        'order_number': '000000150',
        'items': [
          {'order_item_id': 501, 'quantity': 1.0},
        ],
        'type': 'REFUND',
        'reason_id': 1,
        'package_opened': true,
        'comment': 'Too small',
        'refund_amount_type': 'FULL',
      };
      final created = await ReturnsRepository(client).createReturn(input);
      expect(created.id, 31);
      expect(_variables(client.requests.single), {'input': input});
    });

    test('hmAddReturnMessage sends scalar variables', () async {
      final client = fakeHubAppClient({
        'HmAddReturnMessage': {
          'hmAddReturnMessage': {'__typename': 'HmReturnOutput', 'rma': _rma()},
        },
      });
      await ReturnsRepository(client).addMessage(31, 'Any news?');
      expect(_variables(client.requests.single), {
        'returnId': 31,
        'message': 'Any news?',
      });
    });

    test('a store refusal carries its message', () async {
      final repo = ReturnsRepository(
        fakeHubAppClient({
          'HmCreateReturn': Response(
            errors: const [
              GraphQLError(
                message:
                    'Items sold by different sellers need separate returns.',
              ),
            ],
            response: const <String, dynamic>{},
          ),
        }),
      );
      await expectLater(
        repo.createReturn(const {'order_number': '1'}),
        throwsA(
          isA<Failure>()
              .having((f) => f.kind, 'kind', FailureKind.server)
              .having((f) => f.detail, 'detail', contains('different sellers')),
        ),
      );
    });
  });

  group('a server without the returns module', () {
    test('answers HubAppMissing and latches returns off', () async {
      var missing = 0;
      final repo = ReturnsRepository(
        fakeHubAppClient({'HmReturns': hubAppMissingResponse('hmReturns')}),
        onModuleMissing: () => missing++,
      );
      await expectLater(repo.fetchReturns(), throwsA(isA<HubAppMissing>()));
      expect(missing, 1);
    });

    test('a network failure is not mistaken for it', () async {
      var missing = 0;
      final repo = ReturnsRepository(
        fakeHubAppClient({'HmReturns': Exception('offline')}),
        onModuleMissing: () => missing++,
      );
      await expectLater(repo.fetchReturns(), throwsA(isA<Failure>()));
      expect(missing, 0);
    });

    test('only hmCreateReturn declares an Hm* variable', () {
      final documents = {
        'config': ReturnsQueries.config,
        'returnableOrders': ReturnsQueries.returnableOrders,
        'returns': ReturnsQueries.returns,
        'returnDetail': ReturnsQueries.returnDetail,
        'addMessage': ReturnsQueries.addMessage,
        'orderLinePrices': ReturnsQueries.orderLinePrices,
      };
      for (final entry in documents.entries) {
        final types = gql(entry.value).definitions
            .whereType<OperationDefinitionNode>()
            .expand((op) => op.variableDefinitions)
            .map((v) => v.type)
            .whereType<NamedTypeNode>()
            .map((t) => t.name.value);
        expect(
          types.where((t) => t.startsWith('Hm')),
          isEmpty,
          reason: entry.key,
        );
      }
    });
  });

  group('findReturnableOrder', () {
    Map<String, dynamic> page(
      List<Map<String, dynamic>> orders,
      int n,
      int of,
    ) => {
      'hmReturnableOrders': {
        '__typename': 'HmReturnableOrderPage',
        'total_count': 40,
        'page_info': _pageInfo(n, of),
        'items': orders,
      },
    };

    test('pages until the order turns up', () async {
      var call = 0;
      final client = GraphQLClient(
        link: Link.function((request, [forward]) {
          call++;
          final data = call == 1
              ? page([_returnableOrder('000000160')], 1, 3)
              : page([_returnableOrder('000000150')], 2, 3);
          return Stream.value(
            Response(data: data, response: const <String, dynamic>{}),
          );
        }),
        cache: GraphQLCache(partialDataPolicy: PartialDataCachePolicy.accept),
      );
      final found = await findReturnableOrder(
        ReturnsRepository(client),
        '000000150',
      );
      expect(found?.number, '000000150');
      expect(call, 2);
    });

    test('stops at orders a day older than the one asked for', () async {
      final client = fakeHubAppClient({
        'HmReturnableOrders': page(
          [_returnableOrder('000000120', createdAt: '2026-09-01T08:00:00Z')],
          1,
          5,
        ),
      });
      final found = await findReturnableOrder(
        ReturnsRepository(client),
        '000000150',
        placedAt: '2026-09-22 12:30:00',
      );
      expect(found, isNull);
      expect(client.requests, hasLength(1));
    });

    test('an order with nothing returnable left is not offered', () async {
      final found = await findReturnableOrder(
        ReturnsRepository(
          fakeHubAppClient({
            'HmReturnableOrders': page(
              [_returnableOrder('000000150', returnable: 0)],
              1,
              1,
            ),
          }),
        ),
        '000000150',
      );
      expect(found, isNull);
    });
  });
}

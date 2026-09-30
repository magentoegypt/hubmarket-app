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
import 'package:hubmarket_app/features/returns/domain/return_photo.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';

import '../../support/hubapp_fakes.dart';
import '../../support/returns_fakes.dart';

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

Map<String, dynamic> _money(num value) => {
  '__typename': 'Money',
  'value': value.toDouble(),
  'currency': 'AED',
};

Map<String, dynamic> _returnableOrder(
  String number, {
  String createdAt = '2026-09-22T08:30:00Z',
  double returnable = 2,
  bool prices = true,
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
      'unit_price': prices ? _money(43) : null,
      'row_total': prices ? _money(86) : null,
      'max_refund': prices ? _money(43 * returnable.floorToDouble()) : null,
    },
  ],
};

Map<String, dynamic> _attachment(String name, {String scheme = 'https'}) => {
  '__typename': 'HmReturnAttachment',
  'name': name,
  'url': '$scheme://hub-market.magento2.click/media/rma/request/$name',
};

Map<String, dynamic> _rma({
  String state = 'OPEN',
  String statusCode = 'pending',
  bool canReply = true,
  bool canCancel = true,
  bool canEscalate = true,
  Map<String, dynamic>? escalation,
}) => {
  '__typename': 'HmReturn',
  'id': 31,
  'number': 'R-000031',
  'order_number': '000000150',
  'created_at': '2026-09-24T14:02:00Z',
  'updated_at': '2026-09-25T05:15:00Z',
  'state': state,
  'status_code': statusCode,
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
      'body_text': 'Too small',
      'attachments': [
        _attachment('1_ab12cd34ef.jpg', scheme: 'http'),
        _attachment('receipt.pdf'),
      ],
      'created_at': '2026-09-24T14:02:00Z',
    },
    {
      '__typename': 'HmReturnMessage',
      'id': 2,
      'author': 'HUB_MARKET',
      'author_name': 'Hub Market',
      'body_text': 'On it',
      'attachments': <Map<String, dynamic>>[],
      'created_at': '2026-09-25T05:15:00Z',
    },
  ],
  'can_reply': canReply,
  'can_cancel': canCancel,
  'can_escalate': canEscalate,
  'escalation': escalation,
};

String _uid(int id) => base64.encode(utf8.encode('$id'));

Map<String, dynamic> _variables(Request request) =>
    Map<String, dynamic>.of(request.variables);

/// The variables a document declares, by type name.
Iterable<String> _variableTypes(String document) => gql(document).definitions
    .whereType<OperationDefinitionNode>()
    .expand((op) => op.variableDefinitions)
    .map((v) {
      var type = v.type;
      while (type is ListTypeNode) {
        type = type.type;
      }
      return (type as NamedTypeNode).name.value;
    });

final _photo = ReturnPhoto(
  name: 'photo-1-1.png',
  mimeType: 'image/png',
  bytes: kGreenPhoto,
);

void main() {
  group('reads', () {
    test('hmReturnConfig, with what files a message may carry', () async {
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
              'attachment_extensions': ['JPG', 'png', 'pdf'],
              'attachment_max_bytes': 2097152,
              'attachment_max_files': 5,
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
      expect(config.attachmentExtensions, ['jpg', 'png', 'pdf']);
      expect(config.attachmentMaxBytes, 2097152);
      expect(config.attachmentMaxFiles, 5);
      expect(config.acceptsPhotos, isTrue);
    });

    test('hmReturnableOrders, paged, with lines, prices and seller', () async {
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
      expect(line.unitPrice, const Money(amount: 43, currency: 'AED'));
      expect(line.rowTotal, const Money(amount: 86, currency: 'AED'));
      expect(line.maxRefund, const Money(amount: 43, currency: 'AED'));
    });

    test('a server without line prices leaves them unknown', () {
      final order = returnableOrderFromJson(
        _returnableOrder('000000150', prices: false),
      );
      expect(order.items.single.unitPrice, isNull);
      expect(order.items.single.maxRefund, isNull);
    });

    test('hmReturnableOrder: one order in one request', () async {
      final client = fakeHubAppClient({
        'HmReturnableOrder': {
          'hmReturnableOrder': _returnableOrder('000000150'),
        },
      });
      final order = await ReturnsRepository(
        client,
      ).fetchReturnableOrder('000000150');
      expect(order?.number, '000000150');
      expect(order?.items.single.unitPrice?.amount, 43);
      expect(client.requests, hasLength(1));
      expect(_variables(client.requests.single), {'number': '000000150'});
    });

    test('hmReturnableOrder: nothing left to return is no order', () async {
      Future<ReturnableOrder?> lookup(Object? answer) => ReturnsRepository(
        fakeHubAppClient({
          'HmReturnableOrder': <String, dynamic>{'hmReturnableOrder': answer},
        }),
      ).fetchReturnableOrder('000000150');

      expect(await lookup(null), isNull);
      expect(
        await lookup(_returnableOrder('000000150', returnable: 0)),
        isNull,
      );
    });

    test('hmReturns rows: status code, refund and first line', () async {
      final page = await ReturnsRepository(
        fakeHubAppClient({
          'HmReturns': {
            'hmReturns': {
              '__typename': 'HmReturnPage',
              'total_count': 2,
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
                  'status_code': 'canceled',
                  'status_label': 'Canceled',
                  'type': 'REFUND',
                  'item_count': 2,
                  'seller': _seller('Hub Market'),
                  'has_unread_reply': true,
                  'refund_amount': _money(29),
                  'first_item': {
                    '__typename': 'HmReturnSummaryItem',
                    'name': 'Joust Duffle Bag',
                    'thumbnail': 'http://hub-market.magento2.click/media/b.jpg',
                  },
                },
                {
                  '__typename': 'HmReturnSummary',
                  'id': 27,
                  'number': 'R-000027',
                  'order_number': '000000148',
                  'created_at': '2026-09-09T09:00:00Z',
                  'updated_at': '2026-09-10T09:00:00Z',
                  'state': 'CLOSED',
                  'status_code': 'resolved',
                  'status_label': 'Resolved',
                  'type': 'REPLACE',
                  'item_count': 1,
                  'seller': null,
                  'has_unread_reply': false,
                  'refund_amount': null,
                  'first_item': null,
                },
              ],
            },
          },
        }),
      ).fetchReturns();
      final row = page.items.first;
      expect(row.id, 31);
      expect(row.state, ReturnState.canceled);
      expect(row.statusCode, 'canceled');
      expect(row.tone, ReturnTone.rejected);
      expect(row.type, ReturnType.refund);
      expect(row.itemCount, 2);
      expect(row.hasUnreadReply, isTrue);
      expect(row.seller?.isMarketplace, isTrue);
      expect(row.refundAmount, const Money(amount: 29, currency: 'AED'));
      expect(row.firstItem?.name, 'Joust Duffle Bag');
      expect(row.firstItem?.thumbnail, startsWith('https://'));

      final resolved = page.items.last;
      expect(resolved.tone, ReturnTone.resolved);
      expect(resolved.firstItem, isNull);
      expect(resolved.refundAmount, isNull);
      // Opening it on the server reads it; the row keeps everything else.
      expect(row.markedRead().hasUnreadReply, isFalse);
      expect(row.markedRead().firstItem?.name, 'Joust Duffle Bag');
      expect(row.markedRead().statusCode, 'canceled');
    });

    test(
      'hmReturn: lines, history, the thread with its files; null when not '
      'theirs',
      () async {
        final client = fakeHubAppClient({
          'HmReturn': {'hmReturn': _rma()},
        });
        final detail = (await ReturnsRepository(client).fetchReturn(31))!;
        expect(_variables(client.requests.single), {'id': 31});
        expect(detail.type, ReturnType.replace);
        expect(detail.reasonText, 'Too small');
        expect(detail.trackingCode, 'ARX-1');
        expect(detail.items.single.quantity, 1);
        expect(detail.history.single.changedBy, ReturnActor.customer);
        expect(detail.messages.map((m) => m.author), [
          ReturnActor.customer,
          ReturnActor.hubMarket,
        ]);
        expect(detail.messages.last.authorName, 'Hub Market');
        final files = detail.messages.first.attachments;
        expect(files.map((f) => f.name), ['1_ab12cd34ef.jpg', 'receipt.pdf']);
        expect(files.first.url, startsWith('https://'));
        expect(files.map((f) => f.isImage), [true, false]);
        expect(detail.escalation, isNull);

        final none = await ReturnsRepository(
          fakeHubAppClient({
            'HmReturn': {'hmReturn': null},
          }),
        ).fetchReturn(99);
        expect(none, isNull);
      },
    );

    test('what the customer may do is the server’s word', () {
      final open = returnDetailFromJson(_rma());
      expect(open.canReply, isTrue);
      expect(open.canCancel, isTrue);
      expect(open.canEscalate, isTrue);

      // Escalated: still open for replies, no second escalation, no cancel.
      final escalated = returnDetailFromJson(
        _rma(
          statusCode: 'awaiting',
          canCancel: false,
          canEscalate: false,
          escalation: {
            '__typename': 'HmReturnEscalation',
            'body_text': 'The seller stopped answering.',
            'attachments': [_attachment('crack_1.png')],
            'created_at': '2026-09-29T08:00:00Z',
          },
        ),
      );
      expect(escalated.canReply, isTrue);
      expect(escalated.canCancel, isFalse);
      expect(escalated.canEscalate, isFalse);
      expect(escalated.escalation?.bodyText, 'The seller stopped answering.');
      expect(escalated.escalation?.attachments.single.isImage, isTrue);

      // A state the app would have guessed open takes no reply when the
      // server says so.
      expect(
        returnDetailFromJson(_rma(canReply: false)).canReply,
        isFalse,
      );
      expect(
        returnDetailFromJson(_rma(state: 'CLOSED', canReply: false)).canReply,
        isFalse,
      );
    });

    test('files from a server without attachments: its URLs', () {
      final json = _rma();
      (json['messages'] as List).first
        ..remove('attachments')
        ..['attachment_urls'] = [
          'http://hub-market.magento2.click/media/rma/request/a%20b.jpg',
        ];
      final file = returnDetailFromJson(json).messages.first.attachments.single;
      expect(file.name, 'a b.jpg');
      expect(file.url, startsWith('https://'));
    });

    test('the core order’s prices, for a server without unit prices', () async {
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
        'attachments': [_photo.toInput()],
      };
      final created = await ReturnsRepository(client).createReturn(input);
      expect(created.id, 31);
      expect(_variables(client.requests.single), {'input': input});
    });

    test('a reply without photos sends scalar variables only', () async {
      final client = fakeHubAppClient({
        'HmAddReturnMessage': {
          'hmAddReturnMessage': {'__typename': 'HmReturnOutput', 'rma': _rma()},
        },
      });
      await ReturnsRepository(client).addMessage(31, 'Any news?');
      expect(operationNameOf(client.requests.single), 'HmAddReturnMessage');
      expect(_variables(client.requests.single), {
        'returnId': 31,
        'message': 'Any news?',
      });
    });

    test('a reply with photos sends them as attachments', () async {
      final client = fakeHubAppClient({
        'HmAddReturnMessageWithPhotos': {
          'hmAddReturnMessage': {'__typename': 'HmReturnOutput', 'rma': _rma()},
        },
      });
      await ReturnsRepository(
        client,
      ).addMessage(31, 'Here it is', photos: [_photo]);
      expect(_variables(client.requests.single), {
        'returnId': 31,
        'message': 'Here it is',
        'attachments': [
          {
            'name': 'photo-1-1.png',
            'mime_type': 'image/png',
            'content_base64': base64Encode(kGreenPhoto),
          },
        ],
      });
    });

    test('hmEscalateReturn, with and without photos', () async {
      final client = fakeHubAppClient({
        'HmEscalateReturn': {
          'hmEscalateReturn': {
            '__typename': 'HmReturnOutput',
            'rma': _rma(statusCode: 'awaiting', canEscalate: false),
          },
        },
        'HmEscalateReturnWithPhotos': {
          'hmEscalateReturn': {
            '__typename': 'HmReturnOutput',
            'rma': _rma(statusCode: 'awaiting', canEscalate: false),
          },
        },
      });
      final repo = ReturnsRepository(client);
      final escalated = await repo.escalate(31, 'No answer from the store.');
      expect(escalated.canEscalate, isFalse);
      expect(_variables(client.requests.first), {
        'returnId': 31,
        'message': 'No answer from the store.',
      });

      await repo.escalate(31, 'See the photo.', photos: [_photo]);
      expect(
        operationNameOf(client.requests.last),
        'HmEscalateReturnWithPhotos',
      );
      expect(
        (_variables(client.requests.last)['attachments'] as List).single,
        _photo.toInput(),
      );
    });

    test('hmCancelReturn', () async {
      final client = fakeHubAppClient({
        'HmCancelReturn': {
          'hmCancelReturn': {
            '__typename': 'HmReturnOutput',
            'rma': _rma(
              state: 'CANCELED',
              statusCode: 'canceled',
              canReply: false,
              canCancel: false,
              canEscalate: false,
            ),
          },
        },
      });
      final cancelled = await ReturnsRepository(client).cancel(31);
      expect(_variables(client.requests.single), {'returnId': 31});
      expect(cancelled.state, ReturnState.canceled);
      expect(cancelled.tone, ReturnTone.rejected);
      expect(cancelled.canCancel, isFalse);
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
          'HmCancelReturn': Response(
            errors: const [
              GraphQLError(message: 'This return can\'t be cancelled any more.'),
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
      await expectLater(
        repo.cancel(31),
        throwsA(
          isA<Failure>().having(
            (f) => f.detail,
            'detail',
            contains('cancelled any more'),
          ),
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

    test('so does a mutation it doesn’t know', () async {
      var missing = 0;
      final repo = ReturnsRepository(
        fakeHubAppClient({
          'HmCancelReturn': hubAppMissingResponse(
            'hmCancelReturn',
            type: 'Mutation',
          ),
        }),
        onModuleMissing: () => missing++,
      );
      await expectLater(repo.cancel(31), throwsA(isA<HubAppMissing>()));
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

    test('Hm* variables only after a query of the module answered', () {
      // First contact (the lists, the order page's lookup, a return's page)
      // and the plain writes declare scalar variables only.
      final scalar = {
        'config': ReturnsQueries.config,
        'returnableOrders': ReturnsQueries.returnableOrders,
        'returnableOrder': ReturnsQueries.returnableOrder,
        'returns': ReturnsQueries.returns,
        'returnDetail': ReturnsQueries.returnDetail,
        'addMessage': ReturnsQueries.addMessage,
        'escalate': ReturnsQueries.escalate,
        'cancel': ReturnsQueries.cancel,
        'orderLinePrices': ReturnsQueries.orderLinePrices,
      };
      for (final entry in scalar.entries) {
        expect(
          _variableTypes(entry.value).where((t) => t.startsWith('Hm')),
          isEmpty,
          reason: entry.key,
        );
      }
      // Sent only from the form (after hmReturnConfig) or a return's page
      // (after hmReturn).
      expect(_variableTypes(ReturnsQueries.createReturn), [
        'HmCreateReturnInput',
      ]);
      expect(
        _variableTypes(ReturnsQueries.addMessageWithPhotos),
        contains('HmReturnAttachmentInput'),
      );
      expect(
        _variableTypes(ReturnsQueries.escalateWithPhotos),
        contains('HmReturnAttachmentInput'),
      );
    });
  });
}

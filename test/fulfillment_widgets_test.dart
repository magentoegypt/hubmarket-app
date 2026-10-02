import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hubmarket_app/core/address/fulfillment_preview.dart';
import 'package:hubmarket_app/core/address/fulfillment_order.dart';

void main() {
  for (final locale in ['en', 'ar']) {
    testWidgets(
      'Delivery offers and order progress render at phone width: $locale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              fulfillmentOffersProvider.overrideWith(
                (ref) async => const [
                  FulfillmentOffer('direct', 'proposed', 'AED', 3000, 3),
                  FulfillmentOffer('hub', 'proposed', 'AED', 2400, 1),
                ],
              ),
              fulfillmentOrderProvider('QA-001').overrideWith(
                (ref) async => {
                  'status': 'ordered',
                  'groups': [
                    {
                      'leg': 'inbound',
                      'state': 'received',
                      'items': [
                        {'sku': 'QA-A', 'qty_milli': 1000},
                      ],
                    },
                    {
                      'leg': 'outbound',
                      'state': 'planned',
                      'items': [
                        {'sku': 'QA-A', 'qty_milli': 1000},
                      ],
                    },
                  ],
                },
              ),
            ],
            child: MaterialApp(
              locale: Locale(locale),
              supportedLocales: const [Locale('en'), Locale('ar')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      FulfillmentPreviewCard(),
                      FulfillmentOrderCard(number: 'QA-001'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            locale == 'en' ? 'Delivery options' : 'وسائل التوصيل المتاحة',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            locale == 'en' ? 'Received at hub' : 'تم الاستلام في مركز التجميع',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Disabled fulfillment remains hidden on older backends', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fulfillmentOffersProvider.overrideWith(
            (ref) async => const [
              FulfillmentOffer('direct', 'disabled', '', null, 0),
            ],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FulfillmentPreviewCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
  });
}

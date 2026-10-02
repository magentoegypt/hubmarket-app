import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../storage/secure_token_store.dart';
import '../store/store_controller.dart';

final fulfillmentOrderProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, number) async {
      final token = await ref.watch(secureTokenStoreProvider).read();
      if (token == null) return null;
      final config = ref.watch(appConfigProvider);
      final store = ref.watch(storeControllerProvider).activeStoreCode;
      final client = http.Client();
      ref.onDispose(client.close);
      final uri = Uri.parse(config.graphqlEndpoint).replace(
        path:
            '/rest/$store/V1/hubfulfillment/order-number/${Uri.encodeComponent(number)}',
        query: null,
      );
      final response = await client
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'User-Agent': config.userAgent,
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw const FormatException('Could not load delivery progress.');
      }
      var data = jsonDecode(response.body);
      if (data is String) data = jsonDecode(data);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid delivery progress.');
      }
      return data['status'] == 'ordered' ? data : null;
    });

class FulfillmentOrderCard extends ConsumerWidget {
  const FulfillmentOrderCard({super.key, required this.number});
  final String number;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    String t(String en, String arabic) => ar ? arabic : en;
    String state(String value) => switch (value) {
      'planned' => t('Preparing', 'قيد التجهيز'),
      'dispatched' => t('Dispatched', 'تم الشحن'),
      'received' => t('Received at hub', 'تم الاستلام في مركز التجميع'),
      'delivered' => t('Delivered', 'تم التوصيل'),
      _ => t('Awaiting update', 'بانتظار التحديث'),
    };
    return ref
        .watch(fulfillmentOrderProvider(number))
        .when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => TextButton(
            onPressed: () => ref.invalidate(fulfillmentOrderProvider(number)),
            child: Text(
              t('Retry delivery progress', 'إعادة تحميل حالة التوصيل'),
            ),
          ),
          data: (plan) => plan == null
              ? const SizedBox.shrink()
              : Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('Delivery progress', 'حالة التوصيل'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        for (final group in plan['groups'] as List)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              group['leg'] == 'inbound'
                                  ? t(
                                      'To consolidation hub',
                                      'إلى مركز التجميع',
                                    )
                                  : t('To your address', 'إلى عنوانك'),
                            ),
                            subtitle: Text(
                              (group['items'] as List)
                                  .map(
                                    (i) =>
                                        '${i['sku']} × ${(i['qty_milli'] as num) / 1000}',
                                  )
                                  .join(', '),
                            ),
                            trailing: Text(state(group['state'] as String)),
                          ),
                      ],
                    ),
                  ),
                ),
        );
  }
}

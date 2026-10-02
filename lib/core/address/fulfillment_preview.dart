import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../features/cart/presentation/cart_controller.dart';
import '../../features/catalog/domain/money.dart';
import 'city_fields.dart';
import 'city_manager.dart';
import 'delivery_location.dart';

class FulfillmentOffer {
  const FulfillmentOffer(
    this.strategy,
    this.status,
    this.currency,
    this.minor,
    this.groups,
  );
  final String strategy, status, currency;
  final int? minor;
  final int groups;
  factory FulfillmentOffer.fromJson(
    String strategy,
    Map<String, dynamic> json,
  ) {
    final status = json['status'];
    if (!const [
      'disabled',
      'unavailable',
      'unsupported_product_type',
      'proposed',
    ].contains(status)) {
      throw const FormatException('Invalid fulfillment status');
    }
    if (status != 'proposed') {
      return FulfillmentOffer(strategy, status as String, '', null, 0);
    }
    final fee = json['shipping_minor'];
    final currency = json['currency'];
    final groups = json['groups'];
    if (fee is! int ||
        fee < 0 ||
        currency is! String ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        groups is! List) {
      throw const FormatException('Invalid shipping offer');
    }
    return FulfillmentOffer(
      strategy,
      'proposed',
      currency,
      fee,
      groups.where((g) => g is Map && g['leg'] != 'inbound').length,
    );
  }
}

class FulfillmentService {
  FulfillmentService(this.baseUrl, this.client);
  final String baseUrl;
  final http.Client client;
  Future<FulfillmentOffer> quote(
    CitySelection location,
    List<Map<String, dynamic>> items,
    String strategy,
  ) async {
    final uri = Uri.parse(baseUrl)
        .resolve('/hubfulfillment/quote/index')
        .replace(
          queryParameters: {
            'country': location.country,
            'region': '${location.regionId ?? 0}',
            'city': '${location.city!.id}',
            'locality': '${location.locality?.id ?? 0}',
            'items': jsonEncode(items),
            'strategy': strategy,
          },
        );
    final response = await client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode == 404) {
      return FulfillmentOffer(strategy, 'disabled', '', null, 0);
    }
    if (response.statusCode != 200) {
      throw const FormatException('Delivery options unavailable');
    }
    return FulfillmentOffer.fromJson(
      strategy,
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}

final fulfillmentServiceProvider = Provider<FulfillmentService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return FulfillmentService(ref.watch(cityDirectoryProvider).baseUrl, client);
});
final fulfillmentOffersProvider =
    FutureProvider.autoDispose<List<FulfillmentOffer>>((ref) async {
      final location = ref.watch(deliveryLocationProvider);
      final items = ref.watch(cartControllerProvider).cart.items;
      if (location == null || !location.valid || items.isEmpty) return [];
      final service = ref.watch(fulfillmentServiceProvider);
      final lines = items
          .map(
            (i) => <String, dynamic>{
              'sku': i.sku,
              'qty_milli': i.quantity * 1000,
            },
          )
          .toList();
      return Future.wait(
        ['direct', 'hub'].map((s) => service.quote(location, lines, s)),
      );
    });

class FulfillmentPreviewCard extends ConsumerWidget {
  const FulfillmentPreviewCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return ref
        .watch(fulfillmentOffersProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => ListTile(
            title: Text(
              ar
                  ? 'تعذر تحميل وسائل التوصيل'
                  : 'Could not load delivery options',
            ),
            trailing: IconButton(
              tooltip: ar ? 'إعادة المحاولة' : 'Retry',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(fulfillmentOffersProvider),
            ),
          ),
          data: (offers) {
            final enabled = offers
                .where((o) => o.status != 'disabled')
                .toList();
            if (enabled.isEmpty) return const SizedBox.shrink();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ar ? 'وسائل التوصيل المتاحة' : 'Delivery options',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final offer in enabled)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          offer.strategy == 'hub'
                              ? (ar
                                    ? 'توصيل مجمّع عبر المركز'
                                    : 'Consolidated hub delivery')
                              : (ar ? 'توصيل مباشر' : 'Direct delivery'),
                        ),
                        subtitle: Text(
                          offer.status == 'proposed'
                              ? (ar
                                    ? '${offer.groups} شحنة إلى عنوانك'
                                    : '${offer.groups} shipment(s) to your address')
                              : offer.status == 'unsupported_product_type'
                              ? (ar
                                    ? 'تحقق من وسائل التوصيل عند إتمام الطلب'
                                    : 'Check delivery options at checkout')
                              : (ar
                                    ? 'غير متاح لهذه السلة والمنطقة'
                                    : 'Unavailable for this cart and area'),
                        ),
                        trailing: offer.minor == null
                            ? null
                            : Text(
                                Money(
                                  amount: offer.minor! / 100,
                                  currency: offer.currency,
                                ).formatted(),
                              ),
                      ),
                    Text(
                      ar
                          ? 'الرسوم تقديرية قبل الضرائب. اختر الوسيلة وأكد عنوان التوصيل عند إتمام الطلب.'
                          : 'Estimated fees before tax. Choose a method and confirm the delivery address at checkout.',
                    ),
                  ],
                ),
              ),
            );
          },
        );
  }
}

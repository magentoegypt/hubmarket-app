import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hubmarket_app/core/address/city_manager.dart';
import 'package:hubmarket_app/core/address/fulfillment_preview.dart';

void main() {
  const location = CitySelection(country: 'EG', regionId: 7, city: CityLocation(104, 7, 'Giza', 'الجيزة'));
  final offer = {'status': 'proposed', 'currency': 'EGP', 'shipping_minor': 2400, 'groups': [
    {'leg': 'inbound'}, {'leg': 'inbound'}, {'leg': 'inbound'}, {'leg': 'outbound'},
  ]};
  test('Hub preview counts last-mile shipments, not inbound legs', () {
    final parsed = FulfillmentOffer.fromJson('hub', offer);
    expect(parsed.groups, 1); expect(parsed.minor, 2400);
  });
  test('Unavailable offer has no invented fee', () {
    final parsed = FulfillmentOffer.fromJson('direct', {'status': 'unavailable'});
    expect(parsed.minor, isNull);
  });
  test('Malformed money and unknown status are rejected', () {
    expect(() => FulfillmentOffer.fromJson('hub', {...offer, 'shipping_minor': -1}), throwsFormatException);
    expect(() => FulfillmentOffer.fromJson('hub', {...offer, 'shipping_minor': 1.5}), throwsFormatException);
    expect(() => FulfillmentOffer.fromJson('hub', {'status': 'success'}), throwsFormatException);
  });
  test('Request includes destination and current quantities without customer identity', () async {
    final service = FulfillmentService('https://example.invalid/graphql', MockClient((r) async {
      expect(r.method, 'GET'); expect(r.headers.containsKey('Authorization'), false);
      expect(r.url.queryParameters['city'], '104');
      expect(jsonDecode(r.url.queryParameters['items']!).single['qty_milli'], 2000);
      return http.Response(jsonEncode(offer), 200);
    }));
    expect((await service.quote(location, [{'sku': 'A', 'qty_milli': 2000}], 'hub')).minor, 2400);
  });
  test('Older backend hides unavailable module instead of showing zero delivery', () async {
    final service = FulfillmentService('https://example.invalid', MockClient((r) async => http.Response('', 404)));
    expect((await service.quote(location, [{'sku': 'A', 'qty_milli': 1000}], 'direct')).status, 'disabled');
  });
  test('Service failure remains retryable rather than available', () async {
    final service = FulfillmentService('https://example.invalid', MockClient((r) async => http.Response('', 503)));
    await expectLater(service.quote(location, [{'sku': 'A', 'qty_milli': 1000}], 'direct'), throwsFormatException);
  });
}

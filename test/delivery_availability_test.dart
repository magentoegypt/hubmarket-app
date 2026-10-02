import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/customer_address.dart';
import 'package:hubmarket_app/core/address/city_fields.dart';
import 'support/fakes.dart';
import 'support/city_fake.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hubmarket_app/core/address/city_manager.dart';
import 'package:hubmarket_app/core/address/delivery_location.dart';

class TestAuth extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.guest);
  void change(AuthStatus status) => state = AuthState(status: status);
}

class DeliveryAccount extends FakeAccountRepository {
  @override
  Future<List<CustomerAddress>> fetchAddresses() async => const [
    CustomerAddress(
      firstName: 'Test',
      lastName: 'Shopper',
      telephone: '',
      street: '',
      city: 'Dubai / Dubai Marina',
      countryCode: 'AE',
      defaultShipping: true,
    ),
  ];
}

void main() {
  const location = CitySelection(
    country: 'EG',
    regionId: 10,
    city: CityLocation(12, 10, 'Cairo', 'القاهرة'),
  );
  test('guest selection survives login and logout; browse all clears it', () {
    final container = ProviderContainer(
      overrides: [authControllerProvider.overrideWith(TestAuth.new)],
    );
    addTearDown(container.dispose);
    final controller = container.read(deliveryLocationProvider.notifier);
    expect(container.read(deliveryLocationProvider), isNull);
    controller.select(location);
    final auth = container.read(authControllerProvider.notifier) as TestAuth;
    auth.change(AuthStatus.authenticated);
    expect(container.read(deliveryLocationProvider), location);
    auth.change(AuthStatus.guest);
    expect(container.read(deliveryLocationProvider), location);
    controller.clear();
    expect(container.read(deliveryLocationProvider), isNull);
  });
  test(
    'login defaults to saved area and logout clears account-derived area',
    () async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(TestAuth.new),
          accountRepositoryProvider.overrideWithValue(DeliveryAccount()),
          cityDirectoryProvider.overrideWithValue(FakeCityDirectory()),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(deliveryLocationProvider), isNull);
      final auth = container.read(authControllerProvider.notifier) as TestAuth;
      auth.change(AuthStatus.authenticated);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(deliveryLocationProvider)?.city?.id, 2);
      expect(container.read(deliveryLocationProvider)?.locality?.id, 3);
      auth.change(AuthStatus.guest);
      expect(container.read(deliveryLocationProvider), isNull);
    },
  );
  test('passes destination IDs and exact SKU to server', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['city'], '12');
      expect(request.url.queryParameters['sku'], 'A&B');
      expect(request.url.path, '/deliveryavailability/check/index');
      return http.Response('{"coverage":"blacklist"}', 200);
    });
    final service = DeliveryService(
      CityDirectory('https://example.test/graphql', client),
      client,
    );
    expect((await service.check(location, 'A&B')).blocked, isTrue);
  });
  test('service errors are never reported as deliverable', () async {
    final client = MockClient((_) async => http.Response('unavailable', 503));
    final service = DeliveryService(
      CityDirectory('https://example.test', client),
      client,
    );
    await expectLater(service.check(location, 'A'), throwsFormatException);
  });
  test('unknown API states are not accepted as coverage', () async {
    final client = MockClient(
      (_) async => http.Response('{"coverage":"available"}', 200),
    );
    final service = DeliveryService(
      CityDirectory('https://example.test', client),
      client,
    );
    await expectLater(service.check(location, 'A'), throwsFormatException);
  });
  test('red requires quotation, green is coverage only', () {
    expect(const DeliveryCheck('red').blocked, isTrue);
    expect(const DeliveryCheck('green').blocked, isFalse);
    expect(deliveryMessage('green', false), contains('checkout'));
    expect(deliveryMessage('blacklist', true), contains('غير متاح'));
  });
}

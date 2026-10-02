import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hubmarket_app/core/address/city_manager.dart';

class FakeCityDirectory extends CityDirectory {
  FakeCityDirectory() : super('https://example.invalid', http.Client());
  @override
  Future<List<CityLocation>> fetch(String country, String level, {int? region, int? parent}) async =>
    level == 'locality' ? const [CityLocation(3, 200, 'Dubai Marina', 'دبي مارينا')]
    : level == 'region' ? const [CityLocation(1, 100, 'Cairo', 'القاهرة')]
    : country == 'AE' ? const [CityLocation(2, 200, 'Dubai', 'دبي')]
    : const [CityLocation(4, 100, 'New Cairo', 'القاهرة الجديدة')];
}

Future<void> chooseDubai(WidgetTester tester, {bool? arabic}) async {
  arabic ??= tester.widget<CityManagerFields>(find.byType(CityManagerFields)).arabic;
  final fields = find.byType(DropdownButtonFormField<int>);
  await tester.ensureVisible(fields.first);
  await tester.tap(fields.first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(arabic ? 'دبي' : 'Dubai').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(fields.last);
  await tester.tap(fields.last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(arabic ? 'دبي مارينا' : 'Dubai Marina').last);
  await tester.pumpAndSettle();
}

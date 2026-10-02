import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hubmarket_app/core/address/city_manager.dart';

Map<String, dynamic> row(int id, int region, String name) => {
  'location_id': '$id', 'region_id': '$region', 'name_en': name, 'name_ar': '',
};
void main() {
  final requests = <Uri>[];
  CityDirectory directory({bool error = false, bool emptyLocalities = false}) => CityDirectory('https://example.invalid/graphql', MockClient((request) async {
    requests.add(request.url);
    if (error) return http.Response('unavailable', 503);
    final q = request.url.queryParameters;
    final items = q['level'] == 'region' ? [row(1, 100, 'Cairo')]
      : q['level'] == 'locality' ? (emptyLocalities ? [] : [row(3, 200, 'Downtown')])
      : q['country'] == 'AE' ? [row(2, 200, 'Dubai')] : [row(4, 100, 'New Cairo')];
    return http.Response(jsonEncode({'items': items}), 200);
  }));
  test('Directory uses public read endpoint and parent filters', () async {
    final rows = await directory().fetch('AE', 'locality', parent: 2);
    expect(rows.single.id, 3);
    expect(requests.last.path, '/citymanager/directory/index');
    expect(requests.last.queryParameters['parent'], '2');
  });
  test('Directory errors are surfaced', () async {
    await expectLater(directory(error: true).fetch('EG', 'city'), throwsFormatException);
  });
  testWidgets('UAE restores city and locality without Emirate picker', (tester) async {
    CitySelection? value;
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: form, child: CityManagerFields(
      directory: directory(), initialCity: 'Dubai — Downtown', onChanged: (v) => value = v,
    )))));
    await tester.pumpAndSettle();
    expect(value?.valid, true);
    expect(value?.addressCity, 'Dubai — Downtown');
    expect(value?.regionId, 200);
    expect(find.text('Emirate'), findsNothing);
    expect(form.currentState!.validate(), true);
  });
  for (final entry in {'EG':'Governorate','SA':'Region','US':'State'}.entries) {
    testWidgets('${entry.key} restores parent and city', (tester) async {
      CitySelection? value;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(child: CityManagerFields(
        directory: directory(), initialCountry: entry.key, initialRegionId: 100,
        initialCity: 'New Cairo', onChanged: (v) => value = v,
      )))));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('Locality'), findsNothing);
      expect(value?.valid, true);
      expect(value?.country, entry.key);
    });
  }
  testWidgets('Changing country clears saved child locations', (tester) async {
    CitySelection? value;
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: form, child: CityManagerFields(
      directory: directory(), initialCity: 'Dubai — Downtown', onChanged: (v) => value = v,
    )))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cm-country-AE')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Egypt').last);
    await tester.pumpAndSettle();
    expect(value?.country, 'EG');
    expect(value?.city, isNull);
    expect(value?.locality, isNull);
    expect(form.currentState!.validate(), false);
  });
  testWidgets('Unavailable service blocks form submission', (tester) async {
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: form, child: CityManagerFields(
      directory: directory(error: true), onChanged: (_) {},
    )))));
    await tester.pumpAndSettle();
    expect(form.currentState!.validate(), false);
    expect(find.text('Locations could not load. Retry'), findsOneWidget);
  });
  testWidgets('UAE locality is optional only when none are configured', (tester) async {
    CitySelection? value;
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: form, child: CityManagerFields(
      directory: directory(emptyLocalities: true), initialCity: 'Dubai', onChanged: (v) => value = v,
    )))));
    await tester.pumpAndSettle();
    expect(form.currentState!.validate(), true);
    expect(value?.valid, true);
    expect(value?.addressCity, 'Dubai');
  });
  testWidgets('UAE locality remains mandatory when configured', (tester) async {
    CitySelection? value;
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: form, child: CityManagerFields(
      directory: directory(), initialCity: 'Dubai', onChanged: (v) => value = v,
    )))));
    await tester.pumpAndSettle();
    expect(form.currentState!.validate(), false);
    expect(value?.valid, false);
  });

}

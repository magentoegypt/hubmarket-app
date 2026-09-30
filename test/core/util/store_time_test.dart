import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/util/store_time.dart';

void main() {
  group('storeStampToLocal', () {
    test(
      'reads a naive Magento stamp as store wall-clock, not device-local',
      () {
        // QA's Sep 16 report: the order was placed at 12:46 on a Cairo phone
        // (UTC+3) and Magento returned "13:46" — Dubai wall-clock. Anchored to
        // the store zone that is 09:46Z, the instant the shopper actually
        // ordered, whatever zone the device renders it in.
        final dt = storeStampToLocal('2026-09-16 13:46:00', 'Asia/Dubai');
        expect(dt, isNotNull);
        expect(dt!.toUtc(), DateTime.utc(2026, 9, 16, 9, 46));
      },
    );

    test('is shown on the device clock, not in the tz package UTC', () {
      // TZDateTime.toLocal() lands in the package's `local`, UTC unless
      // setLocalLocation is called, so a Dubai order at 13:46 read "09:46".
      // The result must be a plain DateTime in the device's own zone.
      final dt = storeStampToLocal('2026-09-16 13:46:00', 'Asia/Dubai')!;
      expect(dt.runtimeType.toString(), isNot(contains('TZDateTime')));
      expect(dt.isUtc, isFalse);
      final onDeviceClock = DateTime.fromMillisecondsSinceEpoch(
        dt.millisecondsSinceEpoch,
      );
      expect(dt.hour, onDeviceClock.hour);
      expect(dt.timeZoneOffset, onDeviceClock.timeZoneOffset);
    });

    test('same instant whatever the store zone spells it as', () {
      expect(
        storeStampToLocal('2026-09-16 13:46:00', 'Asia/Dubai')!.toUtc(),
        storeStampToLocal('2026-09-16 12:46:00', 'Africa/Cairo')!.toUtc(),
      );
    });

    test('keeps a stamp that already carries an offset', () {
      expect(
        storeStampToLocal('2026-09-16T09:46:00Z', 'Asia/Dubai')!.toUtc(),
        DateTime.utc(2026, 9, 16, 9, 46),
      );
      expect(
        storeStampToLocal('2026-09-16T13:46:00+04:00', 'Asia/Dubai')!.toUtc(),
        DateTime.utc(2026, 9, 16, 9, 46),
      );
    });

    test('falls back to the previous device-local reading without a zone', () {
      // No zone to anchor to: read as before rather than shift by a guess.
      final expected = DateTime(2026, 9, 16, 13, 46);
      expect(storeStampToLocal('2026-09-16 13:46:00', ''), expected);
      expect(storeStampToLocal('2026-09-16 13:46:00', 'Not/AZone'), expected);
    });

    test('returns null for an empty or unparseable stamp', () {
      expect(storeStampToLocal('', 'Asia/Dubai'), isNull);
      expect(storeStampToLocal('not a date', 'Asia/Dubai'), isNull);
    });
  });
}

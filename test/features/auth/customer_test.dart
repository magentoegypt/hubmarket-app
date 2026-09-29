import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/auth/domain/customer.dart';

void main() {
  group('Customer.fromJson mobile_number', () {
    test('extracts mobile_number from custom_attributes', () {
      final c = Customer.fromJson(const {
        'firstname': 'Sara',
        'lastname': 'Ali',
        'email': 'sara@example.com',
        'custom_attributes': [
          {'code': 'some_other', 'value': 'x'},
          {'code': 'mobile_number', 'value': '+971501234567'},
        ],
      });
      expect(c.mobileNumber, '+971501234567');
    });

    test('is null when the attribute is absent', () {
      final c = Customer.fromJson(const {
        'firstname': 'Sara',
        'lastname': 'Ali',
        'email': 'sara@example.com',
        'custom_attributes': [
          {'code': 'some_other', 'value': 'x'},
        ],
      });
      expect(c.mobileNumber, isNull);
    });

    test('is null when custom_attributes is missing or empty value', () {
      expect(
        Customer.fromJson(const {
          'firstname': 'Sara',
          'lastname': 'Ali',
          'email': 'sara@example.com',
        }).mobileNumber,
        isNull,
      );
      expect(
        Customer.fromJson(const {
          'firstname': 'Sara',
          'lastname': 'Ali',
          'email': 'sara@example.com',
          'custom_attributes': [
            {'code': 'mobile_number', 'value': ''},
          ],
        }).mobileNumber,
        isNull,
      );
    });
  });
}

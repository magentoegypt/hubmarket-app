import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/auth/domain/customer.dart';

void main() {
  group('Customer.fromJson mobilenumber', () {
    test('reads the Vnecoms `mobilenumber` field', () {
      final c = Customer.fromJson(const {
        'firstname': 'Sara',
        'lastname': 'Ali',
        'email': 'sara@example.com',
        'mobilenumber': '+971501234567',
      });
      expect(c.mobileNumber, '+971501234567');
    });

    test('is null when missing or blank', () {
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
          'mobilenumber': '  ',
        }).mobileNumber,
        isNull,
      );
    });

    test('has no avatar — the backend serves none', () {
      final c = Customer.fromJson(const {
        'firstname': 'Sara',
        'lastname': 'Ali',
        'email': 'sara@example.com',
        // A stray field from another backend must not light up a photo.
        'avatar_url': 'https://example.com/a.jpg',
      });
      expect(c.avatarUrl, isNull);
    });
  });
}

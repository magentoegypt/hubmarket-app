/// The signed-in customer's profile basics.
class Customer {
  const Customer({
    required this.firstName,
    required this.lastName,
    required this.email,
    this.mobileNumber,
    this.avatarUrl,
  });

  final String firstName;
  final String lastName;
  final String email;

  /// The customer's mobile — `Customer.mobilenumber`, the Vnecoms SMS attribute
  /// set at registration and changed in-app through the OTP-gated Edit Profile
  /// flow (normally E.164, e.g. `+971501234567`). Null when not set.
  final String? mobileNumber;

  /// Always null on Hub Market: the backend has no customer-photo endpoint, so
  /// avatars render initials. Kept for the day the backend has one.
  final String? avatarUrl;

  String get fullName => '$firstName $lastName'.trim();

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    firstName: (json['firstname'] as String?) ?? '',
    lastName: (json['lastname'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    mobileNumber: _nonEmpty(json['mobilenumber']),
  );

  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

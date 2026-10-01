import 'package:flutter/foundation.dart';

/// What Profile details (Figma 20c) shows beyond the basics the session holds:
/// the date of birth and whether the e-mail address is confirmed — both core
/// `Customer` fields.
@immutable
class ProfileExtras {
  const ProfileExtras({this.dateOfBirth, this.emailConfirmed = false});

  /// `Customer.date_of_birth`, `YYYY-MM-DD`; null when none was given.
  final String? dateOfBirth;

  /// `confirmation_status` is `ACCOUNT_CONFIRMED`: the customer proved the
  /// address by following the store's confirmation link. A store that does not
  /// require confirmation says `ACCOUNT_CONFIRMATION_NOT_REQUIRED`, which
  /// proves nothing, so the frame's "Verified" stays out.
  final bool emailConfirmed;

  /// From a core `customer { date_of_birth confirmation_status }` answer.
  factory ProfileExtras.fromJson(Map<String, dynamic>? json) {
    final dob = json?['date_of_birth'];
    return ProfileExtras(
      dateOfBirth: dob is String && dob.trim().isNotEmpty ? dob.trim() : null,
      emailConfirmed: json?['confirmation_status'] == 'ACCOUNT_CONFIRMED',
    );
  }
}

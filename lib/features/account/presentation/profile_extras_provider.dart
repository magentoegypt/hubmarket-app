import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../data/account_repository.dart';
import '../domain/profile_extras.dart';

/// The signed-in customer's date of birth and e-mail confirmation, read once
/// when Profile details opens. Null for a guest and on any failure — the screen
/// then leaves the date empty and the "Verified" line out, and never fails over
/// them.
final profileExtrasProvider = FutureProvider.autoDispose<ProfileExtras?>((
  ref,
) async {
  if (!ref.watch(authControllerProvider).isAuthenticated) return null;
  try {
    return await ref.watch(accountRepositoryProvider).fetchProfileExtras();
  } on Object {
    return null;
  }
});

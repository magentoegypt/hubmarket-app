import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';

/// The routes of the sign-in / sign-up flow, stacked on whatever opened it.
const Set<String> _authRoutes = <String>{
  AppRoutes.signIn,
  AppRoutes.signUp,
  AppRoutes.forgotPassword,
  AppRoutes.resetPassword,
  AppRoutes.verifyCode,
};

/// Screens that open the auth flow as the start of the app rather than as a
/// detour from something the customer was doing.
const Set<String> _entryRoutes = <String>{AppRoutes.welcome, AppRoutes.splash};

/// Leaves the auth flow once the customer is signed in (by password, by code,
/// after sign-up or a password reset): every auth screen on top is closed and
/// the screen that opened the flow — checkout, account, wishlist… — is back,
/// its `push` completing with `true`. The flow that began at Welcome (or has
/// nothing under it, e.g. a reset link that opened the app) lands on Home.
void completeAuthFlow(BuildContext context) {
  final router = GoRouter.of(context);
  final matches = router.routerDelegate.currentConfiguration.matches;
  var depth = 0;
  while (depth < matches.length &&
      _authRoutes.contains(matches[matches.length - 1 - depth].matchedLocation)) {
    depth++;
  }
  final callerIndex = matches.length - 1 - depth;
  final caller = callerIndex >= 0 ? matches[callerIndex].matchedLocation : null;
  if (depth == 0 || caller == null || _entryRoutes.contains(caller)) {
    router.go(AppRoutes.home);
    return;
  }
  for (var i = 1; i < depth; i++) {
    router.pop();
  }
  router.pop(true);
}

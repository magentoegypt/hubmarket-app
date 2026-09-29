import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../error/failure.dart';

/// For flows where the backend already returns a **localized** message we want
/// to surface — the WhatsApp-OTP refusals from the Vnecoms SMS GraphQL
/// mutations and the `MagentoEgypt_SmsExtend` REST endpoints come back in the
/// store view's language ("The OTP code is not valid.", "Please wait 30
/// seconds before requesting another code.") — this returns
/// `Failure.detail` for a server failure and otherwise falls back to the
/// standard localized mapping (network/service/generic) or [fallback] for a
/// non-[Failure] error.
///
/// Contrast with [failureMessage], which deliberately hides `detail` because in
/// most flows it is raw, non-localized backend text.
String serverMessageOr(BuildContext context, Object error, String fallback) {
  if (error is Failure) {
    if (error.kind == FailureKind.server &&
        (error.detail?.trim().isNotEmpty ?? false)) {
      return error.detail!.trim();
    }
    return failureMessage(context, error);
  }
  return fallback;
}

/// Maps a [Failure] to a localized, user-friendly message.
String failureMessage(BuildContext context, Failure failure) {
  final l10n = AppLocalizations.of(context);
  switch (failure.kind) {
    case FailureKind.network:
      return l10n.errorNetwork;
    case FailureKind.service:
      return l10n.errorService;
    case FailureKind.auth:
    case FailureKind.unknown:
    case FailureKind.server:
      // `detail` holds raw, non-localized backend text — keep it for logging
      // only, never surface it to the user.
      return l10n.errorGeneric;
  }
}

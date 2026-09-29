import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../l10n/l10n.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../cart/presentation/cart_controller.dart';

/// Confirms and performs permanent account deletion.
///
/// Shared so the action can appear in more than one place. App Review
/// Guideline 5.1.1(v) is about the customer being able to *find* deletion, not
/// merely about it existing: 1.0.0 (80) was rejected as "does not include an
/// option to initiate account deletion" while the option was live but reachable
/// only through a row labelled "Language".
///
/// Returns true when the account was deleted.
Future<bool> confirmAndDeleteAccount(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.deleteAccountConfirmTitle),
      content: Text(l10n.deleteAccountConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.actionCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(l10n.deleteAccountConfirmAction),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    await ref.read(authControllerProvider.notifier).deleteAccount();
    // The account is gone, so the server-side cart went with it.
    await ref.read(cartControllerProvider.notifier).clearAfterOrder();
    if (!context.mounted) return true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.deleteAccountDone)));
    context.go(AppRoutes.home);
    return true;
  } on Object {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.deleteAccountFailed)));
    return false;
  }
}

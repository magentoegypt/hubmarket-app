import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../l10n/l10n.dart';

/// What `/stores` and `/store/…` show while the server has no seller API
/// (Hub Market App not deployed, or not confirmed yet): the app offers no way
/// in then, so only a stale link lands here — it gets "coming soon" and a way
/// Home rather than an error.
class StoresUnavailable extends StatelessWidget {
  const StoresUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.storefront_outlined,
      title: l10n.comingSoon,
      body: l10n.comingSoonBody,
      action: OutlinedButton(
        onPressed: () => context.go(AppRoutes.home),
        child: Text(l10n.navHome),
      ),
    );
  }
}

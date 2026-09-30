import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../error/failure.dart';
import '../network/connectivity.dart';
import 'failure_message.dart';
import 'offline_state.dart';

/// What a screen shows in place of content that failed to load. A request
/// that never reached the store — or any failure while the OS reports no
/// network — gets the designed offline page (Figma S3), which also retries by
/// itself once the network is back; anything else the localized failure and
/// Retry.
class LoadFailureView extends ConsumerWidget {
  const LoadFailureView({super.key, required this.error, this.onRetry});

  final Object? error;

  /// Loads the content again; without it there is no Retry.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = this.error;
    if (ref.watch(isOfflineProvider) || isNetworkFailure(error)) {
      return OfflineState(onRetry: onRetry);
    }
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error is Failure
                  ? failureMessage(context, error)
                  : l10n.errorGeneric,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
            ],
          ],
        ),
      ),
    );
  }
}

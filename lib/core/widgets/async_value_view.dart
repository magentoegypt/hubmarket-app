import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../error/failure.dart';
import '../network/connectivity.dart';
import 'failure_message.dart';
import 'offline_state.dart';

/// Renders an [AsyncValue] with consistent loading / localized-error (+ retry) /
/// data states, so screens don't repeat the boilerplate. A request that never
/// reached the store — or any failure while the OS reports no network — shows
/// the designed offline state (Figma S3) instead of an error line.
class AsyncValueView<T> extends ConsumerWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loading,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  /// Optional loading placeholder (e.g. a shimmer skeleton). Falls back to a
  /// centered spinner when omitted.
  final Widget Function()? loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final offline = ref.watch(isOfflineProvider);
    return value.when(
      loading: loading ??
          () => const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          ),
      error: (error, _) {
        if (offline || isNetworkFailure(error)) {
          return OfflineState(onRetry: onRetry);
        }
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
                  FilledButton(
                    onPressed: onRetry,
                    child: Text(l10n.actionRetry),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      data: data,
    );
  }
}

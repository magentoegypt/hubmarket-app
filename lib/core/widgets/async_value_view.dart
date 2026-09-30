import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'load_failure_view.dart';

/// Renders an [AsyncValue] with consistent loading / localized-error (+ retry) /
/// data states, so screens don't repeat the boilerplate. A request that never
/// reached the store — or any failure while the OS reports no network — shows
/// the designed offline state (Figma S3) instead of an error line
/// ([LoadFailureView]).
class AsyncValueView<T> extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return value.when(
      loading: loading ??
          () => const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          ),
      error: (error, _) => LoadFailureView(error: error, onRetry: onRetry),
      data: data,
    );
  }
}

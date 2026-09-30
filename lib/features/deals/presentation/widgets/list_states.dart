import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/hubapp/hubapp_query.dart';
import '../../../../core/network/connectivity.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/offline_state.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/presentation/widgets/product_skeletons.dart';

/// What a Hub Market App list page shows when its load failed: offline, the
/// store's own trouble with Retry — or, when the server has no such list
/// ([HubAppMissing]), simply [emptyTitle], as an empty list would.
class HmListError extends ConsumerWidget {
  const HmListError({
    super.key,
    required this.error,
    required this.onRetry,
    required this.emptyTitle,
    this.emptyIcon = Icons.local_offer_outlined,
  });

  final Object error;
  final VoidCallback onRetry;
  final String emptyTitle;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (error is HubAppMissing) {
      return EmptyState(icon: emptyIcon, title: emptyTitle);
    }
    if (isNetworkFailure(error) || ref.watch(isOfflineProvider)) {
      return OfflineState(onRetry: onRetry);
    }
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: AppColors.inkMuted,
            ),
            const SizedBox(height: 12),
            Text(
              error is Failure
                  ? failureMessage(context, error as Failure)
                  : l10n.errorGeneric,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
          ],
        ),
      ),
    );
  }
}

/// A two-column grid of card skeletons.
class HmGridSkeleton extends StatelessWidget {
  const HmGridSkeleton({super.key, this.count = 4, this.aspectRatio = 173 / 283});

  final int count;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) => GridView.builder(
    physics: const NeverScrollableScrollPhysics(),
    shrinkWrap: true,
    padding: const EdgeInsets.all(16),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: aspectRatio,
    ),
    itemCount: count,
    itemBuilder: (_, __) => const ProductCardSkeleton(),
  );
}

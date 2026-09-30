import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/hubapp/hubapp.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../domain/returns.dart';
import '../returns_providers.dart';
import '../widgets/return_widgets.dart';

/// My returns (Figma 23b): the customer's returns, newest first, paged
/// (`hmReturns`), each with its status, and New return request.
///
/// The contract's `HmReturnSummary` carries no line names or thumbnails, so
/// a card names the order and its line count where the frame shows the
/// first product.
class MyReturnsScreen extends ConsumerStatefulWidget {
  const MyReturnsScreen({super.key});

  @override
  ConsumerState<MyReturnsScreen> createState() => _MyReturnsScreenState();
}

class _MyReturnsScreenState extends ConsumerState<MyReturnsScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      ref.read(myReturnsControllerProvider.notifier).loadMore();
    }
  }

  void _newRequest() => context.push(AppRoutes.returnRequest);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final available = ref.watch(returnsAvailableProvider);
    final signedIn = ref.watch(
      authControllerProvider.select((s) => s.isAuthenticated),
    );
    final Widget body;
    if (!available) {
      body = EmptyState(
        icon: Icons.assignment_return_outlined,
        title: l10n.returnsUnavailableTitle,
        body: l10n.returnsUnavailableBody,
      );
    } else if (!signedIn) {
      body = EmptyState(
        icon: Icons.assignment_return_outlined,
        title: l10n.returnsMyReturns,
        body: l10n.returnsSignIn,
        action: FilledButton(
          onPressed: () => context.push(AppRoutes.signIn),
          child: Text(l10n.authSignInTitle),
        ),
      );
    } else {
      body = _list(l10n, ref.watch(myReturnsControllerProvider));
    }
    return HubScaffold(
      currentTab: AppTab.account,
      appBar: subpageAppBar(context, l10n.returnsMyReturns),
      body: ColoredBox(color: groupedPageColor(context), child: body),
    );
  }

  Widget _list(AppLocalizations l10n, PagedReturnsState<ReturnSummary> state) {
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = state.error;
    if (error is HubAppMissing) {
      return EmptyState(
        icon: Icons.assignment_return_outlined,
        title: l10n.returnsUnavailableTitle,
        body: l10n.returnsUnavailableBody,
      );
    }
    if (error != null && state.items.isEmpty) {
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
              const SizedBox(height: 16),
              FilledButton(
                onPressed: ref
                    .read(myReturnsControllerProvider.notifier)
                    .refresh,
                child: Text(l10n.actionRetry),
              ),
            ],
          ),
        ),
      );
    }
    if (state.items.isEmpty) {
      return EmptyState(
        icon: Icons.assignment_return_outlined,
        title: l10n.returnsEmptyTitle,
        body: l10n.returnsEmptyBody,
        action: _NewRequestButton(onPressed: _newRequest),
      );
    }
    return RefreshIndicator(
      onRefresh: ref.read(myReturnsControllerProvider.notifier).refresh,
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          for (final item in state.items) ...[
            _ReturnCard(
              summary: item,
              onTap: () => context.push(AppRoutes.returnDetail(item.id)),
            ),
            const SizedBox(height: 12),
          ],
          if (state.isLoadingMore)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          _NewRequestButton(onPressed: _newRequest),
        ],
      ),
    );
  }
}

/// One return (Figma 65:2908): number, date and outcome, status pill, then
/// the order, its seller and whether there's an unread reply.
class _ReturnCard extends StatelessWidget {
  const _ReturnCard({required this.summary, required this.onTap});

  final ReturnSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final day = returnDay(summary.createdAt, locale);
    final caption = [
      if (day.isNotEmpty) l10n.returnsRequestedOn(day),
      returnTypeLabel(l10n, summary.type),
    ].join(' · ');
    final seller = summary.seller?.name.trim() ?? '';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.returnsTitle(returnNumberLabel(summary.number)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 22 / 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkHeading,
                          ),
                        ),
                        Text(
                          caption,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 16 / 12,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ReturnStatusPill(
                    state: summary.state,
                    label: summary.statusLabel,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const ReturnThumb(url: null),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${l10n.orderNumber(summary.orderNumber)} · '
                          '${l10n.orderItemCount(summary.itemCount)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkHeading,
                          ),
                        ),
                        if (seller.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              l10n.returnsSoldBy(seller),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 16 / 12,
                                color: returnsVendorColor,
                              ),
                            ),
                          ),
                        if (summary.hasUnreadReply)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: AppColors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  l10n.returnsNewReply,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.accentStrong,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.inkMuted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "+ New return request" (Figma 65:2943): white, navy 1.5 outline.
class _NewRequestButton extends StatelessWidget {
  const _NewRequestButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 20),
        // Styled on the Text so it keeps the theme's font (a button's
        // textStyle replaces it).
        label: Text(
          l10n.returnsNewRequest,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.brandPrimary,
          side: const BorderSide(color: AppColors.brandPrimary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

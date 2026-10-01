import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/hubapp/hubapp.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../core/widgets/load_failure_view.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../domain/returns.dart';
import '../returns_providers.dart';
import '../widgets/return_widgets.dart';
import '../../../../app/theme/hub_icons.dart';

/// My returns (Figma 23b): the customer's returns, newest first, paged
/// (`hmReturns`), each with its status — coloured by the store's status code,
/// so a resolved return and a rejected one read apart — its first product and
/// its refund, and New return request. A return the store turned down offers
/// "Not happy with the store's answer? Escalate", which opens it.
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
        icon: HubIcons.rotateCcw,
        title: l10n.returnsUnavailableTitle,
        body: l10n.returnsUnavailableBody,
      );
    } else if (!signedIn) {
      body = EmptyState(
        icon: HubIcons.rotateCcw,
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
      appBar: HubTopBar(title: l10n.returnsMyReturns, divider: true),
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
        icon: HubIcons.rotateCcw,
        title: l10n.returnsUnavailableTitle,
        body: l10n.returnsUnavailableBody,
      );
    }
    if (error != null && state.items.isEmpty) {
      // Offline: the S3 page, which reloads by itself once the network is back.
      return LoadFailureView(
        error: error,
        onRetry: ref.read(myReturnsControllerProvider.notifier).refresh,
      );
    }
    if (state.items.isEmpty) {
      return EmptyState(
        icon: HubIcons.rotateCcw,
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

/// One return (Figma 65:2908): number, date, outcome and refund, status pill,
/// then its first product with its thumbnail (the order and its line count
/// when the server has no first line), its seller and whether there's an
/// unread reply — and, when the store turned it down, the escalate banner.
class _ReturnCard extends StatelessWidget {
  const _ReturnCard({required this.summary, required this.onTap});

  final ReturnSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final day = returnDay(summary.createdAt, locale);
    final refund = summary.type == ReturnType.refund
        ? summary.refundAmount
        : null;
    final caption = [
      if (day.isNotEmpty) l10n.returnsRequestedOn(day),
      [
        returnTypeLabel(l10n, summary.type),
        // "Refund AED 29" (Figma 65:2910), the amount left to right.
        if (refund != null) '\u2066${refund.formatted()}\u2069',
      ].join(' '),
    ].join(' · ');
    final seller = summary.seller?.name.trim() ?? '';
    final first = summary.firstItem;
    final more = summary.itemCount - 1;
    return Material(
      color: groupCardColor(context),
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
                          style: t.title.copyWith(color: AppColors.inkHeading),
                        ),
                        Text(
                          caption,
                          style: t.caption.copyWith(color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ReturnStatusPill(
                    tone: summary.tone,
                    label: summary.statusLabel,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ReturnThumb(url: first?.thumbnail),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                first?.name ??
                                    '${l10n.orderNumber(summary.orderNumber)} · '
                                        '${l10n.orderItemCount(summary.itemCount)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodyStrong.copyWith(
                                  color: AppColors.inkHeading,
                                ),
                              ),
                            ),
                            if (first != null && more > 0) ...[
                              const SizedBox(width: 6),
                              Text(
                                l10n.returnsMoreItems(more),
                                style: t.caption.copyWith(
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (seller.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              l10n.returnsSoldBy(seller),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.caption.copyWith(
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
                                  style: t.captionStrong.copyWith(
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
                    HubIcons.chevronRight,
                    size: 18,
                    color: AppColors.inkMuted,
                  ),
                ],
              ),
              if (summary.refusedByStore) ...[
                const SizedBox(height: 10),
                const _EscalateBanner(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Figma 65:2928: "Not happy with the store's answer?  Escalate" on a return
/// the store rejected — red on the red tint, 10 px radius. It is part of the
/// card: tapping it opens the return, where Escalate is.
class _EscalateBanner extends StatelessWidget {
  const _EscalateBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.dangerSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(HubIcons.triangleAlert, size: 16, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.returnsRejectedPrompt,
              style: t.caption.copyWith(color: AppColors.danger),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.returnsEscalate,
            style: t.captionStrong.copyWith(color: AppColors.danger),
          ),
        ],
      ),
    );
  }
}

/// "+ New return request" (Figma 65:2943): white, navy 1.5 outline.
class _NewRequestButton extends StatelessWidget {
  const _NewRequestButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => HubButton(
    label: AppLocalizations.of(context).returnsNewRequest,
    icon: HubIcons.plus,
    iconSize: 20,
    style: HubButtonStyle.outline,
    onPressed: onPressed,
  );
}

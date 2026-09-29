import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/util/launch.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/returns.dart';
import '../returns_providers.dart';
import '../widgets/return_widgets.dart';

/// One return (Figma 23c, `hmReturn`): its lines, outcome and status, the
/// status history and the messages as one thread, oldest first, and a reply
/// box while the return is open (`hmAddReturnMessage`). Staff appear as Hub
/// Market, never by name.
///
/// Not built, for want of contract support: photo attachments on a reply
/// (the camera button) and Escalate.
class ReturnDetailScreen extends ConsumerStatefulWidget {
  const ReturnDetailScreen({super.key, required this.returnId});

  final int returnId;

  @override
  ConsumerState<ReturnDetailScreen> createState() => _ReturnDetailScreenState();
}

class _ReturnDetailScreenState extends ConsumerState<ReturnDetailScreen> {
  final TextEditingController _reply = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _reply.addListener(_onReplyChanged);
  }

  @override
  void dispose() {
    _reply.removeListener(_onReplyChanged);
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onReplyChanged() => setState(() {});

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _sending = true);
    try {
      await ref
          .read(returnDetailControllerProvider(widget.returnId).notifier)
          .reply(text);
      if (!mounted) return;
      _reply.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(serverMessageOr(context, error, l10n.errorGeneric))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final available = ref.watch(returnsAvailableProvider);
    final async = ref.watch(returnDetailControllerProvider(widget.returnId));
    final detail = async.valueOrNull;

    final Widget body;
    if (!available) {
      body = EmptyState(
        icon: Icons.assignment_return_outlined,
        title: l10n.returnsUnavailableTitle,
        body: l10n.returnsUnavailableBody,
      );
    } else if (detail != null) {
      body = _thread(context, detail);
    } else if (async.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (async.hasError) {
      final error = async.error;
      body = Center(
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
                onPressed: () => ref.invalidate(
                  returnDetailControllerProvider(widget.returnId),
                ),
                child: Text(l10n.actionRetry),
              ),
            ],
          ),
        ),
      );
    } else {
      body = EmptyState(
        icon: Icons.assignment_return_outlined,
        title: l10n.returnsNotFound,
      );
    }

    return Scaffold(
      backgroundColor: groupedPageColor(context),
      appBar: subpageAppBar(
        context,
        detail != null ? l10n.returnsTitle(detail.number) : l10n.returnsMyReturns,
      ),
      body: body,
      bottomNavigationBar: available && detail != null && detail.acceptsReplies
          ? _Composer(
              controller: _reply,
              sending: _sending,
              onSend: _send,
            )
          : null,
    );
  }

  Widget _thread(BuildContext context, ReturnDetail detail) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _SummaryCard(detail: detail),
        const SizedBox(height: 12),
        for (final entry in _timeline(detail)) ...[
          switch (entry) {
            _Event(:final history, :final first) => _EventPill(
              text: [
                first
                    ? ((detail.seller?.name.trim() ?? '').isNotEmpty
                          ? l10n.returnsEventSentTo(detail.seller!.name.trim())
                          : l10n.returnsEventSent)
                    : history.statusLabel,
                returnDay(history.createdAt, locale),
              ].where((s) => s.isNotEmpty).join(' · '),
            ),
            _Message(:final message) => _Bubble(message: message),
          },
          const SizedBox(height: 10),
        ],
        if (!detail.acceptsReplies)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: groupCardColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: returnsSubtleText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.returnsClosedNote,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 16 / 12,
                      color: returnsSubtleText,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// History and messages in one list, oldest first; on a tie the status
  /// change comes first (a return is filed, then its first message).
  List<_Entry> _timeline(ReturnDetail detail) {
    final entries = <({DateTime? at, int rank, int index, _Entry entry})>[];
    for (var i = 0; i < detail.history.length; i++) {
      entries.add((
        at: returnInstant(detail.history[i].createdAt),
        rank: 0,
        index: i,
        entry: _Event(detail.history[i], first: i == 0),
      ));
    }
    for (var i = 0; i < detail.messages.length; i++) {
      entries.add((
        at: returnInstant(detail.messages[i].createdAt),
        rank: 1,
        index: i,
        entry: _Message(detail.messages[i]),
      ));
    }
    entries.sort((a, b) {
      final at = a.at, bt = b.at;
      if (at != null && bt != null && at != bt) return at.compareTo(bt);
      if (a.rank != b.rank) return a.rank - b.rank;
      return a.index - b.index;
    });
    return [for (final e in entries) e.entry];
  }
}

sealed class _Entry {
  const _Entry();
}

class _Event extends _Entry {
  const _Event(this.history, {required this.first});

  final ReturnHistoryEntry history;

  /// The oldest entry: the return being filed.
  final bool first;
}

class _Message extends _Entry {
  const _Message(this.message);

  final ReturnMessage message;
}

/// The return at a glance (Figma 65:3010): its lines, outcome and reason,
/// status, refund amount, and the facts the customer gave.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.detail});

  final ReturnDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = detail.items;
    final first = items.isEmpty ? null : items.first;
    final caption = [
      if (first != null && first.quantity > 1) '×${first.quantity.toInt()}',
      returnTypeLabel(l10n, detail.type),
      ?detail.reasonText,
    ].join(' · ');
    final refund = detail.type == ReturnType.refund ? detail.refundAmount : null;
    final tracking = detail.trackingCode;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: groupCardColor(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ReturnThumb(url: first?.imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (first != null)
                      Text(
                        first.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkHeading,
                        ),
                      ),
                    Text(
                      caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
              ReturnStatusPill(state: detail.state, label: detail.statusLabel),
            ],
          ),
          for (final item in items.skip(1)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                ReturnThumb(url: item.imageUrl, size: 40, radius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 20 / 14,
                      color: AppColors.inkHeading,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '×${item.quantity.toInt()}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkHeading,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (refund != null)
            _FactRow(
              label: l10n.returnsRefundAmount,
              value: refund.formatted(),
              ltrValue: true,
            ),
          _FactRow(
            label: l10n.returnsOrderLabel,
            value: '#${detail.orderNumber}',
            ltrValue: true,
          ),
          _FactRow(
            label: l10n.returnsPackageOpenedRow,
            value: detail.packageOpened
                ? l10n.returnsAnswerYes
                : l10n.returnsAnswerNo,
          ),
          if (tracking != null)
            _FactRow(
              label: l10n.returnsTrackingRow,
              value: tracking,
              ltrValue: true,
            ),
        ],
      ),
    );
  }
}

/// Label and value on one line (Figma "Refund amount  AED 43").
class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
    this.ltrValue = false,
  });

  final String label;
  final String value;

  /// Amounts, numbers and codes read left to right in Arabic too.
  final bool ltrValue;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              height: 20 / 14,
              color: returnsSubtleText,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textDirection: ltrValue ? TextDirection.ltr : null,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w600,
              color: AppColors.inkHeading,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A status change in the thread (Figma 65:3015).
class _EventPill extends StatelessWidget {
  const _EventPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: groupCardColor(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 12, color: AppColors.inkMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                height: 14 / 11,
                fontWeight: FontWeight.w700,
                color: AppColors.inkMuted,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A message (Figma 65:3021 / 65:3026): the customer's in navy on the end
/// side, the seller's and Hub Market's in white on the start side.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ReturnMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final mine = message.author == ReturnActor.customer;
    final name = switch (message.author) {
      ReturnActor.customer => l10n.returnsYou,
      _ => message.authorName,
    };
    final nameColor = switch (message.author) {
      ReturnActor.customer => AppColors.borderStrong,
      ReturnActor.seller => returnsVendorColor,
      ReturnActor.hubMarket => AppColors.brandPrimary,
    };
    final time = returnDayTime(message.createdAt, locale);
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: mine ? AppColors.brandPrimary : groupCardColor(context),
            borderRadius: BorderRadius.circular(14),
            border: mine ? null : Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (name.isNotEmpty)
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    height: 16 / 12,
                    fontWeight: FontWeight.w600,
                    color: nameColor,
                  ),
                ),
              if (message.bodyText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  message.bodyText,
                  style: TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    color: mine ? Colors.white : AppColors.inkHeading,
                  ),
                ),
              ],
              if (message.attachmentUrls.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final url in message.attachmentUrls)
                      Semantics(
                        button: true,
                        label: l10n.returnsAttachment,
                        child: GestureDetector(
                          onTap: () {
                            final uri = Uri.tryParse(url);
                            if (uri != null) launchExternalUri(uri);
                          },
                          child: ReturnThumb(
                            url: url,
                            size: 64,
                            radius: 8,
                            icon: Icons.attach_file,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (time.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 11,
                    height: 14 / 11,
                    fontWeight: FontWeight.w700,
                    color: mine ? AppColors.borderStrong : AppColors.inkMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The reply bar (Figma 65:3046), shown only while the return is open.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canSend = controller.text.trim().isNotEmpty && !sending;
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(21)),
      borderSide: BorderSide(color: AppColors.borderStrong),
    );
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
        padding: EdgeInsets.fromLTRB(
          12,
          10,
          12,
          10 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 5000,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontSize: 14, color: AppColors.inkHeading),
                decoration: InputDecoration(
                  hintText: l10n.returnsWriteReply,
                  hintStyle: const TextStyle(color: AppColors.inkMuted),
                  counterText: '',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  border: border,
                  enabledBorder: border,
                  focusedBorder: border.copyWith(
                    borderSide: const BorderSide(
                      color: AppColors.brandPrimary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 42,
              height: 42,
              child: IconButton.filled(
                onPressed: canSend ? onSend : null,
                tooltip: l10n.returnsSendReply,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                  disabledBackgroundColor: AppColors.borderStrong,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                ),
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_forward, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

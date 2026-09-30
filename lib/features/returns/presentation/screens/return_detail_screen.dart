import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/hubapp/hubapp.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../domain/return_photo.dart';
import '../../domain/returns.dart';
import '../returns_providers.dart';
import '../widgets/return_form_widgets.dart';
import '../widgets/return_photos.dart';
import '../widgets/return_widgets.dart';

/// One return (Figma 23c, `hmReturn`): its lines, outcome and status, the
/// status history, the messages and the customer's escalation as one thread,
/// oldest first, then what the customer may do with it — the server says
/// (`can_reply`, `can_escalate`, `can_cancel`), by the website's rules:
///
/// * a reply box, with the camera button for photos, while it takes replies
///   (`hmAddReturnMessage`);
/// * "Not resolved? Hub Market can step in." to escalate it once
///   (`hmEscalateReturn`, a message and photos);
/// * Cancel return request while it is pending or accepted
///   (`hmCancelReturn`).
///
/// Staff appear as Hub Market, never by name.
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
  bool _cancelling = false;

  /// Photos waiting to go with the next reply.
  List<ReturnPhoto> _photos = const <ReturnPhoto>[];

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

  ReturnDetailController get _controller =>
      ref.read(returnDetailControllerProvider(widget.returnId).notifier);

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _sending = true);
    try {
      await _controller.reply(text, photos: _photos);
      if (!mounted) return;
      _reply.clear();
      setState(() => _photos = const <ReturnPhoto>[]);
      _toEnd();
    } catch (error) {
      if (!mounted) return;
      _say(serverMessageOr(context, error, l10n.errorGeneric));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _addPhotos(ReturnConfig config) async {
    final added = await pickReturnPhotos(
      context,
      ref,
      config: config,
      room: config.attachmentMaxFiles - _photos.length,
    );
    if (added.isEmpty || !mounted) return;
    setState(
      () => _photos = [
        ..._photos,
        ...added,
      ].take(config.attachmentMaxFiles).toList(),
    );
  }

  Future<void> _escalate(ReturnConfig? config) async {
    final l10n = AppLocalizations.of(context);
    final escalated = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => _EscalateSheet(returnId: widget.returnId, config: config),
    );
    if (escalated != true || !mounted) return;
    invalidateReturnLists(ref);
    _say(l10n.returnsEscalated);
    _toEnd();
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.returnsCancelTitle),
        content: Text(l10n.returnsCancelBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.returnsCancelKeep),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(l10n.returnsCancelConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await _controller.cancel();
      if (!mounted) return;
      invalidateReturnLists(ref);
      _say(l10n.returnsCancelled);
    } catch (error) {
      if (!mounted) return;
      _say(serverMessageOr(context, error, l10n.errorGeneric));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final available = ref.watch(returnsAvailableProvider);
    final signedIn = ref.watch(
      authControllerProvider.select((s) => s.isAuthenticated),
    );
    // Returns are read only when they are on and the customer is signed in.
    final async = available && signedIn
        ? ref.watch(returnDetailControllerProvider(widget.returnId))
        : const AsyncValue<ReturnDetail?>.data(null);
    final detail = async.valueOrNull;
    // What files a message may carry; photos wait until it's known.
    final config = available && signedIn && detail != null
        ? ref.watch(returnConfigProvider).valueOrNull
        : null;
    final photoConfig = config != null && config.acceptsPhotos ? config : null;

    final Widget body;
    if (!available || async.error is HubAppMissing) {
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
    } else if (detail != null) {
      body = _thread(context, detail, config);
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
        detail != null
            ? l10n.returnsTitle(returnNumberLabel(detail.number))
            : l10n.returnsMyReturns,
      ),
      body: body,
      bottomNavigationBar: available && detail != null && detail.canReply
          ? _Composer(
              controller: _reply,
              sending: _sending,
              onSend: _send,
              photos: _photos,
              maxPhotos: photoConfig?.attachmentMaxFiles ?? 0,
              onAddPhotos:
                  photoConfig != null &&
                      _photos.length < photoConfig.attachmentMaxFiles
                  ? () => _addPhotos(photoConfig)
                  : null,
              onRemovePhoto: (index) =>
                  setState(() => _photos = [..._photos]..removeAt(index)),
            )
          : null,
    );
  }

  Widget _thread(
    BuildContext context,
    ReturnDetail detail,
    ReturnConfig? config,
  ) {
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
            _Message(:final message) => _Bubble.message(message),
            _Escalation(:final escalation) => _Bubble.escalation(escalation),
          },
          const SizedBox(height: 10),
        ],
        if (!detail.canReply) ...[
          const _ClosedNote(),
          const SizedBox(height: 10),
        ],
        if (detail.canEscalate) ...[
          _EscalateCard(onTap: () => _escalate(config)),
          const SizedBox(height: 10),
        ],
        if (detail.canCancel)
          Align(
            alignment: AlignmentDirectional.center,
            child: TextButton.icon(
              onPressed: _cancelling ? null : _cancel,
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              icon: _cancelling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.close, size: 18),
              label: Text(l10n.returnsCancelAction),
            ),
          ),
      ],
    );
  }

  /// History, messages and the escalation in one list, oldest first; on a
  /// tie the status change comes first (a return is filed, then its first
  /// message).
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
    if (detail.escalation case final escalation?) {
      entries.add((
        at: returnInstant(escalation.createdAt),
        rank: 1,
        index: detail.messages.length,
        entry: _Escalation(escalation),
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

class _Escalation extends _Entry {
  const _Escalation(this.escalation);

  final ReturnEscalation escalation;
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
    final refund = detail.type == ReturnType.refund
        ? detail.refundAmount
        : null;
    final tracking = detail.trackingCode;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
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
              ReturnStatusPill(tone: detail.tone, label: detail.statusLabel),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Short fixed labels; the value takes the rest of the row.
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            height: 20 / 14,
            color: returnsSubtleText,
          ),
        ),
        const SizedBox(width: 12),
        // On the end side in either direction, the text itself LTR when it
        // is an amount or a code.
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              value,
              textDirection: ltrValue ? TextDirection.ltr : null,
              style: const TextStyle(
                fontSize: 14,
                height: 20 / 14,
                fontWeight: FontWeight.w600,
                color: AppColors.inkHeading,
              ),
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
        color: Colors.white,
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
/// side, the seller's and Hub Market's in white on the start side, each with
/// its photos (65:3019). The customer's escalation reads as theirs, headed
/// "Escalated to Hub Market".
class _Bubble extends StatelessWidget {
  const _Bubble.message(ReturnMessage this.message) : escalation = null;

  const _Bubble.escalation(ReturnEscalation this.escalation) : message = null;

  final ReturnMessage? message;
  final ReturnEscalation? escalation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final message = this.message;
    final escalation = this.escalation;
    final author = message?.author ?? ReturnActor.customer;
    final mine = author == ReturnActor.customer;
    final name = escalation != null
        ? l10n.returnsEscalationTitle
        : switch (author) {
            ReturnActor.customer => l10n.returnsYou,
            ReturnActor.seller => message!.authorName,
            // Staff are never named, whatever the server sends.
            ReturnActor.hubMarket => kReturnsStaffName,
          };
    final nameColor = switch (author) {
      ReturnActor.customer => AppColors.borderStrong,
      ReturnActor.seller => returnsVendorColor,
      ReturnActor.hubMarket => AppColors.brandPrimary,
    };
    final body = message?.bodyText ?? escalation!.bodyText;
    final attachments = message?.attachments ?? escalation!.attachments;
    final time = returnDayTime(
      message?.createdAt ?? escalation!.createdAt,
      locale,
    );
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: mine ? AppColors.brandPrimary : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: mine ? null : Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (name.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (escalation != null) ...[
                      Icon(Icons.shield_outlined, size: 14, color: nameColor),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          height: 16 / 12,
                          fontWeight: FontWeight.w600,
                          color: nameColor,
                        ),
                      ),
                    ),
                  ],
                ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    color: mine ? Colors.white : AppColors.inkHeading,
                  ),
                ),
              ],
              if (attachments.isNotEmpty) ...[
                const SizedBox(height: 4),
                ReturnAttachmentStrip(attachments: attachments, onDark: mine),
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

/// "This return is closed, so it can't take new messages."
class _ClosedNote extends StatelessWidget {
  const _ClosedNote();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 18, color: returnsSubtleText),
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
    );
  }
}

/// "Not resolved? Hub Market can step in. Escalate" (Figma 65:3034).
class _EscalateCard extends StatelessWidget {
  const _EscalateCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 18,
                  color: returnsSubtleText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.returnsEscalatePrompt,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 16 / 12,
                      color: returnsSubtleText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.returnsEscalate,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 16 / 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentStrong,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Escalate to Hub Market: what went wrong (required, as on the website's
/// form) and photos, then `hmEscalateReturn`. Pops true once escalated.
class _EscalateSheet extends ConsumerStatefulWidget {
  const _EscalateSheet({required this.returnId, required this.config});

  final int returnId;

  /// The store's upload rules; no photos until they're known.
  final ReturnConfig? config;

  @override
  ConsumerState<_EscalateSheet> createState() => _EscalateSheetState();
}

class _EscalateSheetState extends ConsumerState<_EscalateSheet> {
  final TextEditingController _message = TextEditingController();
  List<ReturnPhoto> _photos = const <ReturnPhoto>[];
  bool _sending = false;
  bool _showError = false;
  String? _failure;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _addPhotos(ReturnConfig config) async {
    final added = await pickReturnPhotos(
      context,
      ref,
      config: config,
      room: config.attachmentMaxFiles - _photos.length,
    );
    if (added.isEmpty || !mounted) return;
    setState(
      () => _photos = [
        ..._photos,
        ...added,
      ].take(config.attachmentMaxFiles).toList(),
    );
  }

  Future<void> _submit() async {
    final text = _message.text.trim();
    if (_sending) return;
    if (text.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      await ref
          .read(returnDetailControllerProvider(widget.returnId).notifier)
          .escalate(text, photos: _photos);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failure = serverMessageOr(context, error, l10n.errorGeneric);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = widget.config;
    const outline = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: AppColors.borderStrong),
    );
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReturnSheetTitle(
                l10n.returnsEscalateTitle,
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.returnsEscalateBody,
                style: const TextStyle(
                  fontSize: 13,
                  height: 18 / 13,
                  color: returnsSubtleText,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _message,
                minLines: 3,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                inputFormatters: [LengthLimitingTextInputFormatter(5000)],
                onChanged: (_) {
                  if (_showError) setState(() => _showError = false);
                },
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.inkHeading,
                ),
                decoration: InputDecoration(
                  hintText: l10n.returnsEscalateHint,
                  hintStyle: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: outline,
                  enabledBorder: outline,
                  focusedBorder: outline.copyWith(
                    borderSide: const BorderSide(
                      color: AppColors.brandPrimary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              if (_showError) ReturnFieldError(l10n.returnsEscalateError),
              if (config != null && config.acceptsPhotos) ...[
                const SizedBox(height: 14),
                ReturnPhotoField(
                  label: l10n.returnsPhotos,
                  photos: _photos,
                  maxPhotos: config.attachmentMaxFiles,
                  onAdd: _sending ? null : () => _addPhotos(config),
                  onRemove: (index) =>
                      setState(() => _photos = [..._photos]..removeAt(index)),
                ),
              ],
              if (_failure case final failure?) ReturnFieldError(failure),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _sending ? null : _submit,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        l10n.returnsEscalateSubmit,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The reply bar (Figma 65:3046), shown only while the return takes
/// replies: the camera button (65:3039) when the store takes photos, the
/// photos waiting to go, the field and Send.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.photos,
    required this.maxPhotos,
    required this.onAddPhotos,
    required this.onRemovePhoto,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final List<ReturnPhoto> photos;

  /// 0 when photos aren't taken: no camera button.
  final int maxPhotos;
  final VoidCallback? onAddPhotos;
  final ValueChanged<int> onRemovePhoto;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (photos.isNotEmpty) ...[
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) => ReturnPhotoTile(
                    photo: photos[index],
                    size: 56,
                    onRemove: () => onRemovePhoto(index),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (maxPhotos > 0) ...[
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      onPressed: sending ? null : onAddPhotos,
                      tooltip: l10n.returnsAddPhotos,
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surfaceSubtle,
                        disabledBackgroundColor: AppColors.surfaceSubtle,
                        foregroundColor: AppColors.inkHeading,
                        disabledForegroundColor: AppColors.borderStrong,
                      ),
                      icon: const Icon(Icons.photo_camera_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 5000,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.inkHeading,
                    ),
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
          ],
        ),
      ),
    );
  }
}

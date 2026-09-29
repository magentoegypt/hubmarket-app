import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../l10n/l10n.dart';

/// Rebuilds every second with the time left until [endsAt] — the deals
/// countdown (Figma 07 "countdown", 10b banner). Stops at zero and then
/// draws nothing: an offer that ended isn't counted down.
class DealCountdown extends StatefulWidget {
  const DealCountdown({
    super.key,
    required this.endsAt,
    required this.builder,
    this.now = DateTime.now,
  });

  final DateTime endsAt;
  final Widget Function(BuildContext context, Duration remaining) builder;

  /// The clock (tests pin it).
  final DateTime Function() now;

  @override
  State<DealCountdown> createState() => _DealCountdownState();
}

class _DealCountdownState extends State<DealCountdown> {
  Timer? _timer;

  Duration get _remaining => widget.endsAt.difference(widget.now());

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(DealCountdown old) {
    super.didUpdateWidget(old);
    if (old.endsAt != widget.endsAt) _start();
  }

  void _start() {
    _timer?.cancel();
    if (_remaining <= Duration.zero) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_remaining <= Duration.zero) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _remaining;
    if (left <= Duration.zero) return const SizedBox.shrink();
    return widget.builder(context, left);
  }
}

/// `14:32:19` — hours, minutes and seconds within the day, Western digits in
/// both languages like prices.
String countdownClock(Duration left) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(left.inHours % 24)}:${two(left.inMinutes % 60)}:${two(left.inSeconds % 60)}';
}

/// `2d 14:32:19` (the days in the reader's language before the clock), or
/// `14:32:19` inside the last day.
class CountdownText extends StatelessWidget {
  const CountdownText({super.key, required this.left, required this.style});

  final Duration left;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final clock = Text(
      countdownClock(left),
      textDirection: TextDirection.ltr,
      style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
    if (left.inDays == 0) return clock;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context).dealsCountdownDays(left.inDays),
          style: style,
        ),
        const SizedBox(width: 4),
        clock,
      ],
    );
  }
}

/// The navy pill of Figma 07's Today's Deals: clock, time left, "remaining".
class DealCountdownPill extends StatelessWidget {
  const DealCountdownPill({super.key, required this.endsAt, this.now});

  final DateTime endsAt;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final l10n = AppLocalizations.of(context);
    return DealCountdown(
      endsAt: endsAt,
      now: now ?? DateTime.now,
      builder: (context, left) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.brandPrimary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.schedule_rounded,
              size: 16,
              color: AppColors.accent,
            ),
            const SizedBox(width: 8),
            CountdownText(
              left: left,
              style: t.bodyStrong.copyWith(color: Colors.white),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.homeCountdownRemaining,
              style: t.caption.copyWith(color: const Color(0xFFCBD3E2)),
            ),
          ],
        ),
      ),
    );
  }
}

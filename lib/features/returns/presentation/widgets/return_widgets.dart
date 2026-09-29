import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/returns.dart';

/// Pieces shared by the returns screens (Figma 23, 23b, 23c).

/// Vendor-link blue of "Sold by …" and the seller's name in the thread
/// (Figma `--hm-vendor`).
const Color returnsVendorColor = AppColors.info;

/// Muted body text on the returns cards (Figma `--hm-subtle`).
const Color returnsSubtleText = Color(0xFF535D70);

/// A contract timestamp (ISO-8601 UTC) in the device's zone, or null.
DateTime? returnInstant(String raw) {
  final parsed = DateTime.tryParse(raw.trim());
  return parsed?.toLocal();
}

String _format(String pattern, DateTime value, String locale) {
  try {
    return DateFormat(pattern, locale).format(value);
  } catch (_) {
    return DateFormat(pattern).format(value);
  }
}

/// "24 Sep" — with the year when it isn't this year's.
String returnDay(String raw, String locale, {DateTime? now}) {
  final value = returnInstant(raw);
  if (value == null) return '';
  final thisYear = (now ?? DateTime.now()).year == value.year;
  return _format(thisYear ? 'd MMM' : 'd MMM yyyy', value, locale);
}

/// "24 Sep, 18:02" (Figma 23c message times).
String returnDayTime(String raw, String locale, {DateTime? now}) {
  final value = returnInstant(raw);
  if (value == null) return '';
  final thisYear = (now ?? DateTime.now()).year == value.year;
  return _format(thisYear ? 'd MMM, HH:mm' : 'd MMM yyyy, HH:mm', value, locale);
}

String returnTypeLabel(AppLocalizations l10n, ReturnType type) =>
    switch (type) {
      ReturnType.refund => l10n.returnsTypeRefund,
      ReturnType.replace => l10n.returnsTypeReplace,
    };

/// Status pill (Figma 23b/23c): amber while open, green once closed
/// (resolved), red when cancelled. The label is the store's own status name.
class ReturnStatusPill extends StatelessWidget {
  const ReturnStatusPill({super.key, required this.state, required this.label});

  final ReturnState state;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (state) {
      ReturnState.open => (AppColors.warningSubtle, AppColors.warning),
      ReturnState.closed => (AppColors.successSubtle, AppColors.successStrong),
      ReturnState.canceled => (AppColors.dangerSurface, AppColors.danger),
    };
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          height: 14 / 11,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

/// A rounded product thumbnail on the muted ground, or a returns glyph when
/// there is no image.
class ReturnThumb extends StatelessWidget {
  const ReturnThumb({
    super.key,
    required this.url,
    this.size = 52,
    this.radius = 10,
    this.icon = Icons.assignment_return_outlined,
  });

  final String? url;
  final double size;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: AppColors.surfaceSubtle,
      child: Center(
        child: Icon(icon, size: size * 0.42, color: AppColors.inkMuted),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: (url ?? '').isEmpty
            ? fallback
            : HubImage(
                url: url,
                decodeWidth: size,
                placeholder: (_) =>
                    const ColoredBox(color: AppColors.surfaceSubtle),
                error: (_) => fallback,
              ),
      ),
    );
  }
}

/// The small bold label above a form field (Figma "Caption Strong").
class ReturnFieldLabel extends StatelessWidget {
  const ReturnFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      color: AppColors.inkHeading,
    ),
  );
}

/// A red inline message under a field that can't be sent as it is.
class ReturnFieldError extends StatelessWidget {
  const ReturnFieldError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(top: 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.danger),
    ),
  );
}

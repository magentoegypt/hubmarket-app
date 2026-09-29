import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../l10n/l10n.dart';
import 'search_style.dart';

/// The search screens' header row (Figma 09 · 09b · 09c · S2): the field, with
/// a back arrow before it on the results page and a Cancel action after it
/// everywhere else.
///
/// The field keeps the same slot in the row whatever the mode — the arrow and
/// Cancel are hidden rather than removed — so switching modes never rebuilds
/// the TextField and drops its focus.
class SearchFieldBar extends StatelessWidget {
  const SearchFieldBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    this.onBack,
    this.onCancel,
    this.autofocus = false,
    this.emphasised = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  /// The (x) inside the field, shown while it holds text.
  final VoidCallback onClear;

  /// Shows the back arrow (results, Figma 09c).
  final VoidCallback? onBack;

  /// Shows the Cancel action (landing, type-ahead, no results).
  final VoidCallback? onCancel;
  final bool autofocus;

  /// The navy 1.5 pt outline of a search being typed; the results page draws a
  /// quieter 1 pt grey one.
  final bool emphasised;

  /// The 46 pt field plus 6 above and 10 below.
  static const double height = 62;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final back = onBack;
    final cancel = onCancel;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 10),
      child: Row(
        children: [
          Visibility(
            visible: back != null,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: SizedBox.square(
                dimension: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 22,
                  color: context.scaffoldHeading,
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  // arrow_back mirrors itself in RTL.
                  icon: const Icon(Icons.arrow_back),
                  onPressed: back,
                ),
              ),
            ),
          ),
          Expanded(
            child: _SearchInput(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              emphasised: emphasised,
              hint: l10n.searchFieldHint,
              clearLabel: l10n.searchClearField,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              onClear: onClear,
            ),
          ),
          Visibility(
            visible: cancel != null,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 12),
              child: TextButton(
                onPressed: cancel,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accentStrong,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                // Styled on the Text, not the button: a ButtonStyle textStyle
                // replaces the theme's (and its font family) outright.
                child: Text(
                  l10n.actionCancel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchInput extends StatelessWidget {
  const _SearchInput({
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.emphasised,
    required this.hint,
    required this.clearLabel,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final bool emphasised;
  final String hint;
  final String clearLabel;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    final Color border;
    if (emphasised) {
      border = dark ? Colors.white70 : AppColors.brandPrimary;
    } else {
      border = SearchStyle.chipBorder(context);
    }
    return Container(
      height: 46,
      // 4 at the end: the clear button's 36 pt target then puts its 20 pt disc
      // 12 from the edge, as drawn.
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      decoration: BoxDecoration(
        color: dark ? Colors.white10 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: emphasised ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: context.scaffoldMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              cursorColor: dark ? Colors.white : AppColors.brandPrimary,
              style: TextStyle(fontSize: 14, color: context.scaffoldHeading),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: hint,
                hintMaxLines: 1,
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: context.scaffoldMuted,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : _ClearButton(label: clearLabel, onTap: onClear),
          ),
        ],
      ),
    );
  }
}

/// The small grey (x) disc at the field's end — a 20 pt visual on a 36 pt
/// target.
class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: SizedBox.square(
          dimension: 36,
          child: Center(
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: SearchStyle.outline,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

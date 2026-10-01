import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// The customer's avatar as the Account frames draw it (20, 20c): a navy disc
/// with the initials in white, DM Sans Bold (Tajawal Bold in Arabic) — 56 px
/// with an 18 px label on the hub, 84 px with 28 on Profile details.
///
/// There is no photo: the backend has no customer-photo endpoint, so every
/// avatar is initials.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    this.diameter = 56,
    this.fontSize = 18,
  });

  final String name;
  final double diameter;
  final double fontSize;

  /// First letter of the first and of the last word, upper-cased ("Sara
  /// Ahmed" → "SA"); a single word gives one letter, nothing gives "?".
  /// Arabic letters are joined by a space ("س أ"), as the frame draws them: set
  /// side by side they would join into one word.
  static String initialsOf(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    String first(String word) => word.characters.first.toUpperCase();
    final letters = words.length == 1
        ? [first(words.first)]
        : [first(words.first), first(words.last)];
    final arabic = RegExp(r'[؀-ۿ]').hasMatch(letters.join());
    return letters.join(arabic ? ' ' : '');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.brandPrimary,
        shape: BoxShape.circle,
      ),
      child: Text(
        initialsOf(name),
        maxLines: 1,
        // The line is centred whatever its height (even leading), so the
        // heading style's own ratio does for every size.
        style: t.heading2.copyWith(color: Colors.white, fontSize: fontSize),
      ),
    );
  }
}

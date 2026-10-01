import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// Figma "Input" showing a value instead of taking one: the label (EN/Caption
/// Strong) over a white 52 px field — 1 px `border/strong` outline, radius 12,
/// 16 px at the sides — with a 20 px icon, the value, and a [trailing] part
/// (the "Change" of the mobile number). It is the e-mail, the mobile number and
/// the date of birth of Profile details; with an [onTap] it opens something
/// (the number's editor, the date picker).
///
/// [ltr] keeps what is shown left-to-right (e-mail, phone) while it still sits
/// at the field's start, as in the Arabic frame. Without a [value] the
/// [placeholder] shows, faint.
class ProfileValueField extends StatelessWidget {
  const ProfileValueField({
    super.key,
    required this.label,
    required this.icon,
    this.value,
    this.placeholder,
    this.ltr = false,
    this.trailing,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final String? value;
  final String? placeholder;
  final bool ltr;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final shown = (value != null && value!.isNotEmpty) ? value : placeholder;
    final hasValue = value != null && value!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: t.captionStrong.copyWith(color: AppColors.inkHeading)),
        const SizedBox(height: 6),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.borderStrong),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: AppColors.inkMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          shown ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: ltr && hasValue
                              ? TextDirection.ltr
                              : null,
                          style: t.body.copyWith(
                            color: hasValue
                                ? AppColors.inkHeading
                                : AppColors.inkFaint,
                          ),
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 10),
                      trailing!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

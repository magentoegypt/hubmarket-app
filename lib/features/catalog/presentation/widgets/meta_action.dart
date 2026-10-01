import 'package:flutter/material.dart';

import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_x.dart';

/// A action of a results line (Figma 09c "Relevance" and "Filter", 10
/// "Relevance"): a 16 px icon, 4 px, then the label in Caption Strong. The
/// padding around it is the tap target — [verticalPadding] makes the row as
/// tall as the frame's.
class MetaAction extends StatelessWidget {
  const MetaAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.verticalPadding = 10,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final color = context.scaffoldHeading;
    final t = AppTextStyles.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: verticalPadding),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            // Capped so a long sort name ("Price: High to Low", or its Arabic)
            // can't push the row past the screen next to a long results line.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.captionStrong.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

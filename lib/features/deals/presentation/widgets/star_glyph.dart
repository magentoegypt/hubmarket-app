import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';

/// A filled rating star in a [size] px slot, as Figma's `icon/star` draws it:
/// the glyph fills about 10 of its 12 px. The Material rounded star leaves a
/// third of its box empty, so the glyph is drawn 1.2 times larger and centred
/// in the slot, which keeps the layout (a 12 px star, 2 px apart) as the frame
/// has it.
class StarGlyph extends StatelessWidget {
  const StarGlyph({
    super.key,
    this.size = 12,
    this.color = AppColors.ratingStar,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: OverflowBox(
      maxWidth: size * 1.2,
      maxHeight: size * 1.2,
      child: Icon(Icons.star_rounded, size: size * 1.2, color: color),
    ),
  );
}

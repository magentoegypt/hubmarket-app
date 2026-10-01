import 'package:flutter/widgets.dart';

/// Layout units of the Home that follow the reader's text size. The frames fix
/// the heights of their cards, tiles and slides at normal text; where text sits
/// inside, the height is the frame's number at 1× and grows with the text
/// beyond it, so a larger text setting never overflows a card.
abstract final class HmMetrics {
  /// One line of [style] at the reader's text size.
  static double line(BuildContext context, TextStyle style) =>
      MediaQuery.textScalerOf(context).scale(style.fontSize! * style.height!);

  /// A point of room for the rounding of scaled line heights. Zero at normal
  /// text size, where the frame's own numbers are exact.
  static double slack(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(100) == 100 ? 0 : 1;
}

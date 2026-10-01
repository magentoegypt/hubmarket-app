import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../l10n/l10n.dart';

/// Figma S1 "Empty cart": a pale orange disc with the cart, "Your cart is
/// empty" in the display face, one line of invitation, Start shopping and View
/// wishlist — centred in the page between the header and the tab bar.
class CartEmptyView extends StatelessWidget {
  const CartEmptyView({
    super.key,
    required this.onStartShopping,
    required this.onViewWishlist,
  });

  final VoidCallback onStartShopping;
  final VoidCallback onViewWishlist;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    // SliverFillRemaining centres the content when it fits and scrolls when it
    // overflows (a large text size, a short window).
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 112,
                      height: 112,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.isDarkMode
                            ? Colors.white10
                            : AppColors.accentSubtle,
                        shape: BoxShape.circle,
                      ),
                      child: const _CartGlyph(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.cartEmptyTitle,
                    textAlign: TextAlign.center,
                    style: t.heading1.copyWith(color: context.scaffoldHeading),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.cartEmptyBody,
                    textAlign: TextAlign.center,
                    style: t.body.copyWith(color: context.scaffoldMuted),
                  ),
                  const SizedBox(height: 14),
                  // Figma: the buttons sit in a column 8 px under the rest.
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: onStartShopping,
                    child: Text(l10n.cartStartShopping),
                  ),
                  const SizedBox(height: 10),
                  HubButton(
                    label: l10n.cartEmptyWishlist,
                    style: HubButtonStyle.ghost,
                    onPressed: onViewWishlist,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The 48 px cart of the empty state, drawn from the Figma icon's own paths: at
/// this size its wheels are solid dots, where the icon font's glyph shows them
/// as rings.
class _CartGlyph extends StatelessWidget {
  const _CartGlyph();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(48),
      painter: _CartPainter(AppColors.accentStrong),
    ),
  );
}

class _CartPainter extends CustomPainter {
  const _CartPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas
      ..drawCircle(const Offset(16, 42), 2, stroke)
      ..drawCircle(const Offset(38, 42), 2, stroke);
    final body = Path()
      ..moveTo(4.1, 4.1)
      ..lineTo(8.1, 4.1)
      ..lineTo(13.42, 28.94)
      ..cubicTo(13.6152, 29.8497, 14.1213, 30.663, 14.8514, 31.2397)
      ..cubicTo(15.5815, 31.8165, 16.4898, 32.1207, 17.42, 32.1)
      ..lineTo(36.98, 32.1)
      ..cubicTo(37.8904, 32.0985, 38.773, 31.7866, 39.4821, 31.2157)
      ..cubicTo(40.1911, 30.6448, 40.6843, 29.8491, 40.88, 28.96)
      ..lineTo(44.18, 14.1)
      ..lineTo(10.24, 14.1);
    canvas.drawPath(body, stroke);
  }

  @override
  bool shouldRepaint(_CartPainter oldDelegate) => oldDelegate.color != color;
}

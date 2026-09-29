import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Drives a single repeating gradient sweep over its subtree, turning any
/// [SkeletonBox] descendants into shimmering placeholders. One
/// [AnimationController] + one [ShaderMask] per block (cheap), so wrap a whole
/// skeleton layout in one [Shimmer] rather than each box. Colours default to the
/// design tokens.
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.base = AppColors.surfaceMuted,
    this.highlight = Colors.white,
    this.period = const Duration(milliseconds: 1400),
  });

  final Widget child;

  /// The resting colour of the skeleton blocks (also the [SkeletonBox] default).
  final Color base;

  /// The travelling highlight swept across [base].
  final Color highlight;

  /// One full left→right (LTR) sweep.
  final Duration period;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respect the platform "reduce motion" setting: paint a flat base tint
    // (still a skeleton, just not animated) instead of running the ticker.
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          colors: [widget.base, widget.base],
        ).createShader(bounds),
        child: widget.child,
      );
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [widget.base, widget.highlight, widget.base],
          stops: const [0.1, 0.5, 0.9],
          transform: _SweepTransform(_controller.value, rtl),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

/// Slides the gradient horizontally from fully off one edge to off the other as
/// [percent] runs 0→1 — reversed under RTL so the highlight tracks reading order.
class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.percent, this.rtl);

  final double percent;
  final bool rtl;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final t = rtl ? 1 - percent : percent;
    return Matrix4.translationValues((t * 2 - 1) * bounds.width, 0, 0);
  }
}

/// A solid, base-coloured block. On its own it's just a neutral shape; place it
/// under a [Shimmer] for it to animate. Defaults to the shimmer [Shimmer.base]
/// colour so the sweep reads cleanly.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.color = AppColors.surfaceMuted,
  }) : shape = BoxShape.rectangle;

  const SkeletonBox.circle({
    super.key,
    required double size,
    this.color = AppColors.surfaceMuted,
  }) : width = size,
       height = size,
       borderRadius = 0,
       shape = BoxShape.circle;

  final double? width;
  final double? height;
  final double borderRadius;
  final Color color;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        shape: shape,
        borderRadius: shape == BoxShape.circle
            ? null
            : BorderRadius.circular(borderRadius),
      ),
    );
  }
}

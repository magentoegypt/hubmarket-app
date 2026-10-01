import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// One section of the Filters sheet (Figma 11 "filter/…"): the title in EN/Title
/// with an optional caption at the end, 10 pt, then the [child].
class FilterSection extends StatelessWidget {
  const FilterSection({
    super.key,
    required this.title,
    required this.child,
    this.caption,
    this.gap = 10,
  });

  final String title;
  final String? caption;
  final Widget child;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: t.title.copyWith(color: AppColors.inkHeading),
              ),
            ),
            if (caption != null && caption!.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption.copyWith(color: AppColors.inkMuted),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: gap),
        child,
      ],
    );
  }
}

/// A chip that can hold more than a label (the rating's star): the shared
/// "Chip" — 36 pt, 14 pt of padding, navy when selected, outlined otherwise.
class FilterChipButton extends StatelessWidget {
  const FilterChipButton({
    super.key,
    required this.child,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final bool selected;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final ink = selected ? Colors.white : AppColors.inkHeading;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: selected ? AppColors.brandPrimary : Colors.white,
        shape: StadiumBorder(
          side: selected
              ? BorderSide.none
              : const BorderSide(color: AppColors.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 36,
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: DefaultTextStyle(
                  style: t.bodyStrong.copyWith(color: ink),
                  child: IconTheme(
                    data: IconThemeData(color: ink),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The price range's thumb (Figma "price-slider"): a 24 pt white disc with a
/// navy ring and a soft shadow.
class PriceThumbShape extends RangeSliderThumbShape {
  const PriceThumbShape();

  static const double radius = 12;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool? isOnTop,
    required SliderThemeData sliderTheme,
    TextDirection? textDirection,
    Thumb? thumb,
    bool? isPressed,
  }) {
    final canvas = context.canvas;
    canvas.drawShadow(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
      const Color(0xFF0F2144),
      3,
      true,
    );
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = AppColors.brandPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}

/// The price range's track: 4 pt, `border/subtle` with the picked range in
/// navy, running from 6 pt in from each edge as the frame draws it.
class PriceTrackShape extends RangeSliderTrackShape {
  const PriceTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    const inset = 6.0;
    final height = sliderTheme.trackHeight ?? 4;
    return Rect.fromLTWH(
      offset.dx + inset,
      offset.dy + (parentBox.size.height - height) / 2,
      parentBox.size.width - inset * 2,
      height,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset startThumbCenter,
    required Offset endThumbCenter,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    final rounded = RRect.fromRectAndRadius(track, const Radius.circular(2));
    final canvas = context.canvas;
    canvas.drawRRect(rounded, Paint()..color = AppColors.borderSubtle);
    final left = startThumbCenter.dx < endThumbCenter.dx
        ? startThumbCenter.dx
        : endThumbCenter.dx;
    final right = startThumbCenter.dx < endThumbCenter.dx
        ? endThumbCenter.dx
        : startThumbCenter.dx;
    canvas.drawRect(
      Rect.fromLTRB(left, track.top, right, track.bottom),
      Paint()..color = AppColors.brandPrimary,
    );
  }
}

/// A Min / Max box of the price range (Figma "col"): the caption over the
/// value in EN/Body Strong, 12 × 8 pt inside a 1 pt `border/default` outline
/// with 10 pt corners. The value can be typed; [onSubmitted] gets the number
/// when editing ends (a blank or unreadable entry is null).
class PriceField extends StatefulWidget {
  const PriceField({
    super.key,
    required this.label,
    required this.value,
    required this.onSubmitted,
  });

  final String label;

  /// The range's current end, shown whenever the field isn't being edited.
  final int value;
  final ValueChanged<int?> onSubmitted;

  @override
  State<PriceField> createState() => _PriceFieldState();
}

class _PriceFieldState extends State<PriceField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant PriceField old) {
    super.didUpdateWidget(old);
    // The slider moved it: show that, unless it is being typed.
    if (!_focus.hasFocus && widget.value != old.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    widget.onSubmitted(int.tryParse(_controller.text.trim()));
    // Back to the (clamped) value the range holds once the sheet has taken it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focus.hasFocus) _controller.text = '${widget.value}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus.requestFocus,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.borderStrong),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label,
              style: t.caption.copyWith(color: AppColors.inkMuted),
            ),
            SizedBox(
              height: 20,
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _focus.unfocus(),
                style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
                cursorColor: AppColors.brandPrimary,
                decoration: const InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

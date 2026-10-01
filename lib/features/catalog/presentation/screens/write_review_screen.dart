import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../core/widgets/hub_icon_button.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/widgets/auth_field.dart';
import '../../data/catalog_repository.dart';
import '../../domain/product_detail.dart';
import '../../domain/review_subject.dart';
import '../catalog_providers.dart';
import '../widgets/review_widgets.dart';

/// Figma 15b — the review form: a close "×" and the title over a hairline, the
/// product being reviewed (when the page that opened the form handed it over,
/// [subject]), "How would you rate it?" with five stars and their word, the
/// nickname, the summary and the review, and a footer with the moderation note
/// and "Submit review".
///
/// Core Magento's `createProductReview` takes a nickname, a summary, a text and
/// the ratings — nothing else — so the frame's "What I like / don't like" fields
/// and its photos are left out: they would be collected and thrown away.
class WriteReviewScreen extends ConsumerStatefulWidget {
  const WriteReviewScreen({super.key, required this.sku, this.subject});

  final String sku;

  /// What the product page knew about the product; null from a bare link.
  final ReviewSubject? subject;

  @override
  ConsumerState<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends ConsumerState<WriteReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _summary = TextEditingController();
  final _text = TextEditingController();
  int _rating = 5;
  bool _busy = false;

  @override
  void dispose() {
    _nickname.dispose();
    _summary.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit(List<ReviewRatingMetadata> metadata) async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    // Apply the chosen star to every rating dimension (Quality / Value /
    // Price) so the review saves with the same shape the website produces.
    final ratings = <({String id, String valueId})>[];
    for (final rating in metadata) {
      if (rating.values.isEmpty) continue;
      final value = rating.values.firstWhere(
        (v) => v.value == _rating,
        orElse: () => rating.values.last,
      );
      ratings.add((id: rating.id, valueId: value.valueId));
    }
    if (ratings.isEmpty) {
      _snack(l10n.errorGeneric);
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(catalogRepositoryProvider)
          .createReview(
            sku: widget.sku,
            nickname: _nickname.text.trim(),
            summary: _summary.text.trim(),
            text: _text.text.trim(),
            ratings: ratings,
          );
      _snack(l10n.reviewSubmitted);
      if (mounted) context.pop();
    } catch (_) {
      _snack(l10n.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final metadata = ref.watch(reviewRatingsMetadataProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: RuledTopBar(
        title: l10n.reviewsWrite,
        leading: HubIconButton(
          icon: HubIcons.x,
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: AsyncValueView(
        value: metadata,
        onRetry: () => ref.invalidate(reviewRatingsMetadataProvider),
        data: (meta) => Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.subject != null) ...[
                        _SubjectCard(subject: widget.subject!),
                        const SizedBox(height: 18),
                      ],
                      _RatingInput(
                        rating: _rating,
                        onChanged: (value) => setState(() => _rating = value),
                      ),
                      const SizedBox(height: 18),
                      AuthField(
                        controller: _nickname,
                        label: l10n.reviewNickname,
                        icon: HubIcons.user,
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => Validators.required(context, v),
                      ),
                      const SizedBox(height: 18),
                      AuthField(
                        controller: _summary,
                        label: l10n.reviewSummary,
                        icon: HubIcons.pencil,
                        textCapitalization: TextCapitalization.sentences,
                        validator: (v) => Validators.required(context, v),
                      ),
                      const SizedBox(height: 18),
                      _ReviewTextArea(
                        controller: _text,
                        label: l10n.reviewText,
                        validator: (v) => Validators.required(context, v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Pinned under the form, and lifted above the keyboard with it.
            ScreenFooter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.reviewFooterNote,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.of(
                      context,
                    ).caption.copyWith(color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: 8),
                  HubButton(
                    label: l10n.reviewSubmit,
                    loading: _busy,
                    onPressed: () => _submit(meta),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Figma 15b "product": the product being reviewed on `bg/muted` — its 56 px photo,
/// the name in Body Strong and the seller in Caption. (The frame's "Size M ·
/// Beige floral" is what the customer bought; the page that opened the form
/// only knows what it was showing.)
class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.subject});

  final ReviewSubject subject;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final seller = subject.sellerName;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          HubImage(
            url: subject.imageUrl,
            width: 56,
            height: 56,
            borderRadius: BorderRadius.circular(10),
            error: (_) => const ColoredBox(color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
                ),
                if (seller != null && seller.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    seller,
                    style: t.caption.copyWith(color: AppColors.inkMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Figma 15b "rating": "How would you rate it?" in Title, five 34 px stars 8 px
/// apart that set the rating, and "4 of 5 · Good" in Caption Strong — centred,
/// 8 px between the parts.
class _RatingInput extends StatelessWidget {
  const _RatingInput({required this.rating, required this.onChanged});

  final int rating;
  final ValueChanged<int> onChanged;

  static String _word(AppLocalizations l10n, int stars) => switch (stars) {
    1 => l10n.reviewRatingPoor,
    2 => l10n.reviewRatingFair,
    3 => l10n.reviewRatingAverage,
    4 => l10n.reviewRatingGood,
    _ => l10n.reviewRatingExcellent,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Column(
      children: [
        Text(
          l10n.reviewHowRate,
          textAlign: TextAlign.center,
          style: t.title.copyWith(color: AppColors.inkHeading),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var star = 1; star <= 5; star++) ...[
              if (star > 1) const SizedBox(width: 8),
              Semantics(
                button: true,
                selected: star == rating,
                label: l10n.reviewRatingCaption(star, _word(l10n, star)),
                child: InkResponse(
                  key: ValueKey('review-star-$star'),
                  onTap: () => onChanged(star),
                  radius: 24,
                  child: StarGlyph(
                    size: 34,
                    color: star <= rating
                        ? AppColors.ratingStar
                        : AppColors.ratingEmpty,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.reviewRatingCaption(rating, _word(l10n, rating)),
          textAlign: TextAlign.center,
          style: t.captionStrong.copyWith(color: AppColors.inkMuted),
        ),
      ],
    );
  }
}

/// Figma 15b "textarea": the label in Caption Strong, 6 px above a white box with a
/// 1 px `border/strong` outline, radius 12, 14 × 12 padding and at least 96 px
/// high — the field of the review text, which grows with what is typed.
class _ReviewTextArea extends StatelessWidget {
  const _ReviewTextArea({
    required this.controller,
    required this.label,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String? value)? validator;

  static OutlineInputBorder _outline(Color color, double width) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: t.captionStrong.copyWith(color: AppColors.inkHeading),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          minLines: 3,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          textAlignVertical: TextAlignVertical.top,
          style: t.body.copyWith(color: AppColors.inkHeading),
          cursorColor: AppColors.brandPrimary,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            constraints: const BoxConstraints(minHeight: 96),
            errorStyle: t.caption.copyWith(color: AppColors.danger),
            border: _outline(AppColors.borderStrong, 1),
            enabledBorder: _outline(AppColors.borderStrong, 1),
            focusedBorder: _outline(AppColors.brandPrimary, 1.5),
            errorBorder: _outline(AppColors.danger, 1.5),
            focusedErrorBorder: _outline(AppColors.danger, 1.5),
          ),
        ),
      ],
    );
  }
}

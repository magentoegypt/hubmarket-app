import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/validation/validators.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../l10n/l10n.dart';
import '../../data/catalog_repository.dart';
import '../../domain/product_detail.dart';
import '../catalog_providers.dart';

class WriteReviewScreen extends ConsumerStatefulWidget {
  const WriteReviewScreen({super.key, required this.sku});

  final String sku;

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
      appBar: AppBar(title: Text(l10n.reviewsWrite)),
      body: AsyncValueView(
        value: metadata,
        onRetry: () => ref.invalidate(reviewRatingsMetadataProvider),
        data: (meta) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.reviewRating,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    for (var star = 1; star <= 5; star++)
                      IconButton(
                        onPressed: () => setState(() => _rating = star),
                        icon: Icon(
                          star <= _rating ? Icons.star : Icons.star_border,
                          color: AppColors.accentGold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nickname,
                  decoration: InputDecoration(labelText: l10n.reviewNickname),
                  validator: (v) => Validators.required(context, v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _summary,
                  decoration: InputDecoration(labelText: l10n.reviewSummary),
                  validator: (v) => Validators.required(context, v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _text,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: l10n.reviewText),
                  validator: (v) => Validators.required(context, v),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : () => _submit(meta),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.reviewSubmit),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

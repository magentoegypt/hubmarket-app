import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../deals/presentation/widgets/hm_list_widgets.dart';
import '../../../deals/presentation/widgets/list_states.dart';
import '../../data/brands_provider.dart';
import '../../domain/brand.dart';
import '../../../../app/theme/hub_icons.dart';

/// All brands (Figma 10d, `hmBrands`): search, A–Z initials, and every brand
/// that has products, with how many — `hmBrands`' own `product_count`, the
/// products each brand's page lists.
class BrandsScreen extends ConsumerStatefulWidget {
  const BrandsScreen({super.key});

  @override
  ConsumerState<BrandsScreen> createState() => _BrandsScreenState();
}

class _BrandsScreenState extends ConsumerState<BrandsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _initial; // null = "All"

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The upper-cased first letter of a brand's name.
  static String initialOf(Brand brand) {
    final name = brand.title.trim();
    return name.isEmpty ? '#' : name.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final brands = ref.watch(brandsProvider);
    return HubScaffold(
      currentTab: AppTab.home,
      appBar: HmTitleAppBar(
        title: l10n.brandsScreenTitle,
        actions: const <Widget>[],
      ),
      body: brands.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => HmListError(
          error: error,
          onRetry: () => ref.invalidate(brandsProvider),
          emptyTitle: l10n.brandsEmpty,
          emptyIcon: HubIcons.store,
        ),
        data: (all) => _content(context, l10n, all),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    AppLocalizations l10n,
    List<Brand> all,
  ) {
    final t = AppTextStyles.of(context);
    // Brands with products when the backend counted them; all of them from a
    // backend older than the counts.
    final known = all.any((b) => b.productCount != null);
    final listed = known
        ? [for (final b in all) if ((b.productCount ?? 0) > 0) b]
        : all;
    if (listed.isEmpty) {
      return EmptyState(icon: HubIcons.store, title: l10n.brandsEmpty);
    }

    final initials = listed.map(initialOf).toSet().toList()..sort();
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final b in listed)
        if ((query.isEmpty || b.title.toLowerCase().contains(query)) &&
            (_initial == null || initialOf(b) == _initial))
          b,
    ];
    final hint = '${listed.take(3).map((b) => b.title).join(', ')}…';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        Text(
          l10n.brandsSearchLabel,
          style: t.captionStrong.copyWith(color: AppColors.inkHeading),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          style: t.body.copyWith(color: AppColors.inkHeading),
          // The theme's Figma "Input" (white, 1 px outline, radius 12, 52 px),
          // with the icon where the frame has it: 16 px in, 20 px wide, 10 px
          // before the text.
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: t.body.copyWith(color: AppColors.inkMuted),
            prefixIcon: const Padding(
              // 10 before the text, less the 4 px Material 3 puts after an icon.
              padding: EdgeInsetsDirectional.only(start: 16, end: 6),
              child: Icon(
                HubIcons.search,
                size: 20,
                color: AppColors.inkMuted,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(),
            contentPadding: const EdgeInsetsDirectional.fromSTEB(0, 16, 16, 16),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: initials.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final letter = i == 0 ? null : initials[i - 1];
              return _InitialChip(
                label: letter ?? l10n.brandsFilterAll,
                selected: _initial == letter,
                onTap: () => setState(
                  () => _initial = (letter == null || _initial == letter)
                      ? null
                      : letter,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Text(
          l10n.brandsWithProducts(listed.length),
          style: t.caption.copyWith(color: AppColors.inkMuted),
        ),
        const SizedBox(height: 14),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: EmptyState(icon: HubIcons.searchX, title: l10n.brandsEmpty),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
              mainAxisExtent: BrandCard.heightFor(context),
            ),
            itemCount: shown.length,
            itemBuilder: (context, i) => BrandCard(
              brand: shown[i],
              productCount: shown[i].productCount,
            ),
          ),
      ],
    );
  }
}

class _InitialChip extends StatelessWidget {
  const _InitialChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? AppColors.brandPrimary : AppColors.surfaceSubtle,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 32),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTextStyles.of(context).captionStrong.copyWith(
              color: selected ? Colors.white : AppColors.inkHeading,
            ),
          ),
        ),
      ),
    ),
  );
}

/// A brand in the 10d grid: logo, name and product count; opens its page.
class BrandCard extends StatelessWidget {
  const BrandCard({super.key, required this.brand, this.productCount});

  final Brand brand;
  final int? productCount;

  /// The card's height (Figma 10d: 126 at 1x text in English): the 1 px
  /// outline, 10 above the 60 px logo, the name, the count 6 apart, and 12
  /// below — the two lines are as tall as the language and the user's text
  /// size make them.
  static double heightFor(BuildContext context) {
    final t = AppTextStyles.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle style) => scaler.scale(style.fontSize!) * style.height!;
    return 2 + 10 + 60 + 6 + line(t.captionStrong) + 6 + line(t.micro) + 12;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.push(AppRoutes.brandPage(brand.urlKey), extra: brand),
        child: Padding(
          // 8 / 10 / 8 / 12 inside the 1 px outline (Figma's border-box).
          padding: const EdgeInsets.fromLTRB(9, 11, 9, 13),
          child: Column(
            children: [
              SizedBox(
                height: 60,
                width: double.infinity,
                child: HubImage(
                  url: brand.imageUrl,
                  fit: BoxFit.contain,
                  borderRadius: BorderRadius.circular(8),
                  placeholder: (_) => const SizedBox.shrink(),
                  error: (_) => const ColoredBox(color: AppColors.surfaceSubtle),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                brand.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: t.captionStrong.copyWith(color: AppColors.inkHeading),
              ),
              if (productCount != null) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.hmProductCount(productCount!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.micro.copyWith(color: AppColors.inkMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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

/// All brands (Figma 10d, `hmBrands`): search, A–Z initials, and every brand
/// that has products, with how many — the catalogue's own `mgs_brand` facet.
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
    final counts = ref.watch(brandProductCountsProvider).valueOrNull;
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
          emptyIcon: Icons.storefront_outlined,
        ),
        data: (all) => _content(context, l10n, all, counts),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    AppLocalizations l10n,
    List<Brand> all,
    Map<int, int>? counts,
  ) {
    final t = AppTextStyles.of(context);
    // Brands with products when the counts are known; all of them otherwise.
    final known = counts != null && counts.isNotEmpty;
    final listed = known
        ? [for (final b in all) if ((counts[b.optionId] ?? 0) > 0) b]
        : all;
    if (listed.isEmpty) {
      return EmptyState(icon: Icons.storefront_outlined, title: l10n.brandsEmpty);
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
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: t.body.copyWith(color: AppColors.inkMuted),
            prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.inkMuted),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.brandPrimary, width: 1.5),
            ),
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
            child: EmptyState(icon: Icons.search_off, title: l10n.brandsEmpty),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
              mainAxisExtent: 132,
            ),
            itemCount: shown.length,
            itemBuilder: (context, i) => BrandCard(
              brand: shown[i],
              productCount: known ? counts[shown[i].optionId] : null,
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
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
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

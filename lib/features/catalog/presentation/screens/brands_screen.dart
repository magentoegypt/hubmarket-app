import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../data/brands_provider.dart';
import '../../domain/brand.dart';

/// "Our Brands" directory (Figma `420:2`): hero + "Search a brand" filter +
/// A–Z filter chips + brand-logo cards grouped by first letter. Reached from
/// the home "Explore Our Brands" See More. Tapping a brand searches the
/// catalogue for it (consistent with the home rail). Bidirectional: directional
/// insets + the display font apply only to EN, so it mirrors cleanly in AR.
class BrandsScreen extends ConsumerStatefulWidget {
  const BrandsScreen({super.key});

  @override
  ConsumerState<BrandsScreen> createState() => _BrandsScreenState();
}

class _BrandsScreenState extends ConsumerState<BrandsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _letter; // null = "All"

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// First A–Z letter of a brand title; anything else groups under '#'.
  static String _initial(String title) {
    final trimmed = title.trimLeft();
    if (trimmed.isEmpty) return '#';
    final c = trimmed[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final brands = ref.watch(brandsProvider);
    return HubScaffold(
      currentTab: AppTab.home,
      // Figma appbar: back chevron + centered HUB MARKET lockup (no search/bell).
      appBar: AppBar(
        toolbarHeight: 60,
        centerTitle: false,
        titleSpacing: 4,
        leading: const HubBackButton(),
        title: const BrandLogo(height: 44),
      ),
      body: brands.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (_, __) => EmptyState(
          icon: Icons.storefront_outlined,
          title: l10n.brandsEmpty,
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
    // Letters present in the catalogue (drives the A–Z chip row).
    final letters = all.map((b) => _initial(b.title)).toSet().toList()..sort();

    final query = _query.trim().toLowerCase();
    // Alphabetical for a directory (the provider sorts by position).
    var filtered = [...all]
      ..sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    if (query.isNotEmpty) {
      filtered = filtered
          .where((b) => b.title.toLowerCase().contains(query))
          .toList();
    }
    if (_letter != null) {
      filtered = filtered.where((b) => _initial(b.title) == _letter).toList();
    }

    final groups = <String, List<Brand>>{};
    for (final b in filtered) {
      groups.putIfAbsent(_initial(b.title), () => <Brand>[]).add(b);
    }
    final keys = groups.keys.toList()..sort();

    final isEn = Localizations.localeOf(context).languageCode == 'en';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Hero.
        Container(
          color: Colors.white,
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 18),
          child: Column(
            children: [
              Text(
                l10n.brandsTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: isEn ? AppTheme.displayFont : null,
                  fontSize: 27,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkHeading,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.brandsSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
            ],
          ),
        ),
        // Search a brand.
        Container(
          color: Colors.white,
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.surfaceMuted,
              hintText: l10n.brandsSearchHint,
              hintStyle: const TextStyle(
                color: AppColors.inkFaint,
                fontSize: 13.5,
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: AppColors.inkFaint,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        // A–Z filter chips.
        Container(
          color: Colors.white,
          padding: const EdgeInsetsDirectional.only(bottom: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.only(start: 16, end: 16),
            child: Row(
              children: [
                _FilterChip(
                  label: l10n.brandsFilterAll,
                  selected: _letter == null,
                  onTap: () => setState(() => _letter = null),
                ),
                for (final letter in letters) ...[
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: letter,
                    selected: _letter == letter,
                    onTap: () => setState(
                      () => _letter = _letter == letter ? null : letter,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Brand grid, grouped by letter (on the light neutral band).
        Container(
          color: const Color(0xFFF9FAFB),
          padding: const EdgeInsetsDirectional.fromSTEB(16, 18, 16, 22),
          child: keys.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: EmptyState(
                    icon: Icons.search_off,
                    title: l10n.brandsEmpty,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < keys.length; i++) ...[
                      if (i > 0) const SizedBox(height: 20),
                      _BrandGroup(letter: keys[i], brands: groups[keys[i]]!),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// A–Z pill: navy when active, hairline-bordered white otherwise.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: selected
              ? null
              : Border.all(color: AppColors.borderDefault),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.26,
            color: selected ? Colors.white : AppColors.inkHeading,
          ),
        ),
      ),
    );
  }
}

/// A lettered group: navy letter header + 2-column rows of brand cards.
class _BrandGroup extends StatelessWidget {
  const _BrandGroup({required this.letter, required this.brands});

  final String letter;
  final List<Brand> brands;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          letter,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.brandPrimary,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < brands.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _BrandTile(brand: brands[i])),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < brands.length
                    ? _BrandTile(brand: brands[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Brand logo card; falls back to the brand name if the logo can't load.
class _BrandTile extends StatelessWidget {
  const _BrandTile({required this.brand});

  final Brand brand;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(AppRoutes.brand, extra: brand),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 104,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 48,
              width: double.infinity,
              child: HubImage(
                url: brand.imageUrl,
                fit: BoxFit.contain,
                placeholder: (_) => const SizedBox.shrink(),
                error: (_) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              brand.title,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.inkHeading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

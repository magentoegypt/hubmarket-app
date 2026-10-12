import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/hub_icons.dart';
import '../../l10n/l10n.dart';
import '../phone/phone_country.dart';
import '../validation/phone.dart';
import 'hub_bottom_sheet.dart';

/// Opens the country list over the page and resolves to the one picked, or
/// null when the sheet is closed without a pick.
///
/// Built from the pieces of the app's other sheets (white, 20 pt top corners,
/// the navy scrim, a 40 x 4 handle, a heading over a rule): the website's phone
/// field has a country dropdown and this is its phone form.
Future<PhoneCountry?> showCountryPicker(
  BuildContext context, {
  required PhoneCountry selected,
}) => showHubBottomSheet<PhoneCountry>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: Colors.white,
  barrierColor: const Color(0x8C0F2144),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (_) => CountryPickerSheet(selected: selected),
);

/// The sheet's content: a search field, the suggested countries, then all of
/// them by name in the language of the app. Searching matches the name in
/// either language, the region code (`ae`) and the calling code (`971`, `+20`).
class CountryPickerSheet extends StatefulWidget {
  const CountryPickerSheet({super.key, required this.selected});

  final PhoneCountry selected;

  /// A row of the list: 52 pt, a flag, the name and the calling code.
  static const double rowHeight = 52;

  @override
  State<CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<CountryPickerSheet> {
  final _search = TextEditingController();
  final _selectedRow = GlobalKey();

  @override
  void initState() {
    super.initState();
    // A country far down the alphabet is on screen when the sheet opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _selectedRow.currentContext;
      if (row != null && mounted) {
        Scrollable.ensureVisible(row, alignment: 0.35);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final query = _search.text;
    final countries = searchPhoneCountries(query, language: language);
    final searching = query.trim().isNotEmpty;
    final suggested = searching
        ? const <PhoneCountry>[]
        : kPreferredPhoneCountries;
    final rest = searching
        ? countries
        : [
            for (final c in countries)
              if (!kPreferredPhoneCountries.contains(c)) c,
          ];

    Widget caption(String text) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: t.micro.copyWith(color: AppColors.inkMuted),
      ),
    );

    Widget row(PhoneCountry country) => _CountryRow(
      key: country == widget.selected ? _selectedRow : null,
      country: country,
      language: language,
      selected: country == widget.selected,
      onTap: () => Navigator.of(context).pop(country),
    );

    return Padding(
      // Lifts the list over the keyboard while the search field has it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The grab handle.
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.phoneCountryPickerTitle,
                        style: t.heading2.copyWith(color: AppColors.inkHeading),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.phoneCountryClose,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      HubIcons.x,
                      size: 22,
                      color: AppColors.inkHeading,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _SearchField(
                controller: _search,
                hint: l10n.phoneCountrySearchHint,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const Divider(height: 1, color: AppColors.borderSubtle),
            Expanded(
              child: rest.isEmpty && suggested.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.phoneCountryNoMatch,
                          textAlign: TextAlign.center,
                          style: t.body.copyWith(color: AppColors.inkMuted),
                        ),
                      ),
                    )
                  : ListView(
                      // All the rows are built (245 plain ones): the selected
                      // one, far down the alphabet, has to exist to be scrolled
                      // to when the sheet opens.
                      scrollCacheExtent: const ScrollCacheExtent.pixels(20000),
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom + 12,
                      ),
                      children: [
                        if (suggested.isNotEmpty) ...[
                          caption(l10n.phoneCountrySuggested),
                          for (final c in suggested) row(c),
                          caption(l10n.phoneCountryAll),
                        ],
                        for (final c in rest) row(c),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The search box: a 44 pt white field with a `search` glyph, as the app's
/// other fields (12 pt corners, the strong outline, navy when focused).
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    OutlineInputBorder outline(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: t.body.copyWith(color: AppColors.inkHeading),
      cursorColor: AppColors.brandPrimary,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        hintText: hint,
        hintStyle: t.body.copyWith(color: AppColors.inkFaint),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        prefixIcon: const Icon(
          HubIcons.search,
          size: 20,
          color: AppColors.inkMuted,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 44),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: AppLocalizations.of(context).clearLabel,
                icon: const Icon(
                  HubIcons.x,
                  size: 18,
                  color: AppColors.inkMuted,
                ),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        border: outline(AppColors.borderStrong, 1),
        enabledBorder: outline(AppColors.borderStrong, 1),
        focusedBorder: outline(AppColors.brandPrimary, 1.5),
      ),
    );
  }
}

class _CountryRow extends StatelessWidget {
  const _CountryRow({
    super.key,
    required this.country,
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final PhoneCountry country;
  final String language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: CountryPickerSheet.rowHeight,
          ),
          color: selected ? AppColors.accentSubtle : null,
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
          child: Row(
            children: [
              Text(country.flag, style: const TextStyle(fontSize: 24, height: 1)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  country.name(language),
                  style: (selected ? t.bodyStrong : t.body).copyWith(
                    color: AppColors.inkHeading,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // The calling code reads left to right in Arabic too.
              Text(
                country.dial,
                textDirection: TextDirection.ltr,
                style: t.body.copyWith(color: AppColors.inkMuted),
              ),
              if (selected) ...[
                const SizedBox(width: 10),
                const Icon(
                  HubIcons.check,
                  size: 18,
                  color: AppColors.accentStrong,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The countries to list for [query], in [language]: all of them by name when
/// the query is empty. Otherwise those whose name in either language, region
/// code or calling code matches, the ones that start with it first.
List<PhoneCountry> searchPhoneCountries(
  String query, {
  required String language,
}) {
  String key(PhoneCountry c) => phoneSortKey(c.name(language));
  final sorted = [...kPhoneCountries]..sort((a, b) {
    final byName = key(a).compareTo(key(b));
    return byName != 0 ? byName : a.code.compareTo(b.code);
  });
  final needle = phoneSortKey(Phone.latinDigits(query).trim());
  if (needle.isEmpty) return sorted;
  final digits = needle.replaceAll(RegExp(r'\D'), '');
  final typedAsCode = digits.isNotEmpty && RegExp(r'^[+\d\s]+$').hasMatch(needle);

  bool starts(PhoneCountry c) =>
      phoneSortKey(c.nameEn).startsWith(needle) ||
      phoneSortKey(c.nameAr).startsWith(needle) ||
      c.code.toLowerCase() == needle ||
      (typedAsCode && c.dialCode.startsWith(digits));
  bool contains(PhoneCountry c) =>
      phoneSortKey(c.nameEn).contains(needle) ||
      phoneSortKey(c.nameAr).contains(needle);

  return [
    ...sorted.where(starts),
    ...sorted.where((c) => !starts(c) && contains(c)),
  ];
}

const String _accented = 'ÅåÀÁÂÃÄàáâãäÇçÈÉÊËèéêëÍÎÏíîïÑñÓÔÕÖóôõöÚÛÜúûüÝýÿ';
const String _plain = 'AaAAAAAaaaaaCcEEEEeeeeIIIiiiNnOOOOooooUUUuuuYyy';

/// [name] as it sorts and as it is searched: lower case, the accents of the
/// Latin names and the marks of the Arabic ones (vowel signs, the forms of the
/// alef, the leading "al") taken off, so "Côte d'Ivoire" sits at C and
/// "الإمارات" at the alef of "الإمارات" rather than after every other "ال".
String phoneSortKey(String name) {
  final out = StringBuffer();
  for (final rune in name.runes) {
    final char = String.fromCharCode(rune);
    final accent = _accented.indexOf(char);
    if (accent >= 0) {
      out.write(_plain[accent].toLowerCase());
    } else if (rune >= 0x064B && rune <= 0x065F || rune == 0x0670) {
      // Arabic vowel signs and the dagger alef.
    } else if (rune == 0x0622 || rune == 0x0623 || rune == 0x0625) {
      out.writeCharCode(0x0627); // alef with madda or hamza -> alef
    } else if (rune == 0x0649) {
      out.writeCharCode(0x064A); // alef maqsura -> ya
    } else if (rune == 0x0629) {
      out.writeCharCode(0x0647); // ta marbuta -> ha
    } else {
      out.write(char.toLowerCase());
    }
  }
  var key = out.toString().trim();
  // "al" before a name is not what it is filed under.
  if (key.length > 3 && key.startsWith(String.fromCharCodes([0x0627, 0x0644]))) {
    key = key.substring(2).trimLeft();
  }
  return key;
}

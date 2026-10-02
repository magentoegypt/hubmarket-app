import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CityLocation {
  const CityLocation(this.id, this.regionId, this.name, this.arabicName);
  final int id;
  final int regionId;
  final String name;
  final String arabicName;
  factory CityLocation.fromJson(Map<String, dynamic> json) => CityLocation(
    int.parse('${json['location_id']}'),
    int.parse('${json['region_id'] ?? 0}'),
    json['name_en'] as String,
    (json['name_ar'] as String?) ?? '',
  );
  String label(bool arabic) =>
      arabic && arabicName.isNotEmpty ? arabicName : name;
}

class CitySelection {
  const CitySelection({
    required this.country,
    this.regionId,
    this.region = '',
    this.city,
    this.locality,
    this.localityRequired = true,
    this.ready = true,
  });
  final String country;
  final int? regionId;
  final String region;
  final CityLocation? city;
  final CityLocation? locality;
  final bool localityRequired, ready;
  bool get valid => ready && city != null && (country != 'AE' || !localityRequired || locality != null);
  String get addressCity => city == null
      ? ''
      : '${city!.name}${locality == null ? '' : ' / ${locality!.name}'}';
}

class CityDirectory {
  CityDirectory(this.baseUrl, this.client);
  final String baseUrl;
  final http.Client client;
  Future<List<CityLocation>> fetch(
    String country,
    String level, {
    int? region,
    int? parent,
  }) async {
    final uri = Uri.parse(baseUrl)
        .resolve('/citymanager/directory/index')
        .replace(
          queryParameters: {
            'country': country,
            'level': level,
            if (region != null) 'region': '$region',
            if (parent != null) 'parent': '$parent',
          },
        );
    final response = await client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw const FormatException('Location service unavailable');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['items'] as List)
        .map((v) => CityLocation.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
  }
}

String locationCountryName(String code, bool arabic) =>
    (arabic
        ? const {
            'AE': 'الإمارات العربية المتحدة',
            'EG': 'مصر',
            'SA': 'السعودية',
            'US': 'الولايات المتحدة',
          }
        : const {
            'AE': 'United Arab Emirates',
            'EG': 'Egypt',
            'SA': 'Saudi Arabia',
            'US': 'United States',
          })[code] ??
    code;

/// Shared by address book, checkout and seller forms. Names remain in Magento's
/// standard address fields; the UAE's internal region mapping is never a picker.
class CityManagerFields extends StatefulWidget {
  const CityManagerFields({
    super.key,
    required this.directory,
    required this.onChanged,
    this.initialCountry = 'AE',
    this.initialRegionId,
    this.initialCity = '',
    this.arabic = false,
  });
  final CityDirectory directory;
  final ValueChanged<CitySelection> onChanged;
  final String initialCountry;
  final int? initialRegionId;
  final String initialCity;
  final bool arabic;
  @override
  State<CityManagerFields> createState() => _CityManagerFieldsState();
}

class _CityManagerFieldsState extends State<CityManagerFields> {
  late String country;
  int? regionId;
  CityLocation? city, locality;
  List<CityLocation> regions = [], cities = [], localities = [];
  bool loading = true;
  bool failed = false;
  int generation = 0;
  String tr(String en, String ar) => widget.arabic ? ar : en;
  @override
  void initState() {
    super.initState();
    country = const ['AE', 'EG', 'SA', 'US'].contains(widget.initialCountry)
        ? widget.initialCountry
        : 'AE';
    regionId = widget.initialRegionId;
    load(preserve: true);
  }

  void notify() {
    String region = '';
    for (final r in regions) {
      if (r.regionId == regionId) region = r.name;
    }
    widget.onChanged(
      CitySelection(
        country: country,
        regionId: country == 'AE' ? city?.regionId : regionId,
        region: region,
        city: city,
        locality: locality,
        localityRequired: localities.isNotEmpty,
        ready: !loading && !failed,
      ),
    );
  }

  Future<void> load({bool preserve = false}) async {
    final ticket = ++generation;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final rr = country == 'AE'
          ? <CityLocation>[]
          : await widget.directory.fetch(country, 'region');
      if (!mounted || ticket != generation) return;
      if (country != 'AE' && !rr.any((r) => r.regionId == regionId)) {
        regionId = null;
      }
      final cc = country == 'AE' || regionId != null
          ? await widget.directory.fetch(
              country,
              'city',
              region: country == 'AE' ? null : regionId,
            )
          : <CityLocation>[];
      if (!mounted || ticket != generation) return;
      CityLocation? selected;
      final parts = preserve ? widget.initialCity.split(' / ') : <String>[];
      for (final c in cc) {
        if (parts.isNotEmpty &&
            (c.name == parts[0] || c.arabicName == parts[0])) {
          selected = c;
        }
      }
      final ll = country == 'AE' && selected != null
          ? await widget.directory.fetch('AE', 'locality', parent: selected.id)
          : <CityLocation>[];
      if (!mounted || ticket != generation) return;
      CityLocation? area;
      for (final l in ll) {
        if (parts.length > 1 &&
            (l.name == parts[1] || l.arabicName == parts[1])) {
          area = l;
        }
      }
      setState(() {
        regions = rr;
        cities = cc;
        localities = ll;
        city = selected;
        locality = area;
        loading = false;
      });
      notify();
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  Future<void> selectCity(CityLocation? value) async {
    final ticket = ++generation;
    setState(() {
      city = value;
      locality = null;
      localities = [];
      failed = false;
      loading = country == 'AE' && value != null;
    });
    notify();
    if (country != 'AE' || value == null) return;
    try {
      final rows = await widget.directory.fetch(
        'AE',
        'locality',
        parent: value.id,
      );
      if (mounted && ticket == generation) {
        setState(() {
          localities = rows;
          loading = false;
        });
        notify();
      }
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  Widget picker(
    String key,
    String label,
    List<CityLocation> rows,
    CityLocation? selected,
    ValueChanged<CityLocation?> change,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: DropdownButtonFormField<int>(
      key: ValueKey('$key-$country-$regionId-${selected?.id}-${rows.length}'),
      initialValue: selected?.id,
      decoration: InputDecoration(labelText: label),
      isExpanded: true,
      items: [
        for (final row in rows)
          DropdownMenuItem(
            value: row.id,
            child: Text(
              row.label(widget.arabic),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: loading
          ? null
          : (id) => change(rows.firstWhere((r) => r.id == id)),
      validator: (_) => key == 'cm-locality' && city != null && rows.isEmpty && !failed && !loading
          ? null
          : selected == null || failed || loading
          ? tr('Please select a valid location', 'يرجى اختيار موقع صحيح')
          : null,
    ),
  );
  @override
  Widget build(BuildContext context) {
    CityLocation? selectedRegion;
    for (final r in regions) {
      if (r.regionId == regionId) selectedRegion = r;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('cm-country-$country'),
          initialValue: country,
          decoration: InputDecoration(labelText: tr('Country', 'الدولة')),
          isExpanded: true,
          items: [
            for (final c in const ['AE', 'EG', 'SA', 'US'])
              DropdownMenuItem(
                value: c,
                child: Text(locationCountryName(c, widget.arabic)),
              ),
          ],
          onChanged: (value) {
            if (value == null || value == country) return;
            setState(() {
              country = value;
              regionId = null;
              city = locality = null;
              regions = [];
              cities = [];
              localities = [];
            });
            notify();
            load();
          },
        ),
        if (country != 'AE')
          picker(
            'cm-region',
            country == 'EG'
                ? tr('Governorate', 'المحافظة')
                : country == 'US'
                ? tr('State', 'الولاية')
                : tr('Region', 'المنطقة'),
            regions,
            selectedRegion,
            (value) {
              setState(() {
                regionId = value?.regionId;
                city = locality = null;
                cities = [];
                localities = [];
              });
              notify();
              load();
            },
          ),
        picker('cm-city', tr('City', 'المدينة'), cities, city, selectCity),
        if (country == 'AE')
          picker('cm-locality', tr('Locality', 'الحي'), localities, locality, (
            value,
          ) {
            setState(() {
              locality = value;
            });
            notify();
          }),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          ),
        if (!loading &&
            country == 'AE' &&
            city != null &&
            localities.isEmpty &&
            !failed)
          Text(
            tr(
              'Locality is optional for this city.',
              'الحي اختياري لهذه المدينة.',
            ),
          ),
        if (failed)
          TextButton(
            onPressed: () => load(preserve: true),
            child: Text(
              tr(
                'Locations could not load. Retry',
                'تعذر تحميل المواقع. إعادة المحاولة',
              ),
            ),
          ),
      ],
    );
  }
}

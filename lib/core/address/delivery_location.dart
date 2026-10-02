import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../features/cart/presentation/cart_controller.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/account/data/account_repository.dart';
import 'city_fields.dart';
import 'city_manager.dart';

// Explicit shopping destination survives navigation and authentication changes.
// The order always uses its independently validated checkout address.
final deliveryLocationProvider =
    NotifierProvider<DeliveryLocation, CitySelection?>(DeliveryLocation.new);

class DeliveryLocation extends Notifier<CitySelection?> {
  bool _explicit = false;
  bool _disposed = false;
  int _generation = 0;
  @override
  CitySelection? build() {
    ref.onDispose(() {
      _disposed = true;
    });
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (!next.isAuthenticated) {
        _generation++;
        if (!_explicit) state = null;
      } else if (previous?.isAuthenticated != true) {
        _restoreSavedArea();
      }
    });
    if (ref.read(authControllerProvider).isAuthenticated) {
      Future.microtask(_restoreSavedArea);
    }
    return null;
  }

  Future<void> _restoreSavedArea() async {
    if (_explicit) return;
    final generation = ++_generation;
    try {
      final addresses = await ref
          .read(accountRepositoryProvider)
          .fetchAddresses();
      final defaults = addresses.where((a) => a.defaultShipping);
      if (defaults.isEmpty ||
          _disposed ||
          generation != _generation ||
          _explicit) {
        return;
      }
      final address = defaults.first;
      final directory = ref.read(cityDirectoryProvider);
      final parts = address.city.split(' / ');
      final cities = await directory.fetch(
        address.countryCode,
        'city',
        region: address.regionId,
      );
      final matches = cities.where(
        (c) => c.name == parts.first || c.arabicName == parts.first,
      );
      if (matches.length != 1) return;
      final city = matches.single;
      final localities = address.countryCode == 'AE'
          ? await directory.fetch('AE', 'locality', parent: city.id)
          : <CityLocation>[];
      final matchingLocalities = localities.where(
        (l) =>
            parts.length == 2 &&
            (l.name == parts[1] || l.arabicName == parts[1]),
      );
      final value = CitySelection(
        country: address.countryCode,
        regionId: city.regionId,
        city: city,
        locality: matchingLocalities.length == 1
            ? matchingLocalities.single
            : null,
        localityRequired: localities.isNotEmpty,
      );
      if (!_disposed &&
          generation == _generation &&
          !_explicit &&
          value.valid) {
        state = value;
      }
    } catch (_) {
      // A stale/incomplete saved address never invents a shopping destination.
    }
  }

  void select(CitySelection value) {
    if (value.valid) {
      _explicit = true;
      _generation++;
      state = value;
    }
  }

  void clear() {
    _explicit = true;
    _generation++;
    state = null;
  }
}

class DeliveryCheck {
  const DeliveryCheck(this.coverage);
  final String coverage;
  bool get blocked => coverage == 'red' || coverage == 'blacklist';
}

class DeliveryService {
  DeliveryService(this.directory, this.client);
  final CityDirectory directory;
  final http.Client client;
  Future<DeliveryCheck> check(CitySelection location, String sku) async {
    final uri = Uri.parse(directory.baseUrl)
        .resolve('/deliveryavailability/check/index')
        .replace(
          queryParameters: {
            'country': location.country,
            'region': '${location.regionId ?? 0}',
            'city': '${location.city!.id}',
            'locality': '${location.locality?.id ?? 0}',
            'sku': sku,
          },
        );
    final response = await client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw const FormatException('Delivery check unavailable');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final coverage = data['coverage'];
    if (!const [
      'green',
      'red',
      'blacklist',
      'unconfigured',
    ].contains(coverage)) {
      throw const FormatException('Invalid delivery response');
    }
    return DeliveryCheck(coverage as String);
  }
}

final deliveryServiceProvider = Provider<DeliveryService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return DeliveryService(ref.watch(cityDirectoryProvider), client);
});

final deliveryCheckProvider = FutureProvider.autoDispose
    .family<DeliveryCheck?, String>((ref, sku) async {
      final location = ref.watch(deliveryLocationProvider);
      if (location == null) return null;
      return ref.watch(deliveryServiceProvider).check(location, sku);
    });

String deliveryMessage(String status, bool ar) => switch (status) {
  'blacklist' =>
    ar ? 'التوصيل غير متاح لهذه المنطقة' : 'Delivery unavailable in this area',
  'red' =>
    ar
        ? 'هذه المنطقة تتطلب عرض سعر للتوصيل'
        : 'This area requires a delivery quotation',
  'green' =>
    ar
        ? 'المنطقة ضمن التغطية. المخزون والرسوم عند إتمام الطلب.'
        : 'Area covered. Stock and fees are checked at checkout.',
  _ =>
    ar
        ? 'لم يتم تأكيد التغطية بعد. تحقق عند إتمام الطلب.'
        : 'Coverage not confirmed yet. Check at checkout.',
};

class DeliveryLocationBar extends ConsumerWidget {
  const DeliveryLocationBar({super.key, this.showCartChecks = false});
  final bool showCartChecks;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(deliveryLocationProvider);
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final label = location == null
        ? (ar ? 'اختر منطقة التوصيل' : 'Choose delivery area')
        : '${location.city!.label(ar)}${location.locality == null ? '' : ' / ${location.locality!.label(ar)}'}';
    final items = showCartChecks && location != null
        ? ref.watch(cartControllerProvider).cart.items
        : null;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.location_on_outlined),
            title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.expand_more),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const _DeliveryPicker(),
            ),
          ),
          if (location != null) DeliveryCoverageText(sku: '*'),
          if (items != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 110),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final item in items)
                      DeliveryCoverageText(sku: item.sku, name: item.name),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DeliveryCoverageText extends ConsumerWidget {
  const DeliveryCoverageText({super.key, required this.sku, this.name});
  final String sku;
  final String? name;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return ref
        .watch(deliveryCheckProvider(sku))
        .when(
          data: (result) => result == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '${name == null ? '' : '$name: '}${deliveryMessage(result.coverage, ar)}',
                    style: TextStyle(
                      color: result.blocked
                          ? Theme.of(context).colorScheme.error
                          : null,
                      fontSize: 12,
                    ),
                  ),
                ),
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (_, stack) => TextButton(
            onPressed: () => ref.invalidate(deliveryCheckProvider(sku)),
            child: Text(
              ar
                  ? 'تعذر التحقق من التوصيل. أعد المحاولة'
                  : 'Delivery check unavailable. Retry',
            ),
          ),
        );
  }
}

Future<void> showDeliveryPicker(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _DeliveryPicker(),
    );

class _DeliveryPicker extends ConsumerStatefulWidget {
  const _DeliveryPicker();
  @override
  ConsumerState<_DeliveryPicker> createState() => _DeliveryPickerState();
}

class _DeliveryPickerState extends ConsumerState<_DeliveryPicker> {
  CitySelection? selection;
  @override
  Widget build(BuildContext context) {
    final previous = ref.read(deliveryLocationProvider);
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ar ? 'منطقة التوصيل' : 'Delivery area',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            CityManagerFields(
              directory: ref.read(cityDirectoryProvider),
              initialCountry: previous?.country ?? 'AE',
              initialRegionId: previous?.regionId,
              initialCity: previous?.addressCity ?? '',
              arabic: ar,
              onChanged: (value) => setState(() => selection = value),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: selection?.valid == true
                  ? () {
                      ref
                          .read(deliveryLocationProvider.notifier)
                          .select(selection!);
                      Navigator.pop(context);
                    }
                  : null,
              child: Text(ar ? 'استخدم هذه المنطقة' : 'Use this area'),
            ),
            TextButton(
              onPressed: () {
                ref.read(deliveryLocationProvider.notifier).clear();
                Navigator.pop(context);
              },
              child: Text(ar ? 'تصفح جميع المنتجات' : 'Browse all products'),
            ),
          ],
        ),
      ),
    );
  }
}

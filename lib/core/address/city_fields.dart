import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../widgets/address_form.dart';
import 'city_manager.dart';

final cityDirectoryProvider = Provider<CityDirectory>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return CityDirectory(ref.watch(appConfigProvider).graphqlEndpoint, client);
});

class AddressCityFields extends ConsumerWidget {
  const AddressCityFields({super.key, required this.controller});
  final AddressFormController controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) => CityManagerFields(
    directory: ref.watch(cityDirectoryProvider),
    initialCountry: controller.country.value,
    initialRegionId: controller.regionId.value,
    initialCity: controller.area.text,
    arabic: Localizations.localeOf(context).languageCode == 'ar',
    onChanged: (selection) {
      controller.country.value = selection.country;
      controller.regionId.value = selection.regionId;
      controller.region.text = selection.region;
      controller.area.text = selection.addressCity;
    },
  );
}

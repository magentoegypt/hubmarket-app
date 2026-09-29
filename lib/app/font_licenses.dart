import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The bundled fonts and their SIL Open Font License texts
/// (`assets/fonts/licenses/`, copied from google/fonts next to each family).
/// The OFL requires the licence to travel with the fonts; registering it puts
/// each family on the licences page beside the package licences.
const Map<String, String> bundledFontLicenses = <String, String>{
  'DM Sans': 'assets/fonts/licenses/DMSans-OFL.txt',
  'Tajawal': 'assets/fonts/licenses/Tajawal-OFL.txt',
  'Playfair Display': 'assets/fonts/licenses/PlayfairDisplay-OFL.txt',
};

/// One licence entry per bundled font family, read from [bundle].
Stream<LicenseEntry> fontLicenseEntries({AssetBundle? bundle}) async* {
  final assets = bundle ?? rootBundle;
  for (final entry in bundledFontLicenses.entries) {
    final text = await assets.loadString(entry.value);
    yield LicenseEntryWithLineBreaks(<String>[entry.key], text);
  }
}

/// Adds the bundled fonts' licences to the [LicenseRegistry]. The texts are
/// read lazily — only when something (the licences page) asks for them.
void registerFontLicenses() => LicenseRegistry.addLicense(fontLicenseEntries);

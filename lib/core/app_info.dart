import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The app's version string, e.g. "0.1.1 (2)", read from the build at runtime
/// (reflects the pubspec `version:` of the installed build). Null when the
/// platform plugin is unavailable (e.g. in a plain widget test).
final appVersionProvider = FutureProvider<String?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version} (${info.buildNumber})';
  } catch (_) {
    return null;
  }
});

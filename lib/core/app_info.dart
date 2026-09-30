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

/// The build's semantic version alone, e.g. "1.0.0" — what the backend's
/// version policy (`hmAppConfig.version`) compares against. Null when the
/// platform plugin is unavailable, which never triggers an update prompt.
final appSemverProvider = FutureProvider<String?>((ref) => readAppSemver());

/// The installed build's semantic version (pubspec `version:` without the
/// build number), e.g. "1.0.0"; null when the platform plugin is unavailable.
/// Also names the version in the User-Agent (`AppConfig.forVersion`).
Future<String?> readAppSemver() async {
  try {
    final version = (await PackageInfo.fromPlatform()).version.trim();
    return version.isEmpty ? null : version;
  } catch (_) {
    return null;
  }
}

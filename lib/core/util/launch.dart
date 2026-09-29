import 'package:url_launcher/url_launcher.dart';

/// Opens an external [uri] (web/email/phone) in the platform handler. Returns
/// false when no handler is available, so callers can surface a friendly
/// message instead of throwing. Centralised so footer links + Help contact
/// share one code path (and one set of platform query-scheme declarations).
Future<bool> launchExternalUri(Uri uri) async {
  try {
    if (!await canLaunchUrl(uri)) return false;
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Convenience: a `mailto:` link to [address].
Uri mailtoUri(String address) => Uri(scheme: 'mailto', path: address);

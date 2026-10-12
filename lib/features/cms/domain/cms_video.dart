/// The page a video embed plays on, or null when [src] is not an embed the app
/// will show.
///
/// A seller pastes a player into a product description (Page Builder's Video
/// element writes `<iframe src="https://www.youtube.com/embed/ID?autoplay=1">`).
/// The app never loads that player inside itself: it draws a card, and a tap
/// hands the provider's own watch page to the platform. So only the providers
/// sellers actually use are accepted (YouTube, Vimeo), the link is rebuilt from
/// the video's id alone — the embed's autoplay, mute and tracking parameters are
/// dropped — and any other `<iframe>` (a map, a form, an advert) stays out.
String? embeddedVideoUrl(String? src) {
  var raw = (src ?? '').trim();
  if (raw.startsWith('//')) raw = 'https:$raw';
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasAuthority) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final host = uri.host.toLowerCase();
  final bare = host.startsWith('www.') ? host.substring(4) : host;
  final path = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  switch (bare) {
    case 'youtube.com' || 'm.youtube.com' || 'youtube-nocookie.com':
      return _youtube(uri, path);
    case 'youtu.be':
      return path.isEmpty ? null : _youtubeWatch(path.first, uri);
    case 'vimeo.com':
      return _vimeo(path, hash: null);
    case 'player.vimeo.com':
      return path.length >= 2 && path.first == 'video'
          ? _vimeo([path[1]], hash: uri.queryParameters['h'])
          : null;
  }
  return null;
}

/// YouTube ids are 11 characters of this alphabet; a little slack is allowed.
final RegExp _youtubeId = RegExp(r'^[A-Za-z0-9_-]{6,20}$');

/// A playlist's id is longer (`PL` and 32 more).
final RegExp _youtubeList = RegExp(r'^[A-Za-z0-9_-]{10,64}$');

String? _youtube(Uri uri, List<String> path) {
  if (path.isEmpty) return null;
  switch (path.first) {
    case 'embed':
      if (path.length < 2) return null;
      if (path[1] == 'videoseries') {
        final list = uri.queryParameters['list'];
        return list != null && _youtubeList.hasMatch(list)
            ? 'https://www.youtube.com/playlist?list=$list'
            : null;
      }
      return _youtubeWatch(path[1], uri);
    case 'v' || 'shorts' || 'live':
      return path.length < 2 ? null : _youtubeWatch(path[1], uri);
    case 'watch':
      return _youtubeWatch(uri.queryParameters['v'], uri);
  }
  // A channel, a results page, … is a place, not a video.
  return null;
}

String? _youtubeWatch(String? id, Uri uri) {
  if (id == null || !_youtubeId.hasMatch(id)) return null;
  final start = int.tryParse(
    uri.queryParameters['start'] ?? uri.queryParameters['t'] ?? '',
  );
  final at = start != null && start > 0 ? '&t=${start}s' : '';
  return 'https://www.youtube.com/watch?v=$id$at';
}

/// `vimeo.com/<id>`, `vimeo.com/<id>/<hash>` (unlisted), `vimeo.com/channels/x/<id>`
/// and `player.vimeo.com/video/<id>?h=<hash>`.
String? _vimeo(List<String> path, {required String? hash}) {
  final at = path.indexWhere((s) => RegExp(r'^\d{3,}$').hasMatch(s));
  if (at < 0) return null;
  final id = path[at];
  final unlisted = hash ?? (at + 1 < path.length ? path[at + 1] : null);
  return unlisted != null && RegExp(r'^[0-9a-fA-F]{6,}$').hasMatch(unlisted)
      ? 'https://vimeo.com/$id/$unlisted'
      : 'https://vimeo.com/$id';
}

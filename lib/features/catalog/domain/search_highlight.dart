/// A `[start, end)` slice of a string.
typedef TextSlice = ({int start, int end});

/// The tags the app asks Algolia to wrap matched words in (InstantSearch's
/// own), chosen so they can't be mistaken for anything in a product name.
const String kHighlightPreTag = '__ais-highlight__';
const String kHighlightPostTag = '__/ais-highlight__';

/// Reads an Algolia `_highlightResult` value — the attribute's text with every
/// matched word wrapped in [pre] … [post] — into the plain text and the
/// matched slices. Algolia marks prefix, typo and plural matches too, which a
/// literal comparison ([searchMatchSlices]) can't. An unclosed tag leaves the
/// rest of the text plain.
({String text, List<TextSlice> matches}) parseHighlighted(
  String value, {
  String pre = kHighlightPreTag,
  String post = kHighlightPostTag,
}) {
  final text = StringBuffer();
  final matches = <TextSlice>[];
  var at = 0;
  while (at < value.length) {
    final open = value.indexOf(pre, at);
    if (open < 0) {
      text.write(value.substring(at));
      break;
    }
    text.write(value.substring(at, open));
    final close = value.indexOf(post, open + pre.length);
    if (close < 0) {
      text.write(value.substring(open + pre.length));
      break;
    }
    final start = text.length;
    text.write(value.substring(open + pre.length, close));
    if (text.length > start) matches.add((start: start, end: text.length));
    at = close + post.length;
  }
  return (text: text.toString(), matches: List.unmodifiable(matches));
}

/// Where the words of [query] occur in [text], case-insensitively: sorted,
/// merged slices — what a search hit draws in bold when the engine didn't
/// say (the GraphQL fallback; Algolia hits carry their own, see
/// [parseHighlighted]).
///
/// Only literal occurrences are marked, so a prefix or typo match renders
/// plain, which is honest. Returns nothing when lower-casing changes the
/// text's length (a few non-ASCII letters do), since the offsets would drift.
List<TextSlice> searchMatchSlices(String text, String query) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toSet();
  if (words.isEmpty || text.isEmpty) return const <TextSlice>[];
  final haystack = text.toLowerCase();
  if (haystack.length != text.length) return const <TextSlice>[];

  final found = <TextSlice>[];
  for (final word in words) {
    var from = 0;
    while (from < haystack.length) {
      final at = haystack.indexOf(word, from);
      if (at < 0) break;
      found.add((start: at, end: at + word.length));
      from = at + word.length;
    }
  }
  found.sort((a, b) => a.start.compareTo(b.start));

  final merged = <TextSlice>[];
  for (final slice in found) {
    final last = merged.isEmpty ? null : merged.last;
    if (last != null && slice.start <= last.end) {
      merged[merged.length - 1] = (
        start: last.start,
        end: slice.end > last.end ? slice.end : last.end,
      );
    } else {
      merged.add(slice);
    }
  }
  return merged;
}

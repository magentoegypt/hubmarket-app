/// A `[start, end)` slice of a string.
typedef TextSlice = ({int start, int end});

/// Where the words of [query] occur in [text], case-insensitively: sorted,
/// merged slices — what a search hit draws in bold.
///
/// Only literal occurrences are marked. Algolia also matches prefixes and
/// typos, so a hit can come back with nothing to highlight; it then renders
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

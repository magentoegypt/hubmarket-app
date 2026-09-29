import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// A run of text inside a paragraph, heading, list item or table cell, with
/// the formatting the renderer supports. `\n` stands for a `<br>`.
class CmsInline {
  const CmsInline(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.href,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;

  /// The link target when the run sits inside an `<a href>`.
  final String? href;

  bool sameStyleAs(CmsInline other) =>
      bold == other.bold &&
      italic == other.italic &&
      underline == other.underline &&
      href == other.href;

  CmsInline withText(String value) => CmsInline(
    value,
    bold: bold,
    italic: italic,
    underline: underline,
    href: href,
  );
}

/// One block of a CMS page, as the native renderer draws it.
sealed class CmsBlock {
  const CmsBlock();
}

class CmsHeading extends CmsBlock {
  const CmsHeading(
    this.level,
    this.inlines, {
    this.anchor,
    this.attributes = const <String, String>{},
  });

  /// 1–6, from `<h1>`…`<h6>`.
  final int level;
  final List<CmsInline> inlines;

  /// The heading's `id` (or that of an `<a name|id>` inside it) — the target
  /// of an in-page `#anchor` link.
  final String? anchor;

  /// The element's attributes, e.g. the FAQ convention's `data-icon`.
  final Map<String, String> attributes;

  String get text => CmsDocument.inlineText(inlines);
}

class CmsParagraph extends CmsBlock {
  const CmsParagraph(this.inlines);
  final List<CmsInline> inlines;

  String get text => CmsDocument.inlineText(inlines);
}

class CmsList extends CmsBlock {
  const CmsList({required this.ordered, required this.items});

  final bool ordered;

  /// Each item's own blocks — nested lists stay nested.
  final List<List<CmsBlock>> items;
}

class CmsImage extends CmsBlock {
  const CmsImage({
    required this.src,
    this.alt = '',
    this.width,
    this.height,
    this.href,
  });

  final String src;
  final String alt;
  final double? width;
  final double? height;

  /// Set when the image is wrapped in a link.
  final String? href;
}

class CmsTableCell {
  const CmsTableCell(this.inlines, {this.header = false});
  final List<CmsInline> inlines;
  final bool header;
}

class CmsTable extends CmsBlock {
  const CmsTable({required this.rows, this.caption = const <CmsInline>[]});
  final List<CmsInline> caption;
  final List<List<CmsTableCell>> rows;

  int get columnCount =>
      rows.fold<int>(0, (max, r) => r.length > max ? r.length : max);
}

class CmsQuote extends CmsBlock {
  const CmsQuote(this.children);
  final List<CmsBlock> children;
}

class CmsRule extends CmsBlock {
  const CmsRule();
}

/// A jump target for the section chips at the top of a content page.
typedef CmsSection = ({int index, String title});

/// Turns storefront CMS HTML (a page's `content`, a block's `content`) into
/// [CmsBlock]s the app draws with native widgets — the same markup the
/// website renders, so admins edit a page once for both.
///
/// Supported: headings, paragraphs, line breaks, ordered/unordered (nested)
/// lists, links, bold/italic/underline, images, simple tables, quotes and
/// rules. Layout wrappers (`div`, `section`, Page Builder rows…) are
/// flattened; scripts, styles, forms and embeds are dropped rather than shown
/// half-rendered.
abstract final class CmsDocument {
  static List<CmsBlock> parse(String html) {
    if (html.trim().isEmpty) return const <CmsBlock>[];
    return _Parser().blocks(html_parser.parseFragment(html).nodes);
  }

  /// The text of [inlines], with `<br>`s as newlines.
  static String inlineText(List<CmsInline> inlines) =>
      inlines.map((i) => i.text).join().trim();

  /// All text of [blocks], whitespace-collapsed — for searching.
  static String plainText(List<CmsBlock> blocks) {
    final out = StringBuffer();
    void walk(List<CmsBlock> list) {
      for (final b in list) {
        switch (b) {
          case CmsHeading():
            out.write('${b.text} ');
          case CmsParagraph():
            out.write('${b.text} ');
          case CmsList():
            for (final item in b.items) {
              walk(item);
            }
          case CmsTable():
            out.write('${inlineText(b.caption)} ');
            for (final row in b.rows) {
              for (final cell in row) {
                out.write('${inlineText(cell.inlines)} ');
              }
            }
          case CmsQuote():
            walk(b.children);
          case CmsImage():
            out.write('${b.alt} ');
          case CmsRule():
            break;
        }
      }
    }

    walk(blocks);
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// The page's sections for the jump chips: its `<h2>`s, or its `<h3>`s
  /// when it has fewer than two `<h2>`. Empty when there aren't at least two
  /// of either — one chip is not navigation.
  static List<CmsSection> sections(List<CmsBlock> blocks) {
    for (final level in const [2, 3]) {
      final found = <CmsSection>[];
      for (var i = 0; i < blocks.length; i++) {
        final b = blocks[i];
        if (b is CmsHeading && b.level == level && b.text.isNotEmpty) {
          found.add((index: i, title: b.text));
        }
      }
      if (found.length >= 2) return found;
    }
    return const <CmsSection>[];
  }

  /// Index of the heading an in-page `#anchor` link points to, or null.
  static int? anchorIndex(List<CmsBlock> blocks, String anchor) {
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b is CmsHeading && b.anchor == anchor) return i;
    }
    return null;
  }
}

class _Style {
  const _Style({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.href,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final String? href;

  _Style copyWith({bool? bold, bool? italic, bool? underline, String? href}) =>
      _Style(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        href: href ?? this.href,
      );

  CmsInline run(String text) => CmsInline(
    text,
    bold: bold,
    italic: italic,
    underline: underline,
    href: href,
  );
}

class _Parser {
  /// Never rendered: code, forms and embeds a native page can't honour.
  static const Set<String> _dropped = {
    'script', 'style', 'noscript', 'template', 'head', 'meta', 'link',
    'form', 'input', 'button', 'select', 'option', 'textarea', 'label',
    'iframe', 'object', 'embed', 'video', 'audio', 'canvas', 'svg', 'map',
  };

  /// Layout wrappers whose children are laid out as blocks in their place.
  static const Set<String> _containers = {
    'div', 'section', 'article', 'main', 'header', 'footer', 'aside', 'nav',
    'figure', 'figcaption', 'center', 'details', 'summary', 'dl', 'dt', 'dd',
    'address', 'body', 'html', 'tbody', 'thead', 'tfoot', 'li',
  };

  static const Set<String> _blockTags = {
    'p', 'ul', 'ol', 'table', 'img', 'hr', 'blockquote', 'h1', 'h2', 'h3',
    'h4', 'h5', 'h6', 'pre', ..._containers,
  };

  List<CmsBlock> blocks(List<dom.Node> nodes) {
    final out = <CmsBlock>[];
    final pending = <CmsInline>[];

    void flush() {
      final runs = _tidy(pending);
      if (runs.isNotEmpty) out.add(CmsParagraph(runs));
      pending.clear();
    }

    for (final node in nodes) {
      if (node is dom.Text) {
        pending.addAll(_textRuns(node.text, const _Style()));
        continue;
      }
      if (node is! dom.Element) continue;
      final tag = node.localName ?? '';
      if (_dropped.contains(tag)) continue;
      if (tag == 'br') {
        pending.add(const CmsInline('\n'));
        continue;
      }
      final level = _headingLevel(tag);
      if (level != null) {
        flush();
        final runs = _tidy(_inlines(node.nodes, const _Style()));
        if (runs.isNotEmpty) {
          out.add(
            CmsHeading(
              level,
              runs,
              anchor: _anchorOf(node),
              attributes: {
                for (final e in node.attributes.entries) '${e.key}': e.value,
              },
            ),
          );
        }
        continue;
      }
      switch (tag) {
        case 'p' || 'pre':
          flush();
          out.addAll(_paragraph(node));
        case 'ul' || 'ol':
          flush();
          final items = <List<CmsBlock>>[
            for (final li in node.children)
              if (li.localName == 'li') blocks(li.nodes),
          ].where((item) => item.isNotEmpty).toList();
          if (items.isNotEmpty) {
            out.add(CmsList(ordered: tag == 'ol', items: items));
          }
        case 'table':
          flush();
          final table = _table(node);
          if (table != null) out.add(table);
        case 'img':
          flush();
          final image = _image(node);
          if (image != null) out.add(image);
        case 'hr':
          flush();
          out.add(const CmsRule());
        case 'blockquote':
          flush();
          final inner = blocks(node.nodes);
          if (inner.isNotEmpty) out.add(CmsQuote(inner));
        case 'a' when _hasBlockChild(node):
          // A linked banner (`<a><img></a>`, Page Builder): keep the image and
          // its link, lay the rest out as blocks.
          flush();
          final href = node.attributes['href']?.trim();
          for (final b in blocks(node.nodes)) {
            out.add(
              b is CmsImage && href != null && href.isNotEmpty
                  ? CmsImage(
                      src: b.src,
                      alt: b.alt,
                      width: b.width,
                      height: b.height,
                      href: href,
                    )
                  : b,
            );
          }
        default:
          if (_containers.contains(tag)) {
            flush();
            out.addAll(blocks(node.nodes));
          } else {
            pending.addAll(_inlines([node], const _Style()));
          }
      }
    }
    flush();
    return out;
  }

  List<CmsBlock> _paragraph(dom.Element p) {
    final out = <CmsBlock>[];
    final runs = _tidy(_inlines(p.nodes, const _Style()));
    if (runs.isNotEmpty) out.add(CmsParagraph(runs));
    // Images inside a paragraph become blocks of their own, after its text.
    for (final img in p.querySelectorAll('img')) {
      final image = _image(img);
      if (image != null) out.add(image);
    }
    return out;
  }

  List<CmsInline> _inlines(List<dom.Node> nodes, _Style style) {
    final out = <CmsInline>[];
    for (final node in nodes) {
      if (node is dom.Text) {
        out.addAll(_textRuns(node.text, style));
        continue;
      }
      if (node is! dom.Element) continue;
      final tag = node.localName ?? '';
      if (_dropped.contains(tag) || tag == 'img') continue;
      if (tag == 'br') {
        out.add(style.run('\n'));
        continue;
      }
      var s = style;
      switch (tag) {
        case 'b' || 'strong' || 'th':
          s = s.copyWith(bold: true);
        case 'i' || 'em' || 'cite':
          s = s.copyWith(italic: true);
        case 'u' || 'ins':
          s = s.copyWith(underline: true);
        case 'a':
          final href = node.attributes['href']?.trim();
          if (href != null && href.isNotEmpty) s = s.copyWith(href: href);
      }
      // Block markup nested in inline context (a `<p>` inside an `<li>` that
      // is being flattened) still breaks the line.
      final blockish = _blockTags.contains(tag);
      if (blockish && out.isNotEmpty) out.add(style.run('\n'));
      out.addAll(_inlines(node.nodes, s));
      if (blockish) out.add(style.run('\n'));
    }
    return out;
  }

  Iterable<CmsInline> _textRuns(String text, _Style style) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ');
    return collapsed.isEmpty ? const <CmsInline>[] : [style.run(collapsed)];
  }

  /// Trims each line, collapses doubled spaces and line breaks, merges runs
  /// of equal style and drops empty ones. Whitespace-only input yields `[]`.
  List<CmsInline> _tidy(List<CmsInline> runs) {
    // Split every run at its line breaks so lines can be trimmed.
    final pieces = <CmsInline>[];
    for (final r in runs) {
      final parts = r.text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) pieces.add(r.withText('\n'));
        if (parts[i].isNotEmpty) pieces.add(r.withText(parts[i]));
      }
    }
    final out = <CmsInline>[];
    var atLineStart = true;
    for (final p in pieces) {
      if (p.text == '\n') {
        // No leading breaks and never two in a row.
        if (out.isEmpty || out.last.text.endsWith('\n')) continue;
        _trimTrailingSpace(out);
        if (out.isEmpty) continue;
        out.add(p);
        atLineStart = true;
        continue;
      }
      var text = p.text;
      if (atLineStart) text = text.trimLeft();
      if (text.isEmpty) continue;
      if (!atLineStart &&
          text.startsWith(' ') &&
          out.isNotEmpty &&
          out.last.text.endsWith(' ')) {
        text = text.substring(1);
        if (text.isEmpty) continue;
      }
      atLineStart = false;
      if (out.isNotEmpty && out.last.sameStyleAs(p) && out.last.text != '\n') {
        out[out.length - 1] = out.last.withText(out.last.text + text);
      } else {
        out.add(p.withText(text));
      }
    }
    while (out.isNotEmpty && out.last.text == '\n') {
      out.removeLast();
    }
    _trimTrailingSpace(out);
    return out;
  }

  void _trimTrailingSpace(List<CmsInline> out) {
    while (out.isNotEmpty) {
      final trimmed = out.last.text.trimRight();
      if (trimmed.isEmpty) {
        out.removeLast();
        continue;
      }
      out[out.length - 1] = out.last.withText(trimmed);
      return;
    }
  }

  CmsTable? _table(dom.Element table) {
    final rows = <List<CmsTableCell>>[];
    for (final tr in table.querySelectorAll('tr')) {
      final cells = <CmsTableCell>[
        for (final cell in tr.children)
          if (cell.localName == 'td' || cell.localName == 'th')
            CmsTableCell(
              _tidy(_inlines(cell.nodes, const _Style())),
              header: cell.localName == 'th',
            ),
      ];
      if (cells.any((c) => c.inlines.isNotEmpty)) rows.add(cells);
    }
    if (rows.isEmpty) return null;
    final caption = table.querySelector('caption');
    return CmsTable(
      rows: rows,
      caption: caption == null
          ? const <CmsInline>[]
          : _tidy(_inlines(caption.nodes, const _Style(bold: true))),
    );
  }

  CmsImage? _image(dom.Element img) {
    final src = (img.attributes['src'] ?? img.attributes['data-src'] ?? '')
        .trim();
    if (src.isEmpty || src.startsWith('data:')) return null;
    return CmsImage(
      src: src,
      alt: (img.attributes['alt'] ?? '').trim(),
      width: _dimension(img.attributes['width']),
      height: _dimension(img.attributes['height']),
    );
  }

  double? _dimension(String? raw) {
    final value = double.tryParse((raw ?? '').replaceAll('px', '').trim());
    return (value == null || value <= 0) ? null : value;
  }

  int? _headingLevel(String tag) {
    if (tag.length != 2 || tag[0] != 'h') return null;
    final level = int.tryParse(tag[1]);
    return (level != null && level >= 1 && level <= 6) ? level : null;
  }

  String? _anchorOf(dom.Element heading) {
    final id = heading.id.trim();
    if (id.isNotEmpty) return id;
    for (final inner in heading.querySelectorAll('*')) {
      final value = (inner.id.isNotEmpty
              ? inner.id
              : (inner.localName == 'a' ? inner.attributes['name'] ?? '' : ''))
          .trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  bool _hasBlockChild(dom.Element element) => element.children.any(
    (c) => _blockTags.contains(c.localName) || c.localName == 'img',
  );
}

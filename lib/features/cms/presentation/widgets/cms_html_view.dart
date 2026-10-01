import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/util/media.dart';
import '../../../../core/widgets/network_image.dart';
import '../../domain/cms_document.dart';

/// Draws parsed CMS content ([CmsDocument.parse]) with native widgets.
///
/// Links are reported through [onLink] with their raw `href`; the caller
/// decides where they go (in-page anchor, an app screen, the browser).
/// [blockKeys] attaches a key to top-level blocks by index so a screen can
/// scroll to a heading.
///
/// [page] is the type of Figma 28's content page: the text in EN/Body, the
/// paragraphs before the first heading in ink and the rest in `text/subtle`,
/// headings in EN/Title with 6 px under them and 16 between sections. Without
/// it the content keeps the compact look the Home, the store pages and the
/// return form give it.
class CmsHtmlView extends StatefulWidget {
  const CmsHtmlView({
    super.key,
    required this.blocks,
    required this.onLink,
    this.blockKeys = const <int, GlobalKey>{},
    this.mediaBase = '',
    this.compact = false,
    this.page = false,
  });

  final List<CmsBlock> blocks;
  final ValueChanged<String> onLink;
  final Map<int, GlobalKey> blockKeys;

  /// Base URL relative image paths resolve against (the storefront origin).
  final String mediaBase;

  /// Tighter type and spacing, for FAQ answers inside an accordion.
  final bool compact;

  /// The content page's type and rhythm (see the class doc).
  final bool page;

  @override
  State<CmsHtmlView> createState() => _CmsHtmlViewState();
}

class _CmsHtmlViewState extends State<CmsHtmlView> {
  /// Link recognizers of the current build, disposed before the next one.
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  double get _bodySize => widget.compact ? 14 : 15;

  TextStyle _body(BuildContext context) => widget.page
      ? AppTextStyles.of(context).body.copyWith(
          color: context.isDarkMode
              ? context.scaffoldMuted
              : AppColors.inkSubtle,
        )
      : TextStyle(
          fontSize: _bodySize,
          height: 1.5,
          color: context.scaffoldMuted,
        );

  /// The index of the first heading among the top-level blocks, or -1.
  int _firstHeading = -1;

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final blocks = widget.blocks;
    _firstHeading = blocks.indexWhere((b) => b is CmsHeading);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++)
          KeyedSubtree(
            key: widget.blockKeys[i],
            child: Padding(
              padding: EdgeInsets.only(
                top: !widget.page && blocks[i] is CmsHeading && i > 0 ? 8 : 0,
                bottom: i == blocks.length - 1 ? 0 : _gapAfter(blocks, i),
              ),
              child: _block(context, blocks[i], depth: 0, index: i),
            ),
          ),
      ],
    );
  }

  double _gapAfter(List<CmsBlock> blocks, int i) {
    final block = blocks[i];
    if (widget.page) {
      // Figma 28: a heading sits 6 above its text, sections 16 apart.
      if (block is CmsHeading) return 6;
      return blocks[i + 1] is CmsHeading ? 16 : 12;
    }
    return switch (block) {
      CmsHeading() => widget.compact ? 4 : 8,
      CmsTable() => 16,
      _ => widget.compact ? 8 : 12,
    };
  }

  Widget _block(
    BuildContext context,
    CmsBlock block, {
    required int depth,
    int? index,
  }) {
    switch (block) {
      case CmsHeading():
        return Semantics(
          header: true,
          child: Text.rich(
            _span(
              context,
              block.inlines,
              widget.page
                  ? _pageHeading(context, block.level)
                  : TextStyle(
                      fontSize: _headingSize(block.level),
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: context.scaffoldHeading,
                    ),
            ),
          ),
        );
      case CmsParagraph():
        // The page's opening lines, before its first heading, are ink.
        final lead =
            widget.page &&
            depth == 0 &&
            index != null &&
            (_firstHeading == -1 || index < _firstHeading);
        return Text.rich(
          _span(
            context,
            block.inlines,
            lead
                ? _body(context).copyWith(color: context.scaffoldHeading)
                : _body(context),
          ),
        );
      case CmsList():
        return _list(context, block, depth: depth);
      case CmsImage():
        return _image(block);
      case CmsTable():
        return _table(context, block);
      case CmsQuote():
        return Container(
          padding: const EdgeInsetsDirectional.only(start: 12),
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(color: context.hairline, width: 3),
            ),
          ),
          child: _column(context, block.children, depth: depth),
        );
      case CmsRule():
        return Divider(height: 1, thickness: 1, color: context.hairline);
    }
  }

  /// EN/Heading 2 for a top heading, EN/Title for the sections (h2, h3),
  /// EN/Body Strong below.
  TextStyle _pageHeading(BuildContext context, int level) {
    final t = AppTextStyles.of(context);
    final base = switch (level) {
      1 => t.heading2,
      2 || 3 => t.title,
      _ => t.bodyStrong,
    };
    return base.copyWith(color: context.scaffoldHeading);
  }

  double _headingSize(int level) {
    final base = switch (level) {
      1 => 22.0,
      2 => 18.0,
      3 => 16.0,
      _ => 15.0,
    };
    return widget.compact ? base - 1 : base;
  }

  Widget _column(
    BuildContext context,
    List<CmsBlock> blocks, {
    required int depth,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < blocks.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i == blocks.length - 1 ? 0 : 6),
          child: _block(context, blocks[i], depth: depth),
        ),
    ],
  );

  Widget _list(BuildContext context, CmsList list, {required int depth}) {
    final marker = _body(context).copyWith(color: context.scaffoldHeading);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < list.items.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == list.items.length - 1 ? 0 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: list.ordered ? 26 : 18,
                  child: Text(
                    list.ordered ? '${i + 1}.' : (depth.isEven ? '•' : '◦'),
                    style: marker,
                  ),
                ),
                Expanded(
                  child: _column(context, list.items[i], depth: depth + 1),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _image(CmsImage image) {
    final url = resolveMediaUrl(image.src, widget.mediaBase);
    Widget child = HubImage(
      url: url,
      fit: BoxFit.contain,
      semanticLabel: image.alt.isEmpty ? null : image.alt,
    );
    final w = image.width;
    final h = image.height;
    child = (w != null && h != null)
        ? AspectRatio(aspectRatio: w / h, child: child)
        : SizedBox(height: 180, child: child);
    child = ClipRRect(borderRadius: BorderRadius.circular(12), child: child);
    final href = image.href;
    if (href == null) return child;
    return GestureDetector(onTap: () => widget.onLink(href), child: child);
  }

  Widget _table(BuildContext context, CmsTable table) {
    final columns = table.columnCount;
    final cellStyle = TextStyle(
      fontSize: 13,
      height: 1.4,
      color: context.scaffoldMuted,
    );
    Widget cell(CmsTableCell? c) => Padding(
      padding: const EdgeInsets.all(8),
      child: c == null
          ? const SizedBox.shrink()
          : Text.rich(
              _span(
                context,
                c.inlines,
                c.header
                    ? cellStyle.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.scaffoldHeading,
                      )
                    : cellStyle,
              ),
            ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrow tables share the width; wide ones scroll sideways with a
        // readable minimum per column.
        const minColumn = 120.0;
        final fits = columns * minColumn <= constraints.maxWidth;
        final grid = Table(
          defaultColumnWidth: fits
              ? const FlexColumnWidth()
              : const FixedColumnWidth(minColumn + 20),
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          border: TableBorder.all(
            color: context.hairline,
            borderRadius: BorderRadius.circular(8),
          ),
          children: [
            for (final row in table.rows)
              TableRow(
                decoration: row.isNotEmpty && row.every((c) => c.header)
                    ? BoxDecoration(
                        color: context.isDarkMode
                            ? Colors.white10
                            : AppColors.surfaceSubtle,
                      )
                    : null,
                children: [
                  for (var c = 0; c < columns; c++)
                    cell(c < row.length ? row[c] : null),
                ],
              ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (table.caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text.rich(
                  _span(
                    context,
                    table.caption,
                    TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.scaffoldHeading,
                    ),
                  ),
                ),
              ),
            if (fits)
              grid
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: grid,
              ),
          ],
        );
      },
    );
  }

  TextSpan _span(
    BuildContext context,
    List<CmsInline> inlines,
    TextStyle base,
  ) {
    return TextSpan(
      style: base,
      children: [
        for (final run in inlines)
          TextSpan(
            text: run.text,
            style: TextStyle(
              fontWeight: run.bold ? FontWeight.w700 : null,
              fontStyle: run.italic ? FontStyle.italic : null,
              color: run.href != null
                  ? AppColors.accentStrong
                  : (run.bold ? context.scaffoldHeading : null),
              decoration: run.underline || run.href != null
                  ? TextDecoration.underline
                  : null,
              decorationColor: run.href != null ? AppColors.accentStrong : null,
            ),
            recognizer: run.href == null ? null : _tap(run.href!),
          ),
      ],
    );
  }

  TapGestureRecognizer _tap(String href) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onLink(href);
    _recognizers.add(recognizer);
    return recognizer;
  }
}

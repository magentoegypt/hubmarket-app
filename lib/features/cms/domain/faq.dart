import 'cms_document.dart';

/// One question of the Help centre FAQ.
class FaqItem {
  FaqItem({required this.question, required this.answer});

  /// A plain-text answer (the bundled FAQ) as a one-paragraph item.
  factory FaqItem.text(String question, String answer) => FaqItem(
    question: question,
    answer: [
      CmsParagraph([CmsInline(answer)]),
    ],
  );

  final String question;

  /// The answer as renderable blocks — links, lists and emphasis survive.
  final List<CmsBlock> answer;

  late final String _searchText =
      '$question ${CmsDocument.plainText(answer)}'.toLowerCase();

  /// Whether [query] (already lower-cased and trimmed) occurs in the question
  /// or the answer.
  bool matches(String query) => _searchText.contains(query);
}

/// A group of FAQ questions shown as one "Popular topics" row.
class FaqTopic {
  const FaqTopic({required this.title, required this.items, this.icon});

  /// Null for questions placed before the first topic heading — shown as
  /// plain questions rather than behind a topic row.
  final String? title;

  /// The topic's `data-icon` key (`orders`, `returns`, `payments`, `account`,
  /// `selling`, `delivery`), or null for the generic help icon.
  final String? icon;
  final List<FaqItem> items;
}

/// Reads the Help centre FAQ from the CMS block `hm_app_faq`.
///
/// The storefront has no FAQ page (29 Sep 2026: `route(url: "faq")` is null
/// and no CMS page carries one), so the FAQ lives in a block admins edit under
/// Content › Blocks, one per store view. The convention survives the WYSIWYG
/// editor because it is only headings and paragraphs:
///
/// ```html
/// <h2 data-icon="orders">Orders &amp; delivery</h2>   <!-- a topic -->
/// <h3>How do I track my order?</h3>                   <!-- a question -->
/// <p>Open Account › My orders…</p>                     <!-- its answer: -->
/// <ul><li>…</li></ul>                                  <!-- everything up to -->
/// <h3>Can I cancel an order?</h3>                      <!-- the next h2/h3 -->
/// <p>…</p>
/// <h2 data-icon="payments">Payments</h2>
/// …
/// ```
///
/// * `<h1>`/`<h2>` start a topic; `data-icon` is optional (`orders`,
///   `returns`, `payments`, `account`, `selling`, `delivery`).
/// * `<h3>`–`<h6>` start a question; the blocks after it, up to the next
///   heading of either kind, are the answer. Links, lists, bold and images
///   work in answers.
/// * Questions before the first topic heading form an untitled group.
/// * Anything before the first question of a topic is ignored, as are topics
///   without questions. Wrapper `<div>`s (Page Builder rows) are fine.
abstract final class FaqDocument {
  static List<FaqTopic> parse(String html) {
    final topics = <_TopicDraft>[];
    _TopicDraft? topic;
    _ItemDraft? item;
    for (final block in CmsDocument.parse(html)) {
      if (block is CmsHeading && block.level <= 2) {
        topic = _TopicDraft(block.text, block.attributes['data-icon']);
        topics.add(topic);
        item = null;
        continue;
      }
      if (block is CmsHeading) {
        if (topic == null) {
          topic = _TopicDraft(null, null);
          topics.add(topic);
        }
        item = _ItemDraft(block.text);
        topic.items.add(item);
        continue;
      }
      item?.answer.add(block);
    }
    return [
      for (final t in topics)
        if (t.items.any((i) => i.question.isNotEmpty))
          FaqTopic(
            title: (t.title?.isEmpty ?? true) ? null : t.title,
            icon: t.icon?.trim().toLowerCase(),
            items: [
              for (final i in t.items)
                if (i.question.isNotEmpty)
                  FaqItem(question: i.question, answer: i.answer),
            ],
          ),
    ];
  }
}

class _TopicDraft {
  _TopicDraft(this.title, this.icon);
  final String? title;
  final String? icon;
  final List<_ItemDraft> items = <_ItemDraft>[];
}

class _ItemDraft {
  _ItemDraft(this.question);
  final String question;
  final List<CmsBlock> answer = <CmsBlock>[];
}

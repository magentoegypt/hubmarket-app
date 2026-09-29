/// A storefront blog post ("The Hub Market Journal") from the Mirasvit blog
/// (`blogPosts` GraphQL query). Only the fields the home rail needs are kept;
/// the full article opens on the live site in the in-app web view.
class BlogPost {
  const BlogPost({
    required this.id,
    required this.title,
    required this.url,
    this.imageUrl = '',
    this.excerpt = '',
    this.publishTime = '',
  });

  final int id;
  final String title;

  /// Absolute post URL (`post_url`) — opened in the in-app web view.
  final String url;
  final String imageUrl;
  final String excerpt;
  final String publishTime;

  bool get hasImage => imageUrl.isNotEmpty;
}

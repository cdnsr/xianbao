import 'package:html/parser.dart';
import 'package:html/dom.dart' as dom;

/// Article list item model, parsed from SSR HTML.
class ArticleListItem {
  final String url;
  final String title;
  final String category;
  final String summary;
  final int commentCount;
  final String date;
  final String time;
  final String author;
  final Object? authorRegistrationTime;

  ArticleListItem({
    required this.url,
    required this.title,
    required this.category,
    required this.summary,
    required this.commentCount,
    required this.date,
    required this.time,
    required this.author,
    this.authorRegistrationTime,
  });

  String get path => url;

  /// Numeric article id from URL path, e.g. `/zuankeba/6640760.html` -> 6640760.
  int? get articleId => extractArticleId(url);

  static int? extractArticleId(String pathOrUrl) {
    final match = RegExp(r'/(\d+)\.html').firstMatch(pathOrUrl);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  Map<String, Object?> toJson() => {
    'url': url,
    'title': title,
    'category': category,
    'summary': summary,
    'commentCount': commentCount,
    'date': date,
    'time': time,
    'author': author,
    'authorRegistrationTime': authorRegistrationTime,
  };

  factory ArticleListItem.fromJson(Map<String, dynamic> json) {
    return ArticleListItem(
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      date: json['date'] as String? ?? '',
      time: json['time'] as String? ?? '',
      author: json['author'] as String? ?? '',
      authorRegistrationTime: json['authorRegistrationTime'],
    );
  }

  /// Parse all article list items from an SSR list HTML page.
  static List<ArticleListItem> parseList(String html) {
    final document = _parse(html);
    final items = <ArticleListItem>[];
    final lis = document.querySelectorAll('li.article-list');
    for (final li in lis) {
      final a = li.querySelector('p.title > a');
      if (a == null) continue;
      final timeEl = li.querySelector('time.badge');
      items.add(
        ArticleListItem(
          url: a.attributes['href'] ?? '',
          title: a.attributes['title'] ?? a.text.trim(),
          category: a.attributes['data-catename'] ?? '',
          summary: a.attributes['data-content'] ?? '',
          commentCount:
              int.tryParse(a.attributes['data-comments']?.trim() ?? '0') ?? 0,
          date: timeEl?.attributes['datetime'] ?? '',
          time: timeEl?.attributes['title'] ?? '',
          author: a.attributes['data-louzhu'] ?? '',
          authorRegistrationTime: a.attributes['data-louzhuregtime'],
        ),
      );
    }
    return items;
  }

  /// Parse total page count from pagebar in HTML.
  static int parsePageCount(String html) {
    final document = _parse(html);
    final pagebar = document.querySelector('.pagebar');
    if (pagebar == null) return 1;
    final text = pagebar.text;
    final match = RegExp(r'(\d+)\s*页').firstMatch(text);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 1;
    }
    final pageLinks = pagebar.querySelectorAll('a.page-numbers');
    final current = pagebar.querySelector('.page-numbers.current');
    int maxPage = int.tryParse(current?.text.trim() ?? '1') ?? 1;
    for (final link in pageLinks) {
      final p = int.tryParse(link.text.trim());
      if (p != null && p > maxPage) maxPage = p;
    }
    return maxPage;
  }

  /// Parse the category ID from the meta.php script tag in category page HTML.
  /// Returns null if not found (e.g. on the home page or xianbaoku category).
  static int? parseCateId(String html) {
    final match = RegExp(
      r'meta\.php\?type=category&cateid=(\d+)',
    ).firstMatch(html);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }
}

/// Article detail model, parsed from SSR detail page HTML.
class ArticleDetail {
  final String title;
  final String author;
  final String datetime;
  final String contentHtml;
  final int commentCount;
  final List<Comment> comments;
  final String? commentPostUrl;
  final String? commentKey;
  final int? articleId;

  ArticleDetail({
    required this.title,
    required this.author,
    required this.datetime,
    required this.contentHtml,
    required this.commentCount,
    required this.comments,
    this.commentPostUrl,
    this.commentKey,
    this.articleId,
  });

  static ArticleDetail parse(String html) {
    final document = _parse(html);

    final article = document.querySelector('article.art-main');
    final title = article?.querySelector('h1.art-title')?.text.trim() ?? '';
    final author = article?.querySelector('span.author a')?.text.trim() ?? '';
    final timeEl = article?.querySelector('time.time');
    final datetime = timeEl?.attributes['title'] ?? '';
    final contentHtml =
        article?.querySelector('.article-content')?.innerHtml ?? '';
    final commentCountEl = article?.querySelector('span.comment');
    final commentCount = int.tryParse(commentCountEl?.text.trim() ?? '0') ?? 0;

    int? articleId;
    final button = document.querySelector('#article-button');
    final dataId = button?.attributes['data-id']?.trim();
    if (dataId != null && dataId.isNotEmpty) {
      articleId = int.tryParse(dataId);
    }
    if (articleId == null) {
      final nav = document.querySelector('.pc-nav[data-artid]');
      final artId = nav?.attributes['data-artid']?.trim();
      if (artId != null && artId.isNotEmpty) {
        articleId = int.tryParse(artId);
      }
    }
    if (articleId == null) {
      final pathMatch = RegExp(
        r'data-artid=["''](\d+)["'']',
      ).firstMatch(html);
      if (pathMatch != null) {
        articleId = int.tryParse(pathMatch.group(1)!);
      }
    }

    final comments = <Comment>[];
    final commentList = document.querySelector('.comment-list');
    if (commentList != null) {
      for (final ul in commentList.querySelectorAll('div.ul')) {
        final li = ul.querySelector('div.li');
        if (li == null) continue;
        final clbody = li.querySelector('.clbody');
        if (clbody == null) continue;
        final authorEl = clbody.querySelector('.author');
        final authorText =
            authorEl?.firstChild?.text?.trim() ?? authorEl?.text.trim() ?? '';
        final cTime = clbody.querySelector('.c-time')?.text.trim() ?? '';
        final cIp = clbody.querySelector('.c-ip')?.text.trim() ?? '';
        final contentEl = clbody.querySelector('.c-neirong');
        String contentText = '';
        if (contentEl != null) {
          final buf = StringBuffer();
          for (final node in contentEl.nodes) {
            if (node.nodeType == 3) {
              buf.write(node.text?.trim());
            }
          }
          contentText = buf.toString().trim();
        }
        final replies = <CommentReply>[];
        for (final dp in clbody.querySelectorAll('.c-dianping')) {
          replies.add(
            CommentReply(
              author: dp.querySelector('.dianpingming')?.text.trim() ?? '',
              time: dp.querySelector('.dianpingshijian')?.text.trim() ?? '',
              content: dp.querySelector('.dianpingneirong')?.text.trim() ?? '',
            ),
          );
        }
        comments.add(
          Comment(
            author: authorText,
            time: cTime,
            region: cIp,
            content: contentText,
            replies: replies,
          ),
        );
      }
    }

    final form = document.querySelector('form#frmSumbit');
    String? postUrl;
    String? key;
    if (form != null) {
      final action = form.attributes['action'] ?? '';
      postUrl = action.replaceAll('&amp;', '&');
      final keyMatch = RegExp(r'key=([0-9a-f]+)').firstMatch(action);
      key = keyMatch?.group(1);
    }

    return ArticleDetail(
      title: title,
      author: author,
      datetime: datetime,
      contentHtml: contentHtml,
      commentCount: commentCount,
      comments: comments,
      commentPostUrl: postUrl,
      commentKey: key,
      articleId: articleId,
    );
  }
}

class Comment {
  final String author;
  final String time;
  final String region;
  final String content;
  final List<CommentReply> replies;

  Comment({
    required this.author,
    required this.time,
    required this.region,
    required this.content,
    required this.replies,
  });
}

class CommentReply {
  final String author;
  final String time;
  final String content;

  CommentReply({
    required this.author,
    required this.time,
    required this.content,
  });
}

/// A collected article entry from user center list API.
class CollectListItem {
  final String collectId;
  final String title;
  final String url;
  final String postTime;
  final String viewNums;

  CollectListItem({
    required this.collectId,
    required this.title,
    required this.url,
    required this.postTime,
    required this.viewNums,
  });

  int? get articleId => ArticleListItem.extractArticleId(url);

  factory CollectListItem.fromApiMap(Map<String, dynamic> map) {
    final titleHtml = map['Title']?.toString() ?? '';
    final caozuo = map['Caozuo']?.toString() ?? '';
    final doc = parse(titleHtml);
    final a = doc.querySelector('a');
    final title = (a?.text.trim().isNotEmpty == true)
        ? a!.text.trim()
        : doc.body?.text.trim() ?? titleHtml;
    var url = a?.attributes['href'] ?? '';
    if (url.startsWith('http')) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        url = uri.path;
      }
    }
    final idMatch = RegExp(r"del_coll\('(\d+)'\)").firstMatch(caozuo);
    final collectId = idMatch?.group(1) ?? '';
    return CollectListItem(
      collectId: collectId,
      title: title,
      url: url,
      postTime: map['Posttime']?.toString() ?? '',
      viewNums: map['ViewNums']?.toString() ?? '',
    );
  }
}

/// Result of toggling article collect state.
class CollectToggleResult {
  /// Website codes: 0 = now collected, 1 = need login, other = uncollected.
  final int code;
  final String message;
  final int size;
  final bool needLogin;
  final bool isCollected;

  const CollectToggleResult({
    required this.code,
    required this.message,
    required this.size,
    required this.needLogin,
    required this.isCollected,
  });

  factory CollectToggleResult.fromJson(Map<String, dynamic> json) {
    final code = (json['code'] as num?)?.toInt() ?? -1;
    final size = (json['size'] as num?)?.toInt() ?? 0;
    final msg = json['msg']?.toString() ?? '';
    return CollectToggleResult(
      code: code,
      message: msg,
      size: size,
      needLogin: code == 1,
      isCollected: code == 0,
    );
  }
}

/// Collect button state from article_cache.
class CollectButtonState {
  final bool isCollected;
  final int size;
  final String label;

  const CollectButtonState({
    required this.isCollected,
    required this.size,
    required this.label,
  });

  factory CollectButtonState.fromButsHtml(String buts) {
    final text = parse(buts).body?.text.trim() ?? buts;
    final isCollected = text.contains('已收藏');
    final sizeMatch = RegExp(r'\|\s*(\d+)').firstMatch(text);
    final size = sizeMatch != null ? int.tryParse(sizeMatch.group(1)!) ?? 0 : 0;
    final label = isCollected
        ? (size > 0 ? '已藏 | $size' : '已藏')
        : (size > 0 ? '收藏 | $size' : '收藏');
    return CollectButtonState(
      isCollected: isCollected,
      size: size,
      label: label,
    );
  }
}

/// Wrapper to avoid name clash with ArticleDetail.parse.
dom.Document _parse(String html) => parse(html);

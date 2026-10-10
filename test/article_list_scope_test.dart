import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/models/article.dart';
import 'package:xianbao/models/category.dart';

/// One `<li class="article-list">` in the markup the site emits.
String _li(String href, String title) => '''
<li class="article-list xb-st-chk">
  <span class="figure cg30"></span>
  <p class="title">
    <time class="badge red" datetime="2026-10-11" title="2026-10-11 00:23">00:23</time>
    <span class="badge com">0</span>
    <a href="$href" title="$title" data-catename="好单线报-饮料-淘宝" data-content="x">$title</a>
  </p>
</li>''';

/// The page shell: main list inside `div.listbox`, sidebar hot lists after it.
String _page({
  required String mainItems,
  String mainWrapper = '<div class="listbox">',
  String emptyNote = '',
  String sidebar = '',
}) =>
    '''
<!DOCTYPE html><html><head><title>搜索"矿泉水"-线报酷</title></head><body>
<div id="content" class="content container clearfix">
  <div class="main-col">
    <main id="mainbox" class="fl br mb sb">
      $mainWrapper
        <ul class="new-post">$mainItems</ul>
        $emptyNote
      </div>
    </main>
  </div>
  <aside id="sidebar" class="fr">
    <div class="rank-list bangdan sb mb">
      <div class="swiper r-swiper"><div class="swiper-wrapper">
        <div class="swiper-slide"><ul class="new-post">$sidebar</ul></div>
      </div></div>
    </div>
  </aside>
</div>
</body></html>''';

void main() {
  group('ArticleListItem.parseList list scope', () {
    test('ignores the sidebar hot lists (regression)', () {
      final html = _page(
        mainItems: _li('/haodan/1.html', '矿泉水一箱') +
            _li('/haodan/2.html', '矿泉水两箱'),
        sidebar: _li('/douban-pinzu/9.html', '小米内衣洗衣机') +
            _li('/weibo/8.html', '淘宝红包'),
      );

      final items = ArticleListItem.parseList(html);

      expect(items.map((a) => a.url), ['/haodan/1.html', '/haodan/2.html']);
    });

    test('a keyword with no hits parses to nothing, not to hot-list noise',
        () {
      final html = _page(
        mainItems: '',
        emptyNote: '<div class="search-empty">没有找到与「zzqqxx」相关的线报</div>',
        sidebar: _li('/douban-pinzu/9.html', '小米内衣洗衣机') +
            _li('/weibo/8.html', '淘宝红包'),
      );

      expect(ArticleListItem.parseList(html), isEmpty);
    });

    test('keeps working when the listbox class is renamed', () {
      final html = _page(
        mainItems: _li('/haodan/1.html', '矿泉水一箱'),
        mainWrapper: '<div class="listbox-new">',
        sidebar: _li('/douban-pinzu/9.html', '小米内衣洗衣机'),
      );

      expect(
        ArticleListItem.parseList(html).map((a) => a.url),
        ['/haodan/1.html'],
      );
    });

    test('reads a category page whose listbox carries extra classes', () {
      final html = _page(
        mainItems: _li('/haodan/1.html', '矿泉水一箱'),
        mainWrapper: '<div class="listbox xb-t2">',
        sidebar: _li('/douban-pinzu/9.html', '小米内衣洗衣机'),
      );

      expect(ArticleListItem.parseList(html).length, 1);
    });
  });

  group('parsePageCount', () {
    test('reads the total from the pagebar', () {
      final html = '''
<div class="pagebar"><div class="nav-links">
  <span class="page-numbers current">1</span>
  <a class="page-numbers" href="/page/2/">2</a>
  <label>共 3 页</label>
</div></div>''';
      expect(ArticleListItem.parsePageCount(html), 3);
    });

    test('defaults to a single page without a pagebar', () {
      expect(ArticleListItem.parsePageCount('<html></html>'), 1);
    });
  });

  group('CategoryItem.parsePageTitle', () {
    test('reads the title the filter scopes are derived from', () {
      expect(
        CategoryItem.parsePageTitle('<html><head><title>赚客吧-线报酷</title>'
            '</head></html>'),
        '赚客吧-线报酷',
      );
    });
  });
}

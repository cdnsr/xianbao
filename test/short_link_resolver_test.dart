import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/services/short_link_resolver.dart';

/// Real payload served by `https://u.jd.com/4DNOWBi`: a 200 with the next hop
/// in a JS variable rather than a 3xx redirect.
const String _jdInterstitial =
    "<!DOCTYPE html><html><head><title>京东网上商城</title></head><body>"
    "<script language='javascript'>function htmlspecialchars(str){}</script>"
    "var hrl='https://u.jd.com/jda?e=1000521676&p=JF8BASkJK1olWAQCUV9eCkkQC18"
    "&a=fCg9UgoiAwwHO1BcXkQYFFlif3hxeldcQlozVRBSUll%2bAQAPDSwjLw%3d%3d"
    "&refer=norefer&d=4DNOWBi';var ua='Mozilla/5.0';"
    "</script></body></html>";

/// Real payload served when JD risk control intercepts the hop. The product
/// page is still recoverable from `returnurl`.
const String _jdRiskHandler =
    'https://cfe.m.jd.com/privatedomain/risk_handler/03101900/'
    '?evApi=color-mesh_A_SC_pc_item_product_core&evExt=&evtype=3&lgid=2193'
    '&returnurl=https%3A%2F%2Fitem.jd.com%2F10198817280930.html%3Frid%3D19054'
    '%26unionMediaTag%3D2_0_1%26uabt%3D979_15568_1_0%26cu%3Dtrue'
    '%26utm_source%3Dlianmeng__9__kong__new.xian';

void main() {
  group('isExpandable', () {
    test('accepts the JD shortener and affiliate hosts', () {
      expect(ShortLinkResolver.isExpandable('https://u.jd.com/4DNOWBi'), isTrue);
      expect(ShortLinkResolver.isExpandable('https://3.cn/2abcDEF'), isTrue);
      expect(
        ShortLinkResolver.isExpandable('https://union-click.jd.com/jdc?e=1&p=abc'),
        isTrue,
      );
      expect(
        ShortLinkResolver.isExpandable('https://jingfen.jd.com/item?q=x'),
        isTrue,
      );
    });

    test('accepts JD product links (they need no network to clean up)', () {
      expect(
        ShortLinkResolver.isExpandable('https://item.jd.com/100012043978.html'),
        isTrue,
      );
      expect(
        ShortLinkResolver.isExpandable(
          'https://item.m.jd.com/product/100288670988.html?rid=19054',
        ),
        isTrue,
      );
    });

    test('ignores everything else', () {
      expect(ShortLinkResolver.isExpandable('https://m.tb.cn/h.8EBu5UN'), isFalse);
      expect(ShortLinkResolver.isExpandable('https://www.jd.com/'), isFalse);
      expect(ShortLinkResolver.isExpandable('https://new.xianbao.fun/'), isFalse);
      expect(ShortLinkResolver.isExpandable('not a url'), isFalse);
    });
  });

  group('canonicalProductUrl', () {
    test('strips affiliate query parameters', () {
      expect(
        ShortLinkResolver.canonicalProductUrl(
          'https://item.jd.com/10198817280930.html?rid=19054&cu=true'
          '&utm_source=lianmeng__9__kong',
        ),
        'https://item.jd.com/10198817280930.html',
      );
    });

    test('converts the mobile form to the canonical desktop URL', () {
      expect(
        ShortLinkResolver.canonicalProductUrl(
          'https://item.m.jd.com/product/100288670988.html?rid=19054',
        ),
        'https://item.jd.com/100288670988.html',
      );
    });

    test('returns null for non-product URLs', () {
      expect(ShortLinkResolver.canonicalProductUrl('https://u.jd.com/4DNOWBi'),
          isNull);
      expect(ShortLinkResolver.canonicalProductUrl('https://www.jd.com/'), isNull);
    });
  });

  group('productUrlFromReturnUrl', () {
    test('recovers the product page from a risk-control URL', () {
      expect(
        ShortLinkResolver.productUrlFromReturnUrl(_jdRiskHandler),
        'https://item.jd.com/10198817280930.html',
      );
    });

    test('handles a double-encoded value', () {
      const twice =
          'returnurl=https%253A%252F%252Fitem.jd.com%252F10198817280930.html';
      expect(
        ShortLinkResolver.productUrlFromReturnUrl(twice),
        'https://item.jd.com/10198817280930.html',
      );
    });

    test('returns null when there is no returnurl', () {
      expect(ShortLinkResolver.productUrlFromReturnUrl('https://www.jd.com/'),
          isNull);
    });
  });

  group('redirectTargetInHtml', () {
    test('reads the hrl variable from the JD interstitial', () {
      final target = ShortLinkResolver.redirectTargetInHtml(_jdInterstitial);
      expect(target, isNotNull);
      expect(target, startsWith('https://u.jd.com/jda?e=1000521676'));
      expect(target, contains('&d=4DNOWBi'));
      // The JS string's &amp; escaping must not survive.
      expect(target, isNot(contains('&amp;')));
    });

    test('falls back to a meta refresh', () {
      const html =
          '<meta http-equiv="refresh" content="0;url=https://item.jd.com/1.html">';
      expect(ShortLinkResolver.redirectTargetInHtml(html),
          'https://item.jd.com/1.html');
    });

    test('falls back to location.href', () {
      const html = "location.href='https://u.jd.com/abcd';";
      expect(ShortLinkResolver.redirectTargetInHtml(html),
          'https://u.jd.com/abcd');
    });

    test('returns null when the page is not an interstitial', () {
      expect(ShortLinkResolver.redirectTargetInHtml('<p>hello</p>'), isNull);
    });
  });

  group('expandableUrlsIn', () {
    test('finds JD links and ignores other hosts and images', () {
      const html =
          '<p>好价 <a href="https://u.jd.com/4DNOWBi">https://u.jd.com/4DNOWBi</a></p>'
          '<a href="https://m.tb.cn/h.8EBu5UN">淘宝</a>'
          '<img src="https://img14.360buyimg.com/x.jpg">';

      expect(ShortLinkResolver.expandableUrlsIn(html), ['https://u.jd.com/4DNOWBi']);
      expect(ShortLinkResolver.hasExpandableLink(html), isTrue);
    });

    test('deduplicates a link that appears as both href and text', () {
      const html =
          '<a href="https://u.jd.com/4DNOWBi">https://u.jd.com/4DNOWBi</a>';
      expect(ShortLinkResolver.expandableUrlsIn(html), ['https://u.jd.com/4DNOWBi']);
    });

    test('reports no work for an article with no JD links', () {
      const html = '<p>无链接 <a href="https://m.tb.cn/h.1">x</a></p>';
      expect(ShortLinkResolver.hasExpandableLink(html), isFalse);
    });
  });

  group('rewriteHtml', () {
    test('cleans a product link without any network call', () async {
      const html =
          '<a href="https://item.m.jd.com/product/100288670988.html?rid=19054">'
          '商品</a>';

      final out = await ShortLinkResolver.instance.rewriteHtml(html);

      expect(out, contains('https://item.jd.com/100288670988.html'));
      expect(out, isNot(contains('rid=19054')));
    });

    test('leaves non-JD links untouched', () async {
      const html = '<a href="https://m.tb.cn/h.8EBu5UN">淘宝</a> 正文';
      expect(await ShortLinkResolver.instance.rewriteHtml(html), html);
    });
  });
}

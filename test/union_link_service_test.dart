import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/services/union_link_service.dart';

void main() {
  group('UnionLinkService.promotionUrlFrom', () {
    test('reads the url field from the service response', () {
      expect(
        UnionLinkService.promotionUrlFrom('{"url":"https://u.jd.com/abc"}'),
        'https://u.jd.com/abc',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        UnionLinkService.promotionUrlFrom('{"url":"  https://u.jd.com/abc  "}'),
        'https://u.jd.com/abc',
      );
    });

    test('returns null on the service error shape', () {
      // The worker answers 502 with {"error": ..., "raw": ...} - that must not
      // be mistaken for a link.
      expect(
        UnionLinkService.promotionUrlFrom(
          '{"error":"京东未返回推广链接","status":200,"raw":"{}"}',
        ),
        isNull,
      );
    });

    test('returns null for non-http, empty or missing url', () {
      expect(UnionLinkService.promotionUrlFrom('{"url":""}'), isNull);
      expect(UnionLinkService.promotionUrlFrom('{"url":"not-a-url"}'), isNull);
      expect(UnionLinkService.promotionUrlFrom('{"other":1}'), isNull);
      expect(UnionLinkService.promotionUrlFrom('{}'), isNull);
    });

    test('returns null for non-JSON or non-string bodies', () {
      expect(UnionLinkService.promotionUrlFrom('<html>502</html>'), isNull);
      expect(UnionLinkService.promotionUrlFrom(''), isNull);
      expect(UnionLinkService.promotionUrlFrom(null), isNull);
      expect(UnionLinkService.promotionUrlFrom(42), isNull);
      expect(UnionLinkService.promotionUrlFrom('[1,2]'), isNull);
    });
  });

  group('configuration gate', () {
    test('is off until a service URL is saved', () {
      // No load()/save() in this test, so it stays at its default.
      expect(UnionLinkService.instance.isConfigured, isFalse);
      expect(UnionLinkService.instance.serviceUrl, '');
    });

    test('an unconfigured service never converts anything', () async {
      expect(
        await UnionLinkService.instance.promotionUrlFor(
          'https://item.jd.com/100288670988.html',
        ),
        isNull,
      );
    });
  });
}

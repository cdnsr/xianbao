import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/utils/version_compare.dart';

void main() {
  group('compareVersion', () {
    test('orders patch correctly', () {
      expect(compareVersion('1.4.9', '1.4.10'), -1);
      expect(compareVersion('1.4.10', '1.4.9'), 1);
      expect(compareVersion('1.4.9', '1.4.9'), 0);
    });

    test('handles v prefix and build metadata', () {
      expect(compareVersion('v1.4.9', '1.4.9'), 0);
      expect(compareVersion('1.4.9+24', '1.4.9'), 0);
      expect(isVersionNewer('1.4.10', '1.4.9+24'), isTrue);
      expect(isVersionNewer('1.4.9', '1.4.9'), isFalse);
    });
  });
}
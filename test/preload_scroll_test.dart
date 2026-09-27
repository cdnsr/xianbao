import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/pages/home/home_page.dart';

/// Mirrors the layout the list actually produces closely enough to reason
/// about trigger distances: a fixed-height row and a phone-sized viewport.
const double _rowHeight = 41;
const double _viewport = 700;

/// maxScrollExtent for a window of [shown] rows.
double _maxFor(int shown) {
  final extent = shown * _rowHeight - _viewport;
  return extent < 0 ? 0 : extent;
}

({int reveal, bool fetchNextPage}) _at(
  double pixels, {
  required int shown,
  required int fetched,
}) {
  return preloadForScroll(
    shown: shown,
    fetched: fetched,
    pixels: pixels,
    maxScrollExtent: _maxFor(shown),
    viewportDimension: _viewport,
  );
}

void main() {
  group('preloadForScroll', () {
    test('does nothing while the end is still far away', () {
      final d = _at(0, shown: 100, fetched: 300);
      expect(d.reveal, 100);
      expect(d.fetchNextPage, isFalse);
    });

    test('top-up starts ~1.5 screens before the end, not at it', () {
      // Regression for "had to reverse and scroll back down": the reveal must
      // happen while the user is still moving, well before the hard stop.
      const oneAndAHalfScreens = _viewport * 1.5; // 1050
      final farFromEnd = _maxFor(300) - oneAndAHalfScreens - 1;
      expect(_at(farFromEnd, shown: 300, fetched: 900).reveal, 300);

      final justInside = _maxFor(300) - oneAndAHalfScreens + 1;
      expect(_at(justInside, shown: 300, fetched: 900).reveal, 330);
    });

    test('reveals a chunk when sitting at the very bottom', () {
      final d = _at(_maxFor(100), shown: 100, fetched: 300);
      expect(d.reveal, 130);
      expect(d.fetchNextPage, isFalse);
    });

    test('clamps the reveal to what has actually been fetched', () {
      final d = _at(_maxFor(90), shown: 90, fetched: 100);
      expect(d.reveal, 100);
    });

    test('asks for the next page once every fetched article is revealed', () {
      final d = _at(_maxFor(100), shown: 100, fetched: 100);
      expect(d.reveal, 100);
      expect(d.fetchNextPage, isTrue);
    });

    test('one reveal pushes the end further than the trigger, so it cannot cascade', () {
      // At the bottom of a 100-row window, 300 rows fetched.
      const pixels = 3400.0; // == _maxFor(100)
      final first = _at(pixels, shown: 100, fetched: 300);
      expect(first.reveal, 130);

      // The scroll position has not moved yet; the window is now 130 rows so
      // the end moved 30 rows (~1230px) further down. Nothing more should
      // happen until the user actually scrolls on.
      final second = preloadForScroll(
        shown: first.reveal,
        fetched: 300,
        pixels: pixels,
        maxScrollExtent: _maxFor(first.reveal),
        viewportDimension: _viewport,
      );
      expect(second.reveal, first.reveal);
      expect(second.fetchNextPage, isFalse);
    });

    test('a short list that cannot scroll still asks for the next page', () {
      // Fewer rows than fill the viewport: maxScrollExtent is 0.
      final d = _at(0, shown: 10, fetched: 10);
      expect(d.reveal, 10);
      expect(d.fetchNextPage, isTrue);
    });
  });
}

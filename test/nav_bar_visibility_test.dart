import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/pages/main_shell.dart';

/// Feeds a sequence of scroll updates through [navBarVisibleAfterScroll] the
/// way a real drag would, starting from [startVisible].
bool _run(
  List<double> deltas, {
  double startPixels = 0,
  bool startVisible = true,
}) {
  var pixels = startPixels;
  var visible = startVisible;
  for (final delta in deltas) {
    pixels += delta;
    final next = navBarVisibleAfterScroll(pixels: pixels, delta: delta);
    if (next != null) visible = next;
  }
  return visible;
}

void main() {
  group('navBarVisibleAfterScroll', () {
    test('hides once a swipe upwards passes the threshold', () {
      expect(navBarVisibleAfterScroll(pixels: 30, delta: 6), isFalse);
      expect(navBarVisibleAfterScroll(pixels: 500, delta: 40), isFalse);
    });

    test('leaves the bar alone for a tiny swipe near the top', () {
      // Below the threshold the bar must not flicker on a few pixels.
      expect(navBarVisibleAfterScroll(pixels: 10, delta: 4), isNull);
      expect(navBarVisibleAfterScroll(pixels: 24, delta: 4), isNull);
    });

    test('ignores updates that did not move the list', () {
      expect(navBarVisibleAfterScroll(pixels: 400, delta: 0), isNull);
    });

    test('ANY reverse swipe restores the bar, however small', () {
      // This is the guarantee that the bar can never get stuck hidden.
      expect(navBarVisibleAfterScroll(pixels: 5000, delta: -1), isTrue);
      expect(navBarVisibleAfterScroll(pixels: 5000, delta: -400), isTrue);
    });

    test('reaching the top restores the bar', () {
      expect(navBarVisibleAfterScroll(pixels: 0, delta: 12), isTrue);
      expect(navBarVisibleAfterScroll(pixels: -8, delta: 5), isTrue);
    });
  });

  group('scroll gesture sequences', () {
    test('swipe up then swipe back down shows the bar again', () {
      // Long swipe up: the bar hides on the way.
      final hidden = _run([30, 40, 40, 40, 40, 40, 40]);
      expect(hidden, isFalse, reason: 'bar should hide while scrolling down the list');

      // Reverse: a single small pull back down brings it straight back.
      final restored = _run(
        [-5],
        startPixels: 270,
        startVisible: false,
      );
      expect(restored, isTrue, reason: 'bar must come back on the reverse swipe');
    });

    test('a full drag up and all the way back leaves the bar visible', () {
      final deltas = <double>[
        ...List.filled(10, 50.0), // swipe up, list advances -> hidden
        ...List.filled(10, -50.0), // swipe back down -> shown again
      ];
      expect(_run(deltas), isTrue);
    });

    test('however far the list advanced, a reverse swipe still shows the bar', () {
      for (final distance in <double>[30, 500, 5000]) {
        final deltas = <double>[distance, -1];
        expect(_run(deltas), isTrue,
            reason: 'bar must not stay hidden after a $distance px scroll');
      }
    });

    test('a reverse swipe does not disable hiding for the next swipe up', () {
      // Showing on the reverse is not sticky: swiping up again hides it,
      // because the user is moving forward through the list once more.
      expect(_run(<double>[100, -10, 100]), isFalse);
    });

    test('stays hidden while the list only advances', () {
      final deltas = List<double>.filled(30, 25.0);
      expect(_run(deltas), isFalse);
    });
  });
}

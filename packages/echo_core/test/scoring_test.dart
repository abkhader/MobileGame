import 'package:echo_core/echo_core.dart';
import 'package:test/test.dart';

void main() {
  test('stars follow the spec thresholds', () {
    int s(int score, int best) => Scoring.stars(score: score, best: best);
    expect(
      [s(5, 5), s(7, 5), s(8, 5), s(4, 4), s(6, 4), s(7, 4), s(3, 5)],
      [3, 2, 1, 3, 2, 1, 3],
    );
  });
}

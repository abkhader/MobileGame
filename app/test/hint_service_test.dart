import 'package:echo_app/hints/hint_service.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter_test/flutter_test.dart';

Level _level({
  Object? solution = const [
    ['R'],
    ['R', 'R', 'R', 'R'],
  ],
}) => LevelLoader.fromMap({
  'id': 't',
  'name': 't',
  'runLimit': 2,
  'grid': ['#######', '#Sa.AE#', '#######'],
  'bestScore': 5,
  'solution': ?solution,
});

void main() {
  test('hint path follows the stored solution', () {
    final level = _level();
    expect(HintService.pathFor(level, 0), [
      const Position(1, 1),
      const Position(2, 1),
    ]);
    expect(HintService.pathFor(level, 1)!.last, const Position(5, 1));
    expect(HintService.pathFor(level, 2), isNull);
  });

  test('no solution means no path', () {
    expect(HintService.pathFor(_level(solution: null), 0), isNull);
  });

  test('matchesSolution compares ghosts with the leading runs', () {
    final level = _level();
    var s = GameState.initial(level);
    expect(HintService.matchesSolution(level, s), isTrue);
    s = Rules.endRun(Rules.step(s, Move.right));
    expect(HintService.matchesSolution(level, s), isTrue);

    var other = GameState.initial(level);
    other = Rules.endRun(Rules.step(other, Move.wait));
    expect(HintService.matchesSolution(level, other), isFalse);
  });
}

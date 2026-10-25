import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/hints/hint_service.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter/services.dart';
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

  group('nextBeats', () {
    Level level1() => LevelLoader.fromMap({
      'id': 't',
      'name': 't',
      'runLimit': 1,
      'grid': ['########', '#S....E#', '########'],
      'bestScore': 5,
      'solution': [
        ['R', 'R', 'R', 'R', 'R'],
      ],
    });

    test('at the start it is the first four solution moves', () {
      final level = level1();
      expect(HintService.nextBeats(level, GameState.initial(level)), [
        Move.right,
        Move.right,
        Move.right,
        Move.right,
      ]);
    });

    test('after matching moves it gives the next beats, then fewer', () {
      final level = level1();
      var s = Rules.step(
        Rules.step(GameState.initial(level), Move.right),
        Move.right,
      );
      expect(HintService.nextBeats(level, s), hasLength(3));
      expect(HintService.nextBeats(level, s, count: 1), [Move.right]);
      s = Rules.step(Rules.step(s, Move.right), Move.right);
      expect(HintService.nextBeats(level, s), [Move.right]);
    });

    test('it is null after a deviation or when ghosts differ', () {
      final level = level1();
      var s = Rules.step(GameState.initial(level), Move.wait);
      expect(HintService.nextBeats(level, s), isNull);
      s = Rules.step(GameState.initial(level), Move.right);
      s = Rules.step(s, Move.left);
      expect(HintService.nextBeats(level, s), isNull);
      expect(
        HintService.nextBeats(_level(solution: null), GameState.initial(level)),
        isNull,
      );
    });

    testWidgets('a pushing solution move stays a move, marked blocked', (
      t,
    ) async {
      final level = (await t.runAsync(
        () => LevelRepository(PlatformAssetBundle()).load('1-08'),
      ))!;
      var s = GameState.initial(level);
      final beats = HintService.nextBeats(level, s)!;
      expect(beats, level.solution![0].take(4).toList());
      expect(beats, isNot(contains(Move.wait)));
      final steps = HintService.stepsFor(s, beats);
      expect(steps.map((e) => e.move), beats);
      expect(steps.any((e) => e.blocked), isTrue);
      for (final step in steps) {
        final next = Rules.step(s, step.move);
        expect(step.from, s.player);
        expect(step.to, next.player);
        expect(step.blocked, next.player == s.player);
        s = next;
      }
    });

    test('a wait is a wait, not a push', () {
      final level = level1();
      final steps = HintService.stepsFor(GameState.initial(level), [
        Move.wait,
        Move.right,
      ]);
      expect(steps[0].blocked, isFalse);
      expect(steps[0].move, Move.wait);
      expect(steps[1].to, const Position(2, 1));
    });
  });
}

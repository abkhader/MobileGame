import 'package:echo_app/data/level_repository.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replays every bundled level's stored solution in the app's engine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled levels are exactly 1-01 to 3-10', () async {
    final ids = await LevelRepository(PlatformAssetBundle()).levelIds();
    expect(ids.toSet(), {
      for (var c = 1; c <= 3; c++)
        for (var n = 1; n <= 10; n++) '$c-${'$n'.padLeft(2, '0')}',
    });
    expect(ids, hasLength(30));
  });

  test(
    'every bundled level replays its stored solution to bestScore',
    () async {
      final repo = LevelRepository(PlatformAssetBundle());
      final ids = await repo.levelIds();
      expect(ids, isNotEmpty);
      for (final id in ids) {
        final level = await repo.load(id);
        final solution = level.solution;
        expect(solution, isNotNull, reason: '$id: missing solution');
        expect(level.bestScore, isNotNull, reason: '$id: missing bestScore');

        var state = GameState.initial(level);
        for (var i = 0; i < solution!.length; i++) {
          for (final move in solution[i]) {
            expect(
              state.status,
              GameStatus.playing,
              reason: '$id: solution continues after the level ended',
            );
            state = Rules.step(state, move);
          }
          // A run of 25 moves was already ended by Rules.step.
          if (i < solution.length - 1 &&
              solution[i].length != Rules.maxTicksPerRun) {
            state = Rules.endRun(state);
          }
        }
        expect(
          state.status,
          GameStatus.won,
          reason: '$id: solution does not win',
        );
        expect(state.score, level.bestScore, reason: '$id: score != bestScore');
      }
    },
  );
}

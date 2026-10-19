import 'package:echo_app/data/level_repository.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replays every bundled level's stored solution in the app's engine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

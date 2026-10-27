import 'package:echo_app/data/level_repository.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replays every bundled level's stored solution in the app's engine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Chapters 1 to 3, or 1 to 4 once chapter 4 ships: 10 levels each.
  test(
    'the bundled levels are C-01 to C-10 for chapters 1 to 3 or 4',
    () async {
      final ids = await LevelRepository(PlatformAssetBundle()).levelIds();
      final chapters = ids.map((id) => int.parse(id.split('-').first)).toSet();
      final last = chapters.fold(0, (a, b) => a > b ? a : b);
      expect(last, anyOf(3, 4));
      expect(ids.toSet(), {
        for (var c = 1; c <= last; c++)
          for (var n = 1; n <= 10; n++) '$c-${'$n'.padLeft(2, '0')}',
      });
      expect(ids, hasLength(10 * last));
    },
  );

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
          // A run Rules.step already ended (25 moves, or Pip hit: a forced
          // rewind) is not ended again.
          if (i < solution.length - 1 && state.runIndex == i) {
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

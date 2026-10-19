import 'package:echo_core/echo_core.dart';

/// Hints derived from a level's stored best solution.
class HintService {
  const HintService._();

  /// The player's positions during run [runIndex] of the stored solution,
  /// starting at the level start; null without a solution or past its end.
  static List<Position>? pathFor(Level level, int runIndex) {
    final solution = level.solution;
    if (solution == null || runIndex < 0 || runIndex >= solution.length) {
      return null;
    }
    var state = GameState.initial(level);
    for (var r = 0; r < runIndex; r++) {
      for (final m in solution[r]) {
        if (state.status != GameStatus.playing || state.runIndex != r) break;
        state = Rules.step(state, m);
      }
      if (state.status == GameStatus.playing && state.runIndex == r) {
        state = Rules.endRun(state);
      }
    }
    if (state.status != GameStatus.playing || state.runIndex != runIndex) {
      return null;
    }
    final path = [state.player];
    for (final m in solution[runIndex]) {
      state = Rules.step(state, m);
      if (state.runIndex != runIndex) break;
      path.add(state.player);
      if (state.status != GameStatus.playing) break;
    }
    return path;
  }

  /// True iff the ghosts are exactly the first runs of the stored solution.
  static bool matchesSolution(Level level, GameState s) {
    final solution = level.solution;
    if (solution == null || s.ghosts.length > solution.length) return false;
    for (var i = 0; i < s.ghosts.length; i++) {
      final a = s.ghosts[i];
      final b = solution[i];
      if (a.length != b.length) return false;
      for (var j = 0; j < a.length; j++) {
        if (a[j] != b[j]) return false;
      }
    }
    return true;
  }
}

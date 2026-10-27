import 'package:echo_core/echo_core.dart';

/// Plays [runs] in order and returns the resulting score, or `null` unless the
/// last move of the last run wins the level (so leftover moves, losses and
/// runs that never reach the exit all yield `null`).
///
/// A run that [Rules.step] ends by itself (25 moves, or Pip hit: a forced
/// rewind) is not ended again; moves left in it after that are leftovers.
int? replayScore(Level level, List<List<Move>> runs) {
  if (runs.isEmpty) return null;
  var state = GameState.initial(level);
  try {
    for (var i = 0; i < runs.length; i++) {
      if (runs[i].length > Rules.maxTicksPerRun) return null;
      for (final move in runs[i]) {
        if (state.runIndex != i) return null;
        state = Rules.step(state, move);
      }
      if (i < runs.length - 1 && state.runIndex == i) {
        state = Rules.endRun(state);
      }
    }
  } on StateError {
    return null;
  }
  if (state.status != GameStatus.won || runs.last.isEmpty) return null;
  return state.score;
}

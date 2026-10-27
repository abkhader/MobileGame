import 'package:echo_core/echo_core.dart';

/// Hints derived from a level's stored best solution.
class HintService {
  const HintService._();

  /// The player's positions during run [runIndex] of the stored solution,
  /// starting at the level start; null without a solution or past its end.
  ///
  /// A run that a hit (or the tick cap) already ended is never ended again:
  /// `Rules.endRun` only closes a run still in play.
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

  /// The next [count] moves of the stored solution's current run, from the
  /// player's tick, while the ghosts match the solution and the current run
  /// is its prefix; null otherwise. Moves are returned as stored: a blocked
  /// move is a push the echo records, not a wait.
  static List<Move>? nextBeats(Level level, GameState s, {int count = 4}) {
    final solution = level.solution;
    if (solution == null ||
        s.status != GameStatus.playing ||
        s.runIndex >= solution.length ||
        !matchesSolution(level, s)) {
      return null;
    }
    final run = solution[s.runIndex];
    final done = s.currentRun;
    if (done.length != s.tick || done.length > run.length) return null;
    for (var i = 0; i < done.length; i++) {
      if (done[i] != run[i]) return null;
    }
    return run.skip(done.length).take(count).toList();
  }

  /// Plays [beats] from [s] to say where each one goes and which are pushes.
  static List<HintStep> stepsFor(GameState s, List<Move> beats) {
    final steps = <HintStep>[];
    var state = s;
    for (final m in beats) {
      final next = Rules.step(state, m);
      // A beat that walks into a hit ends the run, but Pip still steps onto
      // that tile first: show it, then stop.
      final hit = next.lastHits.pip;
      if (next.runIndex != state.runIndex && !hit) break;
      final to = Rules.moveTarget(
        state.level,
        state.player,
        m,
        state.openDoors,
      );
      steps.add(
        HintStep(
          move: m,
          from: state.player,
          to: to,
          blocked: m != Move.wait && to == state.player,
        ),
      );
      if (hit || next.status != GameStatus.playing) break;
      state = next;
    }
    return steps;
  }
}

/// One hinted beat: [blocked] means a push against an obstacle.
class HintStep {
  const HintStep({
    required this.move,
    required this.from,
    required this.to,
    required this.blocked,
  });

  final Move move;
  final Position from;
  final Position to;
  final bool blocked;
}

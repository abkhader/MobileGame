import 'level.dart';
import 'move.dart';
import 'position.dart';

enum GameStatus { playing, won, lost }

/// Who was hit on the step that produced a state, so the app can animate
/// and sound it. Every other transition (initial state, a manual
/// `Rules.endRun`) carries [none].
class Hits {
  Hits({required this.pip, required List<int> ghosts})
    : ghosts = List.unmodifiable(ghosts);

  const Hits._none() : pip = false, ghosts = const [];

  static const none = Hits._none();

  /// Pip was hit: the step ended his run (forced rewind, or lost on the last
  /// run).
  final bool pip;

  /// Indices of the echoes hit on that step, ascending.
  final List<int> ghosts;

  bool get any => pip || ghosts.isNotEmpty;

  @override
  bool operator ==(Object other) {
    if (other is! Hits ||
        other.pip != pip ||
        other.ghosts.length != ghosts.length) {
      return false;
    }
    for (var i = 0; i < ghosts.length; i++) {
      if (other.ghosts[i] != ghosts[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(pip, Object.hashAll(ghosts));

  @override
  String toString() => 'Hits(pip: $pip, ghosts: $ghosts)';
}

/// An immutable snapshot of a level in progress. Collections passed in are
/// wrapped as unmodifiable.
///
/// Invariant: `ghostPositions.length == ghostAlive.length == ghosts.length`.
/// In a lost state the final run is still in [currentRun] (and [tick]), not
/// in [ghosts].
class GameState {
  GameState({
    required this.level,
    required this.runIndex,
    required this.tick,
    required List<Move> currentRun,
    required List<List<Move>> ghosts,
    required this.player,
    required List<Position> ghostPositions,
    required Set<Position> openDoors,
    required this.completedTicks,
    required this.status,
    required Set<Position> collected,
    required Set<Position> holes,
    required List<bool> ghostAlive,
    required List<Position> shades,
    required this.lastHits,
  }) : currentRun = List.unmodifiable(currentRun),
       ghosts = List.unmodifiable(ghosts.map(List<Move>.unmodifiable)),
       ghostPositions = List.unmodifiable(ghostPositions),
       openDoors = Set.unmodifiable(openDoors),
       collected = Set.unmodifiable(collected),
       holes = Set.unmodifiable(holes),
       ghostAlive = List.unmodifiable(ghostAlive),
       shades = List.unmodifiable(shades);

  factory GameState.initial(Level level) => GameState(
    level: level,
    runIndex: 0,
    tick: 0,
    currentRun: const [],
    ghosts: const [],
    player: level.start,
    ghostPositions: const [],
    openDoors: const {},
    completedTicks: 0,
    status: GameStatus.playing,
    collected: const {},
    holes: const {},
    ghostAlive: const [],
    shades: level.shadeStarts,
    lastHits: Hits.none,
  );

  final Level level;

  /// 0-based index of the current run.
  final int runIndex;

  /// Ticks taken in the current run.
  final int tick;
  final List<Move> currentRun;

  /// Completed runs, oldest first.
  final List<List<Move>> ghosts;
  final Position player;

  /// Parallel to [ghosts].
  final List<Position> ghostPositions;
  final Set<Position> openDoors;
  final int completedTicks;
  final GameStatus status;

  /// Sparks Pip has grabbed so far; carried across runs.
  final Set<Position> collected;

  /// Cracked tiles that have collapsed this run. Empty at the start of
  /// every run.
  final Set<Position> holes;

  /// Parallel to [ghosts]: false once that echo was hit. A dead echo stays
  /// where it was hit and no longer moves, presses plates, holds doors,
  /// keeps cracked floor up or attracts Shades. All true at a run's start.
  final List<bool> ghostAlive;

  /// Current Shade positions, parallel to `level.shadeStarts`. Reset to the
  /// starts at every run's start. Shades may share a tile.
  final List<Position> shades;

  /// Who was hit on the step that produced this state.
  final Hits lastHits;

  int get score => completedTicks + tick;
}

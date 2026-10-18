import 'level.dart';
import 'move.dart';
import 'position.dart';

enum GameStatus { playing, won, lost }

/// An immutable snapshot of a level in progress. Collections passed in are
/// wrapped as unmodifiable.
///
/// Invariant: `ghostPositions.length == ghosts.length`. In a lost state the
/// final run is still in [currentRun] (and [tick]), not in [ghosts].
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
  })  : currentRun = List.unmodifiable(currentRun),
        ghosts = List.unmodifiable(ghosts.map(List<Move>.unmodifiable)),
        ghostPositions = List.unmodifiable(ghostPositions),
        openDoors = Set.unmodifiable(openDoors);

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

  int get score => completedTicks + tick;
}

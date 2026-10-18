import 'game_state.dart';
import 'level.dart';
import 'move.dart';
import 'position.dart';
import 'tile.dart';

abstract final class Rules {
  static const maxTicksPerRun = 25;

  /// Advances one tick: ghosts (oldest first) move, then the player. All
  /// moves see the doors from the end of the previous tick; doors are
  /// recomputed once afterwards. A win on the final tick beats the tick cap.
  static GameState step(GameState s, Move m) {
    if (s.status != GameStatus.playing) {
      throw StateError('Cannot step: the level is already ${s.status.name}.');
    }
    final level = s.level;
    final ghostPositions = <Position>[];
    for (var i = 0; i < s.ghosts.length; i++) {
      final recording = s.ghosts[i];
      final move = s.tick < recording.length ? recording[s.tick] : Move.wait;
      ghostPositions.add(_move(level, s.ghostPositions[i], move, s.openDoors));
    }
    final player = _move(level, s.player, m, s.openDoors);

    final next = GameState(
      level: level,
      runIndex: s.runIndex,
      tick: s.tick + 1,
      currentRun: [...s.currentRun, m],
      ghosts: s.ghosts,
      player: player,
      ghostPositions: ghostPositions,
      openDoors: _openDoors(level, [...ghostPositions, player]),
      completedTicks: s.completedTicks,
      status: player == level.exit ? GameStatus.won : GameStatus.playing,
    );
    if (next.status == GameStatus.playing && next.tick == maxTicksPerRun) {
      return endRun(next);
    }
    return next;
  }

  /// Ends the current run. On the last run the level is lost and only the
  /// status changes; otherwise the run becomes a ghost and the next run
  /// starts with every actor back on the start.
  static GameState endRun(GameState s) {
    if (s.status != GameStatus.playing) {
      throw StateError(
          'Cannot end run: the level is already ${s.status.name}.');
    }
    final level = s.level;
    if (s.runIndex == level.runLimit - 1) {
      // Lost: only the status changes, so the final run is counted once.
      return GameState(
        level: level,
        runIndex: s.runIndex,
        tick: s.tick,
        currentRun: s.currentRun,
        ghosts: s.ghosts,
        player: s.player,
        ghostPositions: s.ghostPositions,
        openDoors: s.openDoors,
        completedTicks: s.completedTicks,
        status: GameStatus.lost,
      );
    }
    final ghosts = [...s.ghosts, s.currentRun];
    final completedTicks = s.completedTicks + s.tick;
    final ghostPositions = List.filled(ghosts.length, level.start);
    return GameState(
      level: level,
      runIndex: s.runIndex + 1,
      tick: 0,
      currentRun: const [],
      ghosts: ghosts,
      player: level.start,
      ghostPositions: ghostPositions,
      openDoors: _openDoors(level, [...ghostPositions, level.start]),
      completedTicks: completedTicks,
      status: GameStatus.playing,
    );
  }

  static Position _move(
      Level level, Position from, Move m, Set<Position> openDoors) {
    final target = from + m.delta;
    return _passable(level, target, openDoors) ? target : from;
  }

  static bool _passable(Level level, Position p, Set<Position> openDoors) {
    if (!level.inBounds(p)) return false;
    final tile = level.tileAt(p);
    return switch (tile.kind) {
      TileKind.wall => false,
      TileKind.door => openDoors.contains(p),
      _ => true,
    };
  }

  /// Every door whose plate is under any of [actors], plus every door tile
  /// with an actor on it (no crushing).
  static Set<Position> _openDoors(Level level, List<Position> actors) {
    final open = <Position>{};
    for (final a in actors) {
      final tile = level.tileAt(a);
      if (tile.kind == TileKind.plate) {
        open.addAll(level.doors[tile.channel] ?? const []);
      } else if (tile.kind == TileKind.door) {
        open.add(a);
      }
    }
    return open;
  }
}

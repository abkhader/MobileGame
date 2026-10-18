import 'game_state.dart';
import 'level.dart';
import 'move.dart';
import 'position.dart';
import 'tile.dart';

abstract final class Rules {
  static const maxTicksPerRun = 25;

  /// Advances the player by one tick.
  static GameState step(GameState s, Move m) {
    if (s.status != GameStatus.playing) {
      throw StateError('Cannot step: the level is already ${s.status.name}.');
    }
    final level = s.level;
    var player = s.player;
    final target = player + m.delta;
    if (_passable(level, target, s.openDoors)) player = target;

    return GameState(
      level: level,
      runIndex: s.runIndex,
      tick: s.tick + 1,
      currentRun: [...s.currentRun, m],
      ghosts: s.ghosts,
      player: player,
      ghostPositions: s.ghostPositions,
      openDoors: _openDoors(level, [player]),
      completedTicks: s.completedTicks,
      status: player == level.exit ? GameStatus.won : GameStatus.playing,
    );
  }

  static GameState endRun(GameState s) => throw UnimplementedError();

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

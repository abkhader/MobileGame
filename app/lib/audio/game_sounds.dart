import 'package:echo_core/echo_core.dart';

import '../game/game_controller.dart';
import 'audio_service.dart';

/// The sounds to play for a transition from [before] to [after].
List<Sfx> soundsFor(GameState before, GameState after, GameEvent event) {
  switch (event) {
    case GameEvent.moved:
      return [
        Sfx.move,
        if (_plateNewlyOccupied(before, after)) Sfx.plate,
        if (!_sameDoors(before, after)) Sfx.door,
        if (_sparkCollected(before, after)) Sfx.spark,
      ];
    case GameEvent.runEnded:
    case GameEvent.lost:
      // The 25th beat ends the run, and may still grab a spark.
      return [Sfx.runEnd, if (_sparkCollected(before, after)) Sfx.spark];
    case GameEvent.won:
      return [Sfx.move, Sfx.win];
    case GameEvent.none:
    case GameEvent.restarted:
      return [];
  }
}

Set<Position> _occupiedPlates(GameState s) {
  final actors = {s.player, ...s.ghostPositions};
  return {
    for (final plate in s.level.plates.values)
      if (actors.contains(plate)) plate,
  };
}

bool _plateNewlyOccupied(GameState before, GameState after) =>
    _occupiedPlates(after).difference(_occupiedPlates(before)).isNotEmpty;

/// Pip grabbed a spark on this beat. Rewinds and restarts only ever drop
/// sparks, so they never match.
bool _sparkCollected(GameState before, GameState after) =>
    after.collected.length > before.collected.length;

bool _sameDoors(GameState a, GameState b) =>
    a.openDoors.length == b.openDoors.length &&
    a.openDoors.containsAll(b.openDoors);

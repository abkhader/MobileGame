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
      ];
    case GameEvent.runEnded:
    case GameEvent.lost:
      return [Sfx.runEnd];
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

bool _sameDoors(GameState a, GameState b) =>
    a.openDoors.length == b.openDoors.length &&
    a.openDoors.containsAll(b.openDoors);

import 'package:echo_core/echo_core.dart';

import '../game/game_controller.dart';
import '../game/hits.dart';
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
        ..._dangerSounds(before, after),
        if (_laserWarns(after)) Sfx.laserWarn,
      ];
    case GameEvent.hit:
      // A forced rewind: the zap (or whoomp) replaces the run-end chime.
      return [
        _pipHitSound(before, after),
        if (_sparkCollected(before, after)) Sfx.spark,
      ];
    case GameEvent.runEnded:
    case GameEvent.lost:
      if (event == GameEvent.lost && after.lastHits.pip) {
        return [
          _pipHitSound(before, after),
          if (_sparkCollected(before, after)) Sfx.spark,
        ];
      }
      // The 25th beat ends the run, and may still grab a spark.
      return [Sfx.runEnd, if (_sparkCollected(before, after)) Sfx.spark];
    case GameEvent.won:
      return [Sfx.move, ..._dangerSounds(before, after), Sfx.win];
    case GameEvent.none:
    case GameEvent.restarted:
      return [];
  }
}

Sfx _pipHitSound(GameState before, GameState after) =>
    pipHitOf(before, after)?.cause == HitCause.shade ? Sfx.shade : Sfx.zap;

/// Floor breaking and echoes hit on a same-run step, each sound once.
List<Sfx> _dangerSounds(GameState before, GameState after) {
  if (after.runIndex != before.runIndex) return const [];
  final crumble = after.holes.length > before.holes.length;
  final hits = after.lastHits.ghosts;
  if (!crumble && hits.isEmpty) return const [];
  var zap = false;
  var shade = false;
  for (final i in hits) {
    if (echoHitCause(before, after, i) == HitCause.shade) {
      shade = true;
    } else {
      zap = true;
    }
  }
  return [if (crumble) Sfx.crumble, if (zap) Sfx.echoZap, if (shade) Sfx.shade];
}

/// Some laser shows its warning glow in [s]: it fires on the next beat.
/// Played on forward beats only, so at most once a beat and only while time
/// flows.
bool _laserWarns(GameState s) {
  if (s.status != GameStatus.playing) return false;
  for (final beat in s.level.lasers.values) {
    if (Rules.laserWarns(beat, s.tick)) return true;
  }
  return false;
}

Set<Position> _occupiedPlates(GameState s) {
  // A dead echo presses nothing.
  final actors = {
    s.player,
    for (var i = 0; i < s.ghostPositions.length; i++)
      if (s.ghostAlive[i]) s.ghostPositions[i],
  };
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

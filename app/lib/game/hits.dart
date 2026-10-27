import 'package:echo_core/echo_core.dart';

/// What hit an actor: it decides the sound and the look of the hit.
enum HitCause { laser, hole, shade }

/// Pip's hit on the step that produced a state.
class PipHit {
  const PipHit(this.at, this.cause);

  /// The tile Pip stepped onto when he was hit. After a forced rewind the
  /// state has already put him back on the start, so the board needs this.
  final Position at;
  final HitCause cause;

  @override
  String toString() => 'PipHit($at, ${cause.name})';
}

/// Why an actor that ended a step from [before] on [to] was hit, the step
/// making the run's tick [tick]. Only meaningful for a tile the rules hit.
///
/// A firing laser or a hole explains it (a hole under an actor can only be
/// one from before the step: a tile someone stands on never collapses on
/// that beat); otherwise a Shade caught it.
HitCause hitCause(GameState before, Position to, int tick) {
  if (Rules.onFiringLaser(before.level, to, tick)) return HitCause.laser;
  if (before.holes.contains(to)) return HitCause.hole;
  return HitCause.shade;
}

/// Pip's hit on the step [before] → [after], or null when he was not hit.
/// [after] may be a forced rewind (the next run) or a loss.
PipHit? pipHitOf(GameState before, GameState after) {
  if (!after.lastHits.pip) return null;
  // The step's move is the last of the run it ended.
  final run = after.status == GameStatus.lost
      ? after.currentRun
      : after.ghosts.last;
  if (run.isEmpty) return null;
  final to = Rules.moveTarget(
    before.level,
    before.player,
    run.last,
    before.openDoors,
  );
  return PipHit(to, hitCause(before, to, before.tick + 1));
}

/// Why echo [i] was hit on the same-run step [before] → [after].
HitCause echoHitCause(GameState before, GameState after, int i) =>
    hitCause(before, after.ghostPositions[i], after.tick);

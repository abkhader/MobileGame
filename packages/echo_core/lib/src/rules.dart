import 'game_state.dart';
import 'level.dart';
import 'move.dart';
import 'position.dart';
import 'tile.dart';

/// The game rules. Every public helper below is a pure function of its
/// arguments so the solver can mirror them exactly.
abstract final class Rules {
  static const maxTicksPerRun = 25;

  /// The order a Shade tries its equal-length first steps in.
  static const shadeDirections = [Move.up, Move.right, Move.down, Move.left];

  /// Advances one tick (beat). The order is exact:
  ///
  /// 1. Live ghosts (oldest first) move, then the player. All moves see the
  ///    doors from the end of the previous tick. Pip collects a spark here,
  ///    even if he is hit later in the same beat.
  /// 2. [collapse]: cracked tiles everyone has left become holes.
  /// 3. Each Shade, in list order, takes one [shadeStep] toward the nearest
  ///    live actor, using the same doors as step 1.
  /// 4. Hits ([isHit]): a hit ghost dies for the rest of the run. A hit Pip
  ///    ends the run exactly as [endRun] would at this tick (forced rewind,
  ///    or lost on the last run); a hit beats reaching the exit. Then
  ///    [collapseUnderDissolved]: a crack under an echo that just dissolved
  ///    breaks unless a live actor still stands on it.
  /// 5. Doors are recomputed from the actors still standing.
  ///
  /// Actors are Pip and live ghosts. Shades are not actors: they press no
  /// plates, hold no doors open (a door can close on a Shade, which can
  /// still walk out) and keep no cracked floor up.
  ///
  /// A win on the final tick beats the tick cap.
  static GameState step(GameState s, Move m) {
    if (s.status != GameStatus.playing) {
      throw StateError('Cannot step: the level is already ${s.status.name}.');
    }
    final level = s.level;
    final doors = s.openDoors;
    final tick = s.tick + 1;

    // 1. Movement.
    final ghostPositions = <Position>[];
    for (var i = 0; i < s.ghosts.length; i++) {
      final from = s.ghostPositions[i];
      if (!s.ghostAlive[i]) {
        ghostPositions.add(from);
        continue;
      }
      final recording = s.ghosts[i];
      final move = s.tick < recording.length ? recording[s.tick] : Move.wait;
      ghostPositions.add(_move(level, from, move, doors));
    }
    final player = _move(level, s.player, m, doors);

    final collected =
        level.sparks.contains(player) && !s.collected.contains(player)
        ? {...s.collected, player}
        : s.collected;

    // Live actors before and after the move: Pip first, then live ghosts in
    // index order. This is also the Shades' target priority.
    final before = [s.player, ..._live(s.ghostAlive, s.ghostPositions)];
    final after = [player, ..._live(s.ghostAlive, ghostPositions)];

    // 2. Collapse.
    final holes = collapse(level, s.holes, before, after);

    // 3. Shades.
    final shades = s.shades.isEmpty
        ? s.shades
        : [for (final sh in s.shades) shadeStep(level, doors, sh, after)];

    // 4. Hits.
    bool hit(Position from, Position to) =>
        isHit(level, tick, holes, from, to, s.shades, shades);
    final pipHit = hit(s.player, player);
    var ghostAlive = s.ghostAlive;
    final ghostsHit = <int>[];
    for (var i = 0; i < s.ghosts.length; i++) {
      if (s.ghostAlive[i] && hit(s.ghostPositions[i], ghostPositions[i])) {
        ghostsHit.add(i);
      }
    }
    if (ghostsHit.isNotEmpty) {
      ghostAlive = [...s.ghostAlive];
      for (final i in ghostsHit) {
        ghostAlive[i] = false;
      }
    }
    final hits = pipHit || ghostsHit.isNotEmpty
        ? Hits(pip: pipHit, ghosts: ghostsHit)
        : Hits.none;

    // Live actors not hit this beat. Shades are never actors: they press no
    // plates, hold no doors open and keep no cracked floor up.
    final standing = [
      ..._live(ghostAlive, ghostPositions),
      if (!pipHit) player,
    ];

    // 4b. A dissolving echo counts as leaving its tile.
    final holesAfterHits = ghostsHit.isEmpty
        ? holes
        : collapseUnderDissolved(level, holes, [
            for (final i in ghostsHit) ghostPositions[i],
          ], standing);

    // 5. Doors from the actors still standing.

    final next = GameState(
      level: level,
      runIndex: s.runIndex,
      tick: tick,
      currentRun: [...s.currentRun, m],
      ghosts: s.ghosts,
      player: player,
      ghostPositions: ghostPositions,
      openDoors: _openDoors(level, standing),
      completedTicks: s.completedTicks,
      status: !pipHit && player == level.exit
          ? GameStatus.won
          : GameStatus.playing,
      collected: collected,
      holes: holesAfterHits,
      ghostAlive: ghostAlive,
      shades: shades,
      lastHits: hits,
    );
    if (pipHit ||
        (next.status == GameStatus.playing && next.tick == maxTicksPerRun)) {
      return _endRun(next, hits);
    }
    return next;
  }

  /// Ends the current run (the player's "New echo"). On the last run the
  /// level is lost and only the status (and [GameState.lastHits], which is
  /// cleared) changes; otherwise the run becomes a ghost and the next run
  /// starts with every actor back on the start, every ghost alive, no holes
  /// and every Shade on its start.
  static GameState endRun(GameState s) => _endRun(s, Hits.none);

  /// [endRun] that reports [hits] as the last step's hits: used when a step
  /// ends the run itself (Pip hit, or the tick cap).
  static GameState _endRun(GameState s, Hits hits) {
    if (s.status != GameStatus.playing) {
      throw StateError(
        'Cannot end run: the level is already ${s.status.name}.',
      );
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
        collected: s.collected,
        holes: s.holes,
        ghostAlive: s.ghostAlive,
        shades: s.shades,
        lastHits: hits,
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
      collected: s.collected,
      holes: const {},
      ghostAlive: List.filled(ghosts.length, true),
      shades: level.shadeStarts,
      lastHits: hits,
    );
  }

  /// Whether a laser with [beat] (1, 2 or 3) fires after the move that makes
  /// the run's tick equal [tick]: on ticks `n >= 1` with
  /// `n % 3 == beat % 3`. So beat 1 fires on 1, 4, 7…, beat 2 on 2, 5, 8…
  /// and beat 3 on 3, 6, 9….
  static bool laserFires(int beat, int tick) =>
      tick >= 1 && tick % 3 == beat % 3;

  /// Whether a laser with [beat] shows its warning glow in a state at
  /// [tick], i.e. it fires after the next move: `(tick + 1) % 3 == beat % 3`.
  static bool laserWarns(int beat, int tick) => (tick + 1) % 3 == beat % 3;

  /// Whether [p] is a laser tile firing at [tick] (see [laserFires]).
  static bool onFiringLaser(Level level, Position p, int tick) {
    final beat = level.lasers[p];
    return beat != null && laserFires(beat, tick);
  }

  /// Beat step 2. Returns [holes] plus every cracked tile, not already a
  /// hole, that was under at least one of [before] (live actors at the start
  /// of the beat) and is under none of [after] (the same actors after they
  /// moved). Dead ghosts are not actors; an echo dissolving on a crack is
  /// handled after the hits by [collapseUnderDissolved]. Returns [holes]
  /// itself when nothing collapses.
  static Set<Position> collapse(
    Level level,
    Set<Position> holes,
    List<Position> before,
    List<Position> after,
  ) {
    Set<Position>? result;
    for (final p in before) {
      if (level.cracked.contains(p) &&
          !holes.contains(p) &&
          !after.contains(p)) {
        (result ??= {...holes}).add(p);
      }
    }
    return result ?? holes;
  }

  /// Beat step 4b, after the hits: a dissolving echo counts as leaving its
  /// tile. Returns [holes] plus every cracked tile, not already a hole, under
  /// one of [dissolved] (echoes hit this beat) and under none of [standing]
  /// (live actors not hit this beat). Returns [holes] itself when nothing
  /// collapses.
  ///
  /// In [step] every hit is decided by tile, so a live actor sharing a
  /// dissolving echo's tile is always hit too; [standing] only matters for
  /// a hit Pip, whose run ends anyway. It is kept so the rule reads as
  /// designed.
  static Set<Position> collapseUnderDissolved(
    Level level,
    Set<Position> holes,
    List<Position> dissolved,
    List<Position> standing,
  ) {
    Set<Position>? result;
    for (final p in dissolved) {
      if (level.cracked.contains(p) &&
          !holes.contains(p) &&
          !standing.contains(p)) {
        (result ??= {...holes}).add(p);
      }
    }
    return result ?? holes;
  }

  /// Beat step 3 for one Shade at [shade]. [lights] are the live actors
  /// after the move, in priority order: Pip first, then live ghosts by
  /// ascending index. [openDoors] are the doors used for movement this beat.
  ///
  /// The Shade targets the light at the smallest walking distance
  /// ([shadeDistances]; walls and closed doors block, holes and lasers do
  /// not), ties going to the earlier light. It then takes the first of
  /// [shadeDirections] whose tile is passable and one step closer to that
  /// target. At distance 0 (already on a light) or with no reachable light it
  /// waits. Other Shades never block it.
  static Position shadeStep(
    Level level,
    Set<Position> openDoors,
    Position shade,
    List<Position> lights,
  ) {
    var best = -1;
    List<int>? field;
    for (final light in lights) {
      final f = shadeDistances(level, openDoors, light);
      final d = f[_index(level, shade)];
      if (d >= 0 && (best < 0 || d < best)) {
        best = d;
        field = f;
      }
    }
    if (best <= 0) return shade;
    for (final dir in shadeDirections) {
      final n = shade + dir.delta;
      if (_passable(level, n, openDoors) &&
          field![_index(level, n)] == best - 1) {
        return n;
      }
    }
    throw StateError('unreachable: a shortest path has a first step');
  }

  /// Walking distances to [target], indexed `y * width + x`: the fewest
  /// single steps from that tile to [target] where every tile stepped into
  /// is passable (in bounds, not a wall, not a door outside [openDoors]).
  /// The starting tile itself need not be passable. -1 means unreachable.
  static List<int> shadeDistances(
    Level level,
    Set<Position> openDoors,
    Position target,
  ) {
    final dist = List.filled(level.width * level.height, -1);
    final queue = [target];
    dist[_index(level, target)] = 0;
    for (var head = 0; head < queue.length; head++) {
      final v = queue[head];
      // Every predecessor reaches v by stepping into it.
      if (!_passable(level, v, openDoors)) continue;
      final d = dist[_index(level, v)] + 1;
      for (final dir in shadeDirections) {
        final u = v + dir.delta;
        if (!level.inBounds(u) || dist[_index(level, u)] >= 0) continue;
        dist[_index(level, u)] = d;
        queue.add(u);
      }
    }
    return dist;
  }

  /// Whether an actor that moved [from] → [to] this beat is caught by a
  /// Shade that moved `shadesFrom[k]` → `shadesTo[k]`: a Shade ends on [to],
  /// or a Shade and the actor swapped tiles.
  ///
  /// Under [step]'s order a pure swap cannot happen (an actor stepping onto a
  /// Shade is at distance 0, so that Shade waits and lands on it anyway); the
  /// swap clause is kept so the rule reads as designed.
  static bool caughtByShade(
    Position from,
    Position to,
    List<Position> shadesFrom,
    List<Position> shadesTo,
  ) {
    for (var k = 0; k < shadesTo.length; k++) {
      if (shadesTo[k] == to) return true;
      if (shadesFrom[k] == to && shadesTo[k] == from) return true;
    }
    return false;
  }

  /// Beat step 4 for one live actor that moved [from] → [to], with [tick] the
  /// new tick and [holes] after step 2: it is hit if on a firing laser, in a
  /// hole, or [caughtByShade].
  static bool isHit(
    Level level,
    int tick,
    Set<Position> holes,
    Position from,
    Position to,
    List<Position> shadesFrom,
    List<Position> shadesTo,
  ) =>
      onFiringLaser(level, to, tick) ||
      holes.contains(to) ||
      caughtByShade(from, to, shadesFrom, shadesTo);

  static Iterable<Position> _live(
    List<bool> alive,
    List<Position> positions,
  ) sync* {
    for (var i = 0; i < positions.length; i++) {
      if (alive[i]) yield positions[i];
    }
  }

  static int _index(Level level, Position p) => p.y * level.width + p.x;

  static Position _move(
    Level level,
    Position from,
    Move m,
    Set<Position> openDoors,
  ) {
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
  /// with an actor on it (no crushing). Shades are not actors and are never
  /// passed here.
  static Set<Position> _openDoors(Level level, Iterable<Position> actors) {
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

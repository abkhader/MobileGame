import 'package:echo_core/echo_core.dart';

/// An independent reference for levels with dangers. It shares no code with
/// the solver: every world is a real [GameState] and every beat is a real
/// [Rules.step], so lasers, collapse, Shades, hits and forced rewinds are
/// exactly the rules engine's.
///
/// An `m`-run play is `m` worlds stepped tick by tick: world `k` is the game
/// during run `k`, holding the ghosts of runs `0..k-1` and run `k`'s player.
/// Each live run picks a move or (before the final run) ends; its choice is
/// its player's move in its own world and its ghost's move in every later
/// world. [Rules.step] only reads a ghost's recording at the current tick
/// (and its length), so each world's state is rebuilt with filler recordings
/// that hold just this tick's choice: a run that has ended (or ends now) gets
/// a recording that is already over, so its ghost waits.
///
/// A world stops when its run ends: by choice, or when [Rules.step] ends it
/// (Pip hit: forced rewind; the tick cap). A hit of the final run's player
/// loses that play. The final world stops when its player wins; the other
/// worlds keep going (an earlier run was played in full before the final
/// one). A win in an earlier world is a play with fewer runs, not this one.
///
/// There is no reduction at all: the state is every running world's whole
/// [GameState] (minus recordings and score), every move and every end is
/// tried at every tick, and states are only merged within one tick.
class DangerReference {
  DangerReference(this.level)
    : _asLastRun = [
        for (var k = 0; k < level.runLimit; k++) _withRunLimit(level, k + 1),
      ];

  final Level level;

  /// [level] with run `k` as its last run, per `k`: then a step that ends
  /// run `k` (Pip hit, tick cap) reports it lost and keeps every position.
  final List<Level> _asLastRun;

  /// The minimum total score over every winning play with at most
  /// `runLimit` runs, or null when none wins. Throws [ReferenceTooBig] when
  /// one tick holds more than [maxStates] states.
  int? best({int maxStates = 1 << 62}) {
    int? best;
    for (var m = 1; m <= level.runLimit; m++) {
      final found = _search(m, maxStates, null, const {});
      if (found != null && (best == null || found < best)) best = found;
    }
    return best;
  }

  /// The minimum total score over every winning play with exactly [m] runs.
  int? bestWithRuns(int m, {int maxStates = 1 << 62}) =>
      _search(m, maxStates, null, const {});

  /// Whether some winning play with at most `runLimit` runs has the player of
  /// a run in [collectors] collect [spark] (step onto it while that run is
  /// live, as [Rules.step] counts it).
  ///
  /// [stopAtWin] instead ends every play at the final run's win, as if the
  /// earlier runs stopped there too: tests use it to show where that
  /// shortcut would be wrong.
  bool collects(
    Position spark,
    Set<int> collectors, {
    int maxStates = 1 << 62,
    bool stopAtWin = false,
  }) {
    for (var m = 1; m <= level.runLimit; m++) {
      if (_search(m, maxStates, spark, collectors, stopAtWin: stopAtWin) !=
          null) {
        return true;
      }
    }
    return false;
  }

  /// Whether some winning play with at most `runLimit` runs never puts any
  /// actor (a player or a live ghost, in any world) on [cell].
  bool avoids(Position cell, {int maxStates = 1 << 62}) {
    for (var m = 1; m <= level.runLimit; m++) {
      if (_search(m, maxStates, null, const {}, avoid: cell) != null) {
        return true;
      }
    }
    return false;
  }

  /// Cheapest winning [m]-run play (with the spark collected when [spark]
  /// is given), or null.
  int? _search(
    int m,
    int maxStates,
    Position? spark,
    Set<int> collectors, {
    Position? avoid,
    bool stopAtWin = false,
  }) {
    final first = _Joint(
      worlds: [for (var k = 0; k < m; k++) _world(k)],
      won: false,
      got: false,
    );
    var layer = <String, (_Joint, int)>{first.key: (first, 0)};
    int? best;
    for (var tick = 0; tick < Rules.maxTicksPerRun; tick++) {
      final next = <String, (_Joint, int)>{};
      for (final (joint, cost) in layer.values) {
        final live = [for (var j = 0; j < m; j++) joint.worlds[j] != null];
        final choice = List.filled(m, 0);
        void expand(int j) {
          if (j < m) {
            if (!live[j]) {
              choice[j] = _gone;
              expand(j + 1);
              return;
            }
            for (var c = 0; c < (j < m - 1 ? 6 : 5); c++) {
              choice[j] = c;
              expand(j + 1);
            }
            return;
          }
          var stepCost = 0;
          for (var j = 0; j < m; j++) {
            if (choice[j] < _end) stepCost++;
          }
          final worlds = List<GameState?>.filled(m, null);
          var won = joint.won;
          var got = joint.got;
          for (var k = 0; k < m; k++) {
            final w = joint.worlds[k];
            if (w == null || choice[k] == _end) continue;
            final s = _rebuild(w, tick, choice, k);
            final after = Rules.step(s, Move.values[choice[k]]);
            if (avoid != null) {
              if (after.player == avoid) return;
              for (var i = 0; i < k; i++) {
                if (s.ghostAlive[i] && after.ghostPositions[i] == avoid) {
                  return;
                }
              }
            }
            if (spark != null &&
                collectors.contains(k) &&
                after.collected.contains(spark)) {
              got = true;
            }
            if (after.status == GameStatus.won) {
              if (k < m - 1) return; // a win with fewer runs
              won = true;
              continue;
            }
            // Pip hit or the tick cap: world k's level copy has run k as its
            // last run, so the step reports it lost. For the final run that
            // is no win; an earlier run is over (a forced rewind).
            if (after.status == GameStatus.lost) {
              if (k == m - 1) return;
              continue;
            }
            worlds[k] = after;
          }
          final total = cost + stepCost;
          if (won && (spark == null || got)) {
            if (best == null || total < best!) best = total;
            return;
          }
          if (won && stopAtWin) return;
          final joined = _Joint(worlds: worlds, won: won, got: got);
          // Nothing left that could still collect.
          if (spark != null && !got) {
            var any = false;
            for (final c in collectors) {
              if (c < m && worlds[c] != null) any = true;
            }
            if (!any) return;
          }
          final key = joined.key;
          final prior = next[key];
          if (prior == null || total < prior.$2) next[key] = (joined, total);
          if (next.length > maxStates) throw const ReferenceTooBig();
        }

        expand(0);
      }
      layer = next;
      if (layer.isEmpty) break;
    }
    return best;
  }

  /// World [k]'s state at [tick] with filler recordings: ghost `i` acts
  /// `choice[i]` this tick, or waits when its run has ended or ends now.
  GameState _rebuild(GameState w, int tick, List<int> choice, int k) =>
      GameState(
        level: _asLastRun[k],
        runIndex: k,
        tick: tick,
        currentRun: List.filled(tick, Move.wait),
        ghosts: [
          for (var i = 0; i < k; i++)
            [
              ...List.filled(tick, Move.wait),
              if (choice[i] < _end) Move.values[choice[i]],
            ],
        ],
        player: w.player,
        ghostPositions: w.ghostPositions,
        openDoors: w.openDoors,
        completedTicks: 0,
        status: GameStatus.playing,
        collected: const {},
        holes: w.holes,
        ghostAlive: w.ghostAlive,
        shades: w.shades,
        lastHits: Hits.none,
      );

  /// A fresh world [ghosts] ghosts deep: everyone on the start.
  GameState _world(int ghosts) => GameState(
    level: level,
    runIndex: ghosts,
    tick: 0,
    currentRun: const [],
    ghosts: List.filled(ghosts, const []),
    player: level.start,
    ghostPositions: List.filled(ghosts, level.start),
    openDoors: const {},
    completedTicks: 0,
    status: GameStatus.playing,
    collected: const {},
    holes: const {},
    ghostAlive: List.filled(ghosts, true),
    shades: level.shadeStarts,
    lastHits: Hits.none,
  );
}

Level _withRunLimit(Level l, int runLimit) => Level(
  id: l.id,
  name: l.name,
  runLimit: runLimit,
  grid: [
    for (var y = 0; y < l.height; y++)
      [for (var x = 0; x < l.width; x++) l.tileAt(Position(x, y))],
  ],
  start: l.start,
  exit: l.exit,
  plates: l.plates,
  doors: l.doors,
  sparks: l.sparks,
  lasers: l.lasers,
  cracked: l.cracked,
  shadeStarts: l.shadeStarts,
);

// Choice codes: 0-4 index Move.values (up, down, left, right, wait), then
// end (before acting this tick) and gone (ended earlier).
const _end = 5;
const _gone = 6;

class _Joint {
  _Joint({required this.worlds, required this.won, required this.got});

  /// Per run: its world while it is running, else null.
  final List<GameState?> worlds;
  final bool won;
  final bool got;

  String get key {
    final b = StringBuffer('${won ? 1 : 0}${got ? 1 : 0}|');
    for (final w in worlds) {
      if (w == null) {
        b.write('-|');
        continue;
      }
      String ps(Iterable<Position> ps) =>
          ps.map((p) => '${p.x},${p.y}').join(' ');
      List<Position> sorted(Set<Position> s) =>
          s.toList()..sort((a, b) => a.y != b.y ? a.y - b.y : a.x - b.x);
      b
        ..write(ps([w.player]))
        ..write(';')
        ..write(ps(w.ghostPositions))
        ..write(';')
        ..write(w.ghostAlive.map((a) => a ? 1 : 0).join())
        ..write(';')
        ..write(ps(sorted(w.holes)))
        ..write(';')
        ..write(ps(w.shades))
        ..write(';')
        ..write(ps(sorted(w.openDoors)))
        ..write('|');
    }
    return b.toString();
  }
}

class ReferenceTooBig implements Exception {
  const ReferenceTooBig();
}

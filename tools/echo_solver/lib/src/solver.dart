import 'dart:collection';
import 'dart:typed_data';

import 'package:echo_core/echo_core.dart';

part 'spark_proofs.dart';
part 'tracked_runs.dart';

sealed class SolveResult {
  const SolveResult();
}

/// The level's minimum total score and a solution reaching it: every run,
/// including the winning one.
class Solved extends SolveResult {
  const Solved(this.bestScore, this.solution, {this.nodes = 0});

  final int bestScore;
  final List<List<Move>> solution;

  /// Search effort: joint states expanded by [solve]; `Rules.step` calls
  /// made by [solveSequential].
  final int nodes;
}

class Unsolvable extends SolveResult {
  const Unsolvable();
}

/// The search expanded more than the allowed number of nodes.
class BudgetExceeded extends SolveResult {
  const BudgetExceeded(this.nodes);

  final int nodes;
}

class _BudgetAbort implements Exception {
  const _BudgetAbort();
}

/// Finds the minimum total score and the fewest runs reaching it.
///
/// An `m`-run play is searched as `m` parallel worlds stepped tick by tick:
/// world `k` holds the ghosts of runs `0..k-1` and the live player of run
/// `k`, and run `j`'s action at a tick is applied at once to its player in
/// world `j` and to its ghost in every later world. The future depends only
/// on the joint state (tick, live runs, every actor in every live world), so
/// an A* search over joint states is exact and finite. [maxNodes] caps the
/// joint states expanded, across all run counts.
///
/// A level with dangers (lasers, cracked floor or Shades) is searched by
/// [solveTracked]'s every-world search; any other level by [_JointRuns],
/// exactly as before dangers existed.
SolveResult solve(Level level, {int maxNodes = 30000000}) =>
    _JointSearch(level, maxNodes, tracked: hasDangers(level)).solve();

/// Whether [level] has lasers, cracked floor or Shades.
bool hasDangers(Level level) =>
    level.lasers.isNotEmpty ||
    level.cracked.isNotEmpty ||
    level.shadeStarts.isNotEmpty;

/// [solve] with the every-world search ([_TrackedRuns]) on any level: exact
/// with or without dangers, and the search [solve] uses for levels with
/// dangers. Tests compare it with [solve] on levels without dangers.
///
/// With [avoid], only plays in which no actor (a player or a live ghost, in
/// any world) ever stands on that cell count: Solved means some winning
/// play within `runLimit` runs never steps an actor onto it (its best score
/// and solution are the cheapest such play's). Plays are compared up to the
/// final run's win: an earlier run still going then can end at that tick
/// instead, which leaves the final world unchanged.
SolveResult solveTracked(
  Level level, {
  int maxNodes = 30000000,
  Position? avoid,
}) => _JointSearch(
  level,
  maxNodes,
  tracked: true,
  avoid: avoid == null ? -1 : avoid.y * level.width + avoid.x,
).solve();

/// The previous run-by-run iterative-deepening search, kept only as a test
/// reference for [solve]. [prune] switches its useless-run rule so tests can
/// compare the pruned search against the unpruned one. [Solved.nodes] here
/// counts `Rules.step` calls.
///
/// On a level with dangers the useless-run rule is off (a run that touches
/// no plate or door may still lure a Shade, hold up a crack, or end on a
/// hit), a run may also end at tick 0 (its echo waiting on the start is a
/// light for Shades), and the last run's memo key also holds the holes, the
/// Shades and which ghosts are alive.
SolveResult solveSequential(
  Level level, {
  int maxNodes = 30000000,
  bool prune = true,
}) => _solve(level, maxNodes, prune: prune);

SolveResult _solve(Level level, int maxNodes, {required bool prune}) {
  final search = _Search(level, maxNodes, prune: prune);
  final d0 = search.dist(level.start);
  if (d0 == _Search.unreachable) return const Unsolvable();
  try {
    for (
      var bound = d0;
      bound <= level.runLimit * Rules.maxTicksPerRun;
      bound++
    ) {
      final win = search.run(bound);
      if (win != null) {
        if (win.score != bound) {
          throw StateError(
            'solver invariant broken: score ${win.score} != bound $bound',
          );
        }
        return Solved(win.score, [
          ...win.ghosts,
          win.currentRun,
        ], nodes: search.nodes);
      }
    }
  } on _BudgetAbort {
    return BudgetExceeded(search.nodes);
  }
  return const Unsolvable();
}

class _Search {
  _Search(this.level, this.maxNodes, {required bool prune})
    : dangers = hasDangers(level),
      prune = prune && !hasDangers(level) {
    _computeDistances();
    d0 = dist(level.start);
  }

  static const unreachable = 1 << 30;

  final Level level;
  final int maxNodes;
  final bool prune;
  final bool dangers;
  late final int d0;
  int nodes = 0;
  late final List<int> _dist;

  static const _moveOrder = [
    Move.up,
    Move.down,
    Move.left,
    Move.right,
    Move.wait,
  ];

  int dist(Position p) => _dist[p.y * level.width + p.x];

  /// BFS from the exit; doors count as floor, walls are blocked.
  void _computeDistances() {
    final d = List.filled(level.width * level.height, unreachable);
    final queue = Queue<Position>()..add(level.exit);
    d[level.exit.y * level.width + level.exit.x] = 0;
    while (queue.isNotEmpty) {
      final p = queue.removeFirst();
      final here = d[p.y * level.width + p.x];
      for (final m in _moveOrder) {
        final q = p + m.delta;
        if (!_walkable(q)) continue;
        final i = q.y * level.width + q.x;
        if (d[i] == unreachable) {
          d[i] = here + 1;
          queue.add(q);
        }
      }
    }
    _dist = d;
  }

  bool _walkable(Position p) =>
      level.inBounds(p) && level.tileAt(p).kind != TileKind.wall;

  GameState? run(int bound) {
    final root = GameState.initial(level);
    return _dfs(
      root,
      bound,
      level.runLimit == 1 ? <Object, int>{} : null,
      false,
    );
  }

  GameState _step(GameState s, Move m) {
    if (++nodes > maxNodes) throw const _BudgetAbort();
    return Rules.step(s, m);
  }

  /// True when moving [move] from [from] targets a plate or a door, even if
  /// the move ends up blocked: a ghost replaying it may later get through.
  bool _touchesPlateOrDoor(Position from, Move move) {
    if (!prune) return true;
    if (move == Move.wait) return false;
    final kind = level.tileAt(from + move.delta).kind;
    return kind == TileKind.plate || kind == TileKind.door;
  }

  /// [memo] is non-null exactly while in the last run. [interacted] says
  /// whether the current run has targeted a plate or door yet; a run that
  /// never has replays as a ghost that cannot affect any other actor, so
  /// ending it is never part of a cheapest solution.
  GameState? _dfs(
    GameState state,
    int bound,
    Map<Object, int>? memo,
    bool interacted,
  ) {
    if (state.status == GameStatus.won) return state;
    if (state.status == GameStatus.lost) return null;
    final remaining = bound - state.score;
    final lastRun = state.runIndex == level.runLimit - 1;
    if (dist(state.player) > remaining && (lastRun || remaining < d0)) {
      return null;
    }
    if (lastRun) {
      final key = _key(state);
      final seen = memo![key];
      if (seen != null && seen >= remaining) return null;
      memo[key] = remaining;
    }
    for (final move in _moveOrder) {
      if (!_walkable(state.player + move.delta)) continue;
      final touched = interacted || _touchesPlateOrDoor(state.player, move);
      final next = _step(state, move);
      final ended = next.runIndex > state.runIndex;
      if (ended && !touched) continue;
      final win = _dfs(
        next,
        bound,
        _memoFor(state, next, memo),
        ended ? false : touched,
      );
      if (win != null) return win;
    }
    if ((interacted || dangers) &&
        !lastRun &&
        (state.tick > 0 ? state.currentRun.last != Move.wait : dangers) &&
        remaining >= d0) {
      final next = Rules.endRun(state);
      final win = _dfs(next, bound, _memoFor(state, next, memo), false);
      if (win != null) return win;
    }
    return null;
  }

  /// A fresh memo for every entry into the last run; the current one while
  /// staying in it; none before it.
  Map<Object, int>? _memoFor(
    GameState from,
    GameState to,
    Map<Object, int>? memo,
  ) {
    if (to.runIndex == level.runLimit - 1) {
      return to.runIndex > from.runIndex ? <Object, int>{} : memo;
    }
    return null;
  }

  /// Canonical packed key of tick, player and every ghost position; with
  /// dangers also which ghosts are alive, the holes and the Shades.
  Object _key(GameState s) {
    final cells = level.width * level.height;
    if (dangers) {
      String at(Position p) => '${p.y * level.width + p.x}';
      final holes = [for (final h in s.holes) at(h)]..sort();
      return [
        s.tick,
        at(s.player),
        s.ghostPositions.map(at).join(','),
        s.ghostAlive.map((a) => a ? 1 : 0).join(),
        holes.join(','),
        s.shades.map(at).join(','),
      ].join(';');
    }
    var key = s.tick;
    key = key * cells + s.player.y * level.width + s.player.x;
    for (final g in s.ghostPositions) {
      key = key * cells + g.y * level.width + g.x;
    }
    return key;
  }
}

/// Option codes per run in a joint transition: 0-4 index [_jointMoves], then
/// [_end] (the run ends before acting this tick) and [_gone] (it ended
/// earlier).
const _jointMoves = [Move.up, Move.down, Move.left, Move.right, Move.wait];
const _wait = 4;
const _end = 5;
const _gone = 6;
const _unreachable = 1 << 30;

class _JointSearch {
  _JointSearch(
    this.level,
    this.maxNodes, {
    this.tracked = false,
    this.avoid = -1,
  }) : cells = level.width * level.height {
    _target = Int32List(cells * 4);
    _doorChannel = Int32List(cells)..fillRange(0, cells, -1);
    _plateChannel = Int32List(cells)..fillRange(0, cells, -1);
    final channels = <String, int>{};
    int channel(String c) => channels.putIfAbsent(c, () => channels.length);
    for (var c = 0; c < cells; c++) {
      final p = _pos(c);
      final tile = level.tileAt(p);
      if (tile.kind == TileKind.door) _doorChannel[c] = channel(tile.channel!);
      if (tile.kind == TileKind.plate) {
        _plateChannel[c] = channel(tile.channel!);
      }
      for (var d = 0; d < 4; d++) {
        final q = p + _jointMoves[d].delta;
        _target[c * 4 + d] = _walkable(q) ? _index(q) : -1;
      }
    }
    _startIndex = _index(level.start);
    _matters = [
      for (var c = 0; c < cells; c++)
        _plateChannel[c] >= 0 || _doorChannel[c] >= 0,
    ];
    _dist = Int32List(cells)..fillRange(0, cells, _unreachable);
    final queue = Queue<int>()..add(_index(level.exit));
    _dist[_index(level.exit)] = 0;
    while (queue.isNotEmpty) {
      final c = queue.removeFirst();
      for (var d = 0; d < 4; d++) {
        final t = _target[c * 4 + d];
        if (t >= 0 && _dist[t] == _unreachable) {
          _dist[t] = _dist[c] + 1;
          queue.add(t);
        }
      }
    }
  }

  final Level level;
  final int maxNodes;
  final int cells;
  int nodes = 0;

  /// Search with [_TrackedRuns] (every world tracked, dangers exact) instead
  /// of [_JointRuns].
  final bool tracked;

  /// A cell no actor may enter ([solveTracked]), or -1.
  final int avoid;

  late final _DangerTables _dangers = _DangerTables(this);

  /// Cell reached by direction `d` (0-3) from cell `c` at `c * 4 + d`, or -1
  /// for a wall or the grid edge. Doors are resolved per world.
  late final Int32List _target;
  late final Int32List _doorChannel;
  late final Int32List _plateChannel;
  late final int _startIndex;

  /// Plates and doors: the only tiles where a waiting actor has an effect.
  late final List<bool> _matters;

  /// BFS distance to the exit with doors as floor: a consistent heuristic,
  /// since the final player moves at most one tile per tick of cost >= 1.
  late final Int32List _dist;

  Position _pos(int c) => Position(c % level.width, c ~/ level.width);
  int _index(Position p) => p.y * level.width + p.x;
  bool _walkable(Position p) =>
      level.inBounds(p) && level.tileAt(p).kind != TileKind.wall;

  SolveResult solve() {
    // The final player moves at most one tile per tick and a run lasts at
    // most maxTicksPerRun ticks, so a farther (or unreachable) exit cannot be
    // reached. This also keeps the start's h inside the A* bucket list.
    if (_dist[_index(level.start)] > Rules.maxTicksPerRun) {
      return const Unsolvable();
    }
    Solved? best;
    try {
      for (var m = 1; m <= level.runLimit; m++) {
        final found = tracked
            ? _TrackedRuns(
                this,
                _dangers,
                m,
                avoid: avoid,
              ).cheapest(best?.bestScore)
            : _JointRuns(
                this,
                m,
                fewerRunsWin: best != null,
              ).cheapest(best?.bestScore);
        if (found != null) best = found;
      }
    } on _BudgetAbort {
      return BudgetExceeded(nodes);
    }
    if (best == null) return const Unsolvable();
    return Solved(best.bestScore, best.solution, nodes: nodes);
  }
}

/// A* over the joint states of every `m`-run play.
///
/// Actors are stored world by world: world `k` starts at `k * (k + 1) / 2`
/// and holds runs `0..k` (run `k` being its player). A *key* packs the
/// live-run mask (non-final runs; the final run is live until it wins) and
/// every actor position; the tick is not part of it. A *label* is a key
/// reached at a given tick with a given cost g.
///
/// Exact reductions:
/// - A world whose run has ended is frozen and irrelevant: its slots are 0.
///   So are the slots of every earlier world when no play with fewer runs
///   wins (see [fewerRunsWin]).
/// - A ghost whose run has ended waits forever; on a tile that is neither a
///   plate nor a door it affects nothing, so it is stored on the start tile
///   (which is neither either).
/// - Transitions do not depend on the tick, so a label is dominated by a
///   label of the same key with no later tick and no higher cost: every
///   continuation of the later one also works from the earlier one. Labels of
///   one key share h, so A* closes them in order of g, and a label is
///   dominated exactly when its key already has a closed label with a tick no
///   later than its own.
class _JointRuns {
  _JointRuns(this.s, this.m, {required this.fewerRunsWin})
    : actors = m * (m + 1) ~/ 2 {
    final posBits = (s.cells - 1).bitLength.clamp(1, 62);
    final widths = [if (m > 1) m - 1, for (var i = 0; i < actors; i++) posBits];
    var word = 0;
    var used = 0;
    for (final w in widths) {
      if (used + w > 62) {
        word++;
        used = 0;
      }
      _fieldWord.add(word);
      _fieldShift.add(used);
      used += w;
    }
    _posMask = (1 << posBits) - 1;
    _aliveMask = (1 << (m - 1)) - 1;
    words = word + 1;
    _keys = Int64List(words << 10);
  }

  final _JointSearch s;
  final int m;

  /// Whether some play with fewer than [m] runs wins. When none does, no
  /// earlier world's player can ever reach the exit (the first world whose
  /// player did would be such a play), so only the final world is tracked.
  final bool fewerRunsWin;
  final int actors;
  late final int words;

  final _fieldWord = <int>[];
  final _fieldShift = <int>[];
  late final int _posMask;
  late final int _aliveMask;

  // Per key, indexed by key id.
  late Int64List _keys;
  var _keyH = Int32List(1 << 10);
  var _keyClosedTick = Int32List(1 << 10);
  var _keyFirstLabel = Int32List(1 << 10);
  var _keyCount = 0;

  /// Open-addressing hash table of key id + 1 (0 = empty).
  var _table = Int32List(1 << 11);

  // Per label, indexed by label id.
  var _labelKey = Int32List(1 << 10);
  var _labelTick = Int32List(1 << 10);
  var _labelG = Int32List(1 << 10);
  var _labelParent = Int32List(1 << 10);
  var _labelAction = Int32List(1 << 10);
  var _labelNext = Int32List(1 << 10);
  var _labelClosed = Uint8List(1 << 10);
  var _labelCount = 0;

  int _offset(int world) => world * (world + 1) ~/ 2;
  int _posField(int slot) => (m > 1 ? 1 : 0) + slot;

  /// Cheapest `m`-run play costing less than [bound] (any cost when null),
  /// or null if there is none.
  Solved? cheapest(int? bound) {
    final start = s._index(s.level.start);
    final exit = s._index(s.level.exit);
    final buckets = List.generate(Rules.maxTicksPerRun * m + 2, (_) => <int>[]);
    final key = Int64List(words);
    final pos = Int32List(actors)..fillRange(0, actors, start);
    _packAlive(key, _aliveMask);
    for (var k = 0; k < m; k++) {
      if (!_tracked(k, _aliveMask)) continue;
      for (var i = 0; i <= k; i++) {
        _packPos(key, _offset(k) + i, start);
      }
    }
    final firstKey = _keyId(key, s._dist[start]);
    final first = _label(firstKey, 0, 0, -1, 0);
    buckets[_keyH[firstKey]].add(first);

    final moved = Int32List(actors * 5);
    final options = List.generate(m, (_) => <int>[]);
    // Key bits of each slot for each of its run's options (by option code).
    final contrib = Int64List(actors * 7);
    final choice = Int32List(m);
    final cursor = Int32List(m);
    final finalSlot = _offset(m - 1) + m - 1;

    for (var f = 0; f < buckets.length; f++) {
      if (bound != null && f >= bound) return null;
      final bucket = buckets[f];
      for (var b = 0; b < bucket.length; b++) {
        final label = bucket[b];
        if (_labelClosed[label] != 0) continue;
        final k0 = _labelKey[label];
        final g0 = _labelG[label];
        if (g0 + _keyH[k0] != f) continue;
        _labelClosed[label] = 1;
        final tick = _labelTick[label];
        if (_keyClosedTick[k0] <= tick) continue;
        _keyClosedTick[k0] = tick;
        if (++s.nodes > s.maxNodes) throw const _BudgetAbort();
        if (_keyH[k0] == 0) return _rebuild(label);
        if (tick >= Rules.maxTicksPerRun) continue;
        final alive = _decode(k0, pos);

        // Every live actor's result for every move, against its world's
        // doors from the end of the previous tick.
        for (var k = 0; k < m; k++) {
          if (!_tracked(k, alive)) continue;
          final off = _offset(k);
          var pressed = 0;
          for (var i = 0; i <= k; i++) {
            final ch = s._plateChannel[pos[off + i]];
            if (ch >= 0) pressed |= 1 << ch;
          }
          for (var i = 0; i <= k; i++) {
            final from = pos[off + i];
            for (var d = 0; d < 4; d++) {
              var to = s._target[from * 4 + d];
              if (to < 0) {
                to = from;
              } else {
                final ch = s._doorChannel[to];
                if (ch >= 0 &&
                    pressed & (1 << ch) == 0 &&
                    !_occupied(pos, off, k, to)) {
                  to = from;
                }
              }
              moved[(off + i) * 5 + d] = to;
            }
            moved[(off + i) * 5 + _wait] = from;
          }
        }

        // Each run's options. A direction into a wall or the grid edge for
        // every copy of the run is the same as waiting, so it is skipped.
        for (var j = 0; j < m; j++) {
          final o = options[j]..clear();
          if (!_live(j, alive)) {
            o.add(_gone);
            continue;
          }
          for (var d = 0; d < 4; d++) {
            var useful = false;
            for (var k = j; k < m && !useful; k++) {
              if (_tracked(k, alive)) {
                useful = s._target[pos[_offset(k) + j] * 4 + d] >= 0;
              }
            }
            if (useful) o.add(d);
          }
          o.add(_wait);
          if (j < m - 1) o.add(_end);
        }

        // Key bits per slot and option. A ghost whose run has ended (or
        // ends now) waits; it is canonicalized where it cannot matter.
        for (var k = 0; k < m; k++) {
          if (!_tracked(k, alive)) continue;
          final off = _offset(k);
          for (var i = 0; i <= k; i++) {
            final slot = off + i;
            final shift = _fieldShift[_posField(slot)];
            for (final o in options[i]) {
              final p = o < _end ? moved[slot * 5 + o] : _parked(pos[slot]);
              contrib[slot * 7 + o] = p << shift;
            }
          }
        }

        // Every combination of options, as an odometer.
        cursor.fillRange(0, m, 0);
        combos:
        while (true) {
          var cost = 0;
          var nextAlive = alive;
          var action = 0;
          for (var j = 0; j < m; j++) {
            final c = options[j][cursor[j]];
            choice[j] = c;
            action |= c << (3 * j);
            if (c < _end) cost++;
            if (c == _end) nextAlive &= ~(1 << j);
          }
          final h = s._dist[moved[finalSlot * 5 + choice[m - 1]]];
          if (tick + 1 + h <= Rules.maxTicksPerRun) {
            key.fillRange(0, words, 0);
            _packAlive(key, nextAlive);
            var ok = true;
            for (var k = 0; k < m && ok; k++) {
              if (!_tracked(k, nextAlive)) continue;
              final off = _offset(k);
              // A live earlier run reaching the exit would have won with
              // fewer runs: that is not an m-run play.
              if (k < m - 1 &&
                  choice[k] < _end &&
                  moved[(off + k) * 5 + choice[k]] == exit) {
                ok = false;
                break;
              }
              for (var i = 0; i <= k; i++) {
                final slot = off + i;
                key[_fieldWord[_posField(slot)]] |=
                    contrib[slot * 7 + choice[i]];
              }
            }
            if (ok) {
              final g = g0 + cost;
              final kid = _keyId(key, h);
              final t = tick + 1;
              if (_keyClosedTick[kid] > t) {
                var l = _keyFirstLabel[kid];
                while (l >= 0 && _labelTick[l] != t) {
                  l = _labelNext[l];
                }
                if (l < 0) {
                  buckets[g + h].add(_label(kid, t, g, label, action));
                } else if (g < _labelG[l]) {
                  _labelG[l] = g;
                  _labelParent[l] = label;
                  _labelAction[l] = action;
                  buckets[g + h].add(l);
                }
              }
            }
          }
          for (var j = 0; ; j++) {
            if (j == m) break combos;
            if (++cursor[j] < options[j].length) break;
            cursor[j] = 0;
          }
        }
      }
    }
    return null;
  }

  bool _live(int run, int alive) => run == m - 1 || alive & (1 << run) != 0;

  /// Whether world [k]'s actors are part of the state.
  bool _tracked(int k, int alive) =>
      k == m - 1 || (fewerRunsWin && alive & (1 << k) != 0);

  /// Where a ghost whose recording has ended is stored: its own tile if a
  /// plate or a door (it holds that open), else the start tile.
  int _parked(int cell) => s._matters[cell] ? cell : s._startIndex;

  /// True when an actor of world [k] (at [off]) stands on [cell]: a door
  /// with someone in it is open.
  bool _occupied(Int32List pos, int off, int k, int cell) {
    for (var i = 0; i <= k; i++) {
      if (pos[off + i] == cell) return true;
    }
    return false;
  }

  void _packAlive(Int64List key, int alive) {
    if (m > 1) key[_fieldWord[0]] |= alive << _fieldShift[0];
  }

  void _packPos(Int64List key, int slot, int cell) {
    final field = _posField(slot);
    key[_fieldWord[field]] |= cell << _fieldShift[field];
  }

  /// Writes key [kid]'s positions into [pos] and returns its live mask.
  int _decode(int kid, Int32List pos) {
    final base = kid * words;
    for (var slot = 0; slot < actors; slot++) {
      final field = _posField(slot);
      pos[slot] =
          (_keys[base + _fieldWord[field]] >> _fieldShift[field]) & _posMask;
    }
    if (m == 1) return 0;
    return (_keys[base + _fieldWord[0]] >> _fieldShift[0]) & _aliveMask;
  }

  /// Id of [key], adding it with heuristic [h] if new.
  int _keyId(Int64List key, int h) {
    var mask = _table.length - 1;
    var slot = _hash(key, 0) & mask;
    while (true) {
      final entry = _table[slot];
      if (entry == 0) break;
      final id = entry - 1;
      var same = true;
      for (var w = 0; w < words && same; w++) {
        same = _keys[id * words + w] == key[w];
      }
      if (same) return id;
      slot = (slot + 1) & mask;
    }
    final id = _keyCount++;
    if (_keyCount > _keyH.length) {
      final n = _keyH.length * 2;
      _keys = _grown64(_keys, n * words);
      _keyH = _grown32(_keyH, n);
      _keyClosedTick = _grown32(_keyClosedTick, n);
      _keyFirstLabel = _grown32(_keyFirstLabel, n);
    }
    _keys.setRange(id * words, id * words + words, key);
    _keyH[id] = h;
    _keyClosedTick[id] = Rules.maxTicksPerRun + 1;
    _keyFirstLabel[id] = -1;
    _table[slot] = id + 1;
    if (_keyCount * 2 > _table.length) {
      _table = Int32List(_table.length * 2);
      mask = _table.length - 1;
      for (var other = 0; other < _keyCount; other++) {
        var at = _hash(_keys, other * words) & mask;
        while (_table[at] != 0) {
          at = (at + 1) & mask;
        }
        _table[at] = other + 1;
      }
    }
    return id;
  }

  int _hash(Int64List data, int from) {
    var hash = 0;
    for (var w = 0; w < words; w++) {
      hash = (hash ^ data[from + w]) * 0x5bd1e9955bd1e995;
      hash ^= hash >>> 29;
    }
    return hash;
  }

  /// A new label of key [kid] at [tick] with cost [g].
  int _label(int kid, int tick, int g, int parent, int action) {
    final id = _labelCount++;
    if (_labelCount > _labelKey.length) {
      final n = _labelKey.length * 2;
      _labelKey = _grown32(_labelKey, n);
      _labelTick = _grown32(_labelTick, n);
      _labelG = _grown32(_labelG, n);
      _labelParent = _grown32(_labelParent, n);
      _labelAction = _grown32(_labelAction, n);
      _labelNext = _grown32(_labelNext, n);
      _labelClosed = Uint8List(n)
        ..setRange(0, _labelClosed.length, _labelClosed);
    }
    _labelKey[id] = kid;
    _labelTick[id] = tick;
    _labelG[id] = g;
    _labelParent[id] = parent;
    _labelAction[id] = action;
    _labelClosed[id] = 0;
    _labelNext[id] = _keyFirstLabel[kid];
    _keyFirstLabel[kid] = id;
    return id;
  }

  static Int64List _grown64(Int64List a, int n) =>
      Int64List(n)..setRange(0, a.length, a);
  static Int32List _grown32(Int32List a, int n) =>
      Int32List(n)..setRange(0, a.length, a);

  /// Each run's moves up to its end (or the winning tick for the final run).
  Solved _rebuild(int goal) {
    final actions = <int>[];
    for (var l = goal; _labelParent[l] >= 0; l = _labelParent[l]) {
      actions.add(_labelAction[l]);
    }
    final runs = List.generate(m, (_) => <Move>[]);
    final ended = List.filled(m, false);
    for (final action in actions.reversed) {
      for (var j = 0; j < m; j++) {
        final c = (action >> (3 * j)) & 7;
        if (c >= _end) ended[j] = true;
        if (!ended[j]) runs[j].add(_jointMoves[c]);
      }
    }
    return Solved(_labelG[goal], runs);
  }
}

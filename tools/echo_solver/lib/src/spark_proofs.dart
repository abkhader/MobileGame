part of 'solver.dart';

/// What [sparkProof] proved about one spark.
class SparkProof {
  const SparkProof({
    required this.collectible,
    required this.echoNeeded,
    this.nodes = 0,
  }) : budgetExceeded = false;

  const SparkProof.budgetExceeded(this.nodes)
    : collectible = false,
      echoNeeded = false,
      budgetExceeded = true;

  /// Some winning play within `runLimit` runs collects the spark.
  final bool collectible;

  /// [collectible], but no winning play collects it during run 1 (run index
  /// 0): only an echo makes it reachable.
  final bool echoNeeded;

  /// The search went over its node budget; nothing was proved.
  final bool budgetExceeded;

  /// Joint states expanded, including the win checks per run count.
  final int nodes;
}

/// Default node budget of one [sparkProof] (a few seconds): a slow proof
/// fails fast instead of stalling the level check.
const sparkProofMaxNodes = 3000000;

/// Proves whether [spark] (one of [level]'s sparks) can be collected in a
/// winning play, and whether that needs an echo. [maxNodes] caps the joint
/// states expanded over every search this makes.
///
/// It uses the joint worlds of [solve] (see [_JointRuns]), searched for a
/// play in which the final world wins and one given run's player steps onto
/// [spark] in its own world while that run is live ([_SparkRuns]). Run
/// counts with no winning play at all are skipped. "Echo needed" is
/// "collectible, and no winning play collects it in run index 0": no play
/// has run 0 collect, and some play has a later run `j` collect (an OR over
/// `j`, the final run first).
SparkProof sparkProof(
  Level level,
  Position spark, {
  int maxNodes = sparkProofMaxNodes,
}) {
  if (!level.sparks.contains(spark)) {
    throw ArgumentError.value(spark, 'spark', 'is not a spark of the level');
  }
  final s = _JointSearch(level, maxNodes);
  try {
    if (s._dist[s._startIndex] > Rules.maxTicksPerRun) {
      return const SparkProof(collectible: false, echoNeeded: false);
    }
    // winners[m - 1]: some m-run play wins (sparks aside).
    final winners = <bool>[];
    for (var m = 1; m <= level.runLimit; m++) {
      final fewer = winners.contains(true);
      winners.add(_JointRuns(s, m, fewerRunsWin: fewer).cheapest(null) != null);
    }
    final cell = s._index(spark);
    // Whether some m-run play wins with run j collecting.
    bool collects(int m, int j) {
      if (!winners[m - 1]) return false;
      final fewer = winners.sublist(0, m - 1).contains(true);
      return _SparkRuns(s, m, fewer, j, cell).reachable();
    }

    // Run 0's world holds run 0 alone, whatever the run count: if its
    // player cannot even reach the spark there, no play has run 0 collect.
    final solo = _soloReaches(s, cell);
    for (var m = 1; m <= level.runLimit && solo; m++) {
      if (collects(m, 0)) {
        return SparkProof(collectible: true, echoNeeded: false, nodes: s.nodes);
      }
    }
    for (var m = 2; m <= level.runLimit; m++) {
      for (var j = m - 1; j >= 1; j--) {
        if (collects(m, j)) {
          return SparkProof(
            collectible: true,
            echoNeeded: true,
            nodes: s.nodes,
          );
        }
      }
    }
    return SparkProof(collectible: false, echoNeeded: false, nodes: s.nodes);
  } on _BudgetAbort {
    return SparkProof.budgetExceeded(s.nodes);
  }
}

/// Whether one actor alone can step onto [cell] within one run without
/// reaching the exit first (it would win there). Alone, it opens a door only
/// by standing on that door's plate the tick before.
bool _soloReaches(_JointSearch s, int cell) {
  final exit = s._index(s.level.exit);
  final seen = List.filled(s.cells, false);
  var frontier = [s._startIndex];
  seen[s._startIndex] = true;
  for (var tick = 0; tick < Rules.maxTicksPerRun; tick++) {
    final next = <int>[];
    for (final c in frontier) {
      final plate = s._plateChannel[c];
      for (var d = 0; d < 4; d++) {
        final to = s._target[c * 4 + d];
        if (to < 0 || seen[to]) continue;
        final door = s._doorChannel[to];
        if (door >= 0 && door != plate) continue;
        if (to == cell) return true;
        seen[to] = true;
        if (to != exit) next.add(to);
      }
    }
    frontier = next;
  }
  return false;
}

/// Search over the joint states of every `m`-run play for a winning play in
/// which run [collector]'s player collects the target spark: it steps onto
/// [spark] in its own world while its run is live.
///
/// The state (*key*) is [_JointRuns]'s (live-run mask and actor positions)
/// plus a *got* flag. The goal is the final player reaching the exit with
/// got set (a collection on that same tick counts). The search stops at the
/// final world's win, although in the game an earlier run is played in full
/// before the final run and so may collect at a later tick than the final
/// run's winning one. No such play is lost: the final player can instead
/// wait on its tile next to the exit until that tick and step on then.
/// Waiting there is always possible (no actor moves it, an occupied door
/// stays open), entering the exit needs nothing (it is never a door), and
/// the final run acts only in its own world. The independent reference in
/// the tests does keep the earlier worlds going after the win.
///
/// A *label* is a key reached at a tick. A label is cut when its tick plus
/// [_hTick] passes [Rules.maxTicksPerRun]: the larger of the final player's
/// distance to the exit and, until got, the collector's distance to the
/// spark (plus the spark's to the exit when the collector is the final
/// run), all with doors as floor. Labels are expanded in order of score
/// (one per live run per tick, as in [_JointRuns]) plus [_orderWeight]
/// times [_hScore], which finds plays far sooner than tick order when runs
/// must wait for each other. The order does not affect exactness: every
/// label that is not dominated (below) is expanded unless a play is found
/// first, and a label due in a bucket already passed joins the current one.
///
/// Reductions of [_JointRuns], rechecked for this goal:
/// - Ghost parking stays exact. Ghosts never collect, and a run's ended
///   world is frozen (what it did for got is already in the flag), so an
///   ended ghost still matters only on a plate or a door.
/// - "Track only the final world when no fewer-run play wins" is not exact
///   here: the collector's world matters. Instead the final world is always
///   tracked, and world `k < m - 1` while its run is live and either
///   - `k` is the collector and got is not set (its player may collect; it
///     must not reach the exit first), or
///   - some fewer-run play wins and `k` is below the collector.
///   An untracked world affects no other world. What it can still matter
///   for is an earlier world's player reaching the exit, which makes the
///   real play the shorter one ending there. Let `k*` be the first world
///   whose player does that. If `k*` is untracked, either no fewer-run play
///   wins (so no earlier player can reach the exit at all), or the collector
///   is at most `k*` and collected before any exit of its own (checked until
///   got). Then the collector belongs to the shorter play (`k*` + 1 runs; a
///   run before the last one is played in full, and the last one may wait
///   next to the exit as above), which is a winning play in which it
///   collects: the answer, an OR over run counts, is unchanged. A tracked
///   earlier world reaching the exit just ends the branch; the shorter play
///   is searched on its own. So the run-0 search never tracks worlds 1 to
///   m - 2, and drops world 0 once it has collected.
/// - Dropping the tick from the key by dominance stays exact: got is in the
///   key, moves do not depend on the tick, and the only tick rule is the
///   cut, which is monotone in the tick. So a label is dominated by an
///   expanded label of the same key with no later tick, and is skipped.
///   (Cost plays no part in the goal, so unlike [_JointRuns] a cheaper
///   label does not dominate.)
/// - The useless-run prune of [solveSequential] is not used: a run that
///   touches no plate or door may still collect the spark, then end (the
///   joint search never used it). Every live non-final run may end at every
///   tick.
/// - Kept: a move into a wall for every tracked copy equals waiting.
/// Weight of [_SparkRuns._hScore] in the queue order: a greedier order
/// finds plays several times sooner on the 4-run levels (2 measured best).
const _orderWeight = 2;

class _SparkRuns {
  _SparkRuns(this.s, this.m, this.fewerRunsWin, this.collector, this.spark)
    : actors = m * (m + 1) ~/ 2 {
    final posBits = (s.cells - 1).bitLength.clamp(1, 62);
    final widths = [m, for (var i = 0; i < actors; i++) posBits];
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
    _statusMask = (1 << m) - 1;
    words = word + 1;
    _keys = Int64List(words << 10);

    _sparkDist = Int32List(s.cells)..fillRange(0, s.cells, _unreachable);
    final queue = Queue<int>()..add(spark);
    _sparkDist[spark] = 0;
    while (queue.isNotEmpty) {
      final c = queue.removeFirst();
      for (var d = 0; d < 4; d++) {
        final t = s._target[c * 4 + d];
        if (t >= 0 && _sparkDist[t] == _unreachable) {
          _sparkDist[t] = _sparkDist[c] + 1;
          queue.add(t);
        }
      }
    }
    _sparkToExit = s._dist[spark];
  }

  final _JointSearch s;
  final int m;
  final bool fewerRunsWin;

  /// The run index whose player's collection counts.
  final int collector;
  final int spark;
  final int actors;
  late final int words;

  final _fieldWord = <int>[];
  final _fieldShift = <int>[];
  late final int _posMask;
  late final int _statusMask;

  /// BFS distance to [spark] with doors as floor.
  late final Int32List _sparkDist;
  late final int _sparkToExit;

  // Per key, indexed by key id.
  late Int64List _keys;
  var _keyHTick = Int32List(1 << 10);
  var _keyHScore = Int32List(1 << 10);
  var _keyClosedTick = Int32List(1 << 10);
  var _keyFirstLabel = Int32List(1 << 10);
  var _keyCount = 0;

  /// Open-addressing hash table of key id + 1 (0 = empty).
  var _table = Int32List(1 << 11);

  // Per label, indexed by label id.
  var _labelKey = Int32List(1 << 10);
  var _labelTick = Int32List(1 << 10);
  var _labelG = Int32List(1 << 10);
  var _labelNext = Int32List(1 << 10);
  var _labelClosed = Uint8List(1 << 10);
  var _labelCount = 0;

  /// Status bits: the live mask of runs `0..m-2`, then got.
  int get _gotBit => 1 << (m - 1);

  int _offset(int world) => world * (world + 1) ~/ 2;

  bool _live(int run, int status) => run == m - 1 || status & (1 << run) != 0;

  bool _tracked(int k, int status) {
    if (k == m - 1) return true;
    if (status & (1 << k) == 0) return false;
    if (k == collector && status & _gotBit == 0) return true;
    return fewerRunsWin && k < collector;
  }

  /// Fewest ticks still needed with [status], the final player on [last]
  /// and the collector's player on [mine] (ignored once got).
  int _hTick(int status, int last, int mine) {
    final exit = s._dist[last];
    if (status & _gotBit != 0) return exit;
    final toSpark = collector == m - 1
        ? _sparkDist[last] + _sparkToExit
        : _sparkDist[mine];
    return toSpark > exit ? toSpark : exit;
  }

  /// Fewest score points still needed, as for [_hTick]: the final run's
  /// moves, plus the collector's until got when it is another run.
  int _hScore(int status, int last, int mine) {
    if (status & _gotBit != 0) return s._dist[last];
    if (collector == m - 1) return _hTick(status, last, mine);
    return s._dist[last] + _sparkDist[mine];
  }

  bool reachable() {
    const cap = Rules.maxTicksPerRun;
    final start = s._startIndex;
    final exit = s._index(s.level.exit);
    final buckets = List.generate(
      cap * (m + 2 * _orderWeight) + 1,
      (_) => <int>[],
    );
    final key = Int64List(words);
    final pos = Int32List(actors);
    final initial = (1 << (m - 1)) - 1;
    _packStatus(key, initial);
    for (var k = 0; k < m; k++) {
      if (!_tracked(k, initial)) continue;
      for (var i = 0; i <= k; i++) {
        final f = 1 + _offset(k) + i;
        key[_fieldWord[f]] |= start << _fieldShift[f];
      }
    }
    if (_hTick(initial, start, start) > cap) return false;
    final firstKey = _keyId(
      key,
      _hTick(initial, start, start),
      _hScore(initial, start, start),
    );
    buckets[_keyHScore[firstKey]].add(_label(firstKey, 0, 0));

    final moved = Int32List(actors * 5);
    final options = List.generate(m, (_) => <int>[]);
    final contrib = Int64List(actors * 7);
    final choice = Int32List(m);
    final cursor = Int32List(m);
    final tracked = List.filled(m, false);
    final finalSlot = _offset(m - 1) + m - 1;
    final mineSlot = _offset(collector) + collector;

    for (var f = 0; f < buckets.length; f++) {
      final bucket = buckets[f];
      for (var b = 0; b < bucket.length; b++) {
        final label = bucket[b];
        if (_labelClosed[label] != 0) continue;
        final kid = _labelKey[label];
        final g = _labelG[label];
        if (g + _keyHScore[kid] > f) continue;
        _labelClosed[label] = 1;
        final tick = _labelTick[label];
        if (_keyClosedTick[kid] <= tick) continue;
        _keyClosedTick[kid] = tick;
        if (++s.nodes > s.maxNodes) throw const _BudgetAbort();
        final status = _decode(kid, pos);
        for (var k = 0; k < m; k++) {
          tracked[k] = _tracked(k, status);
        }

        // Every tracked actor's result for every move.
        for (var k = 0; k < m; k++) {
          if (!tracked[k]) continue;
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

        // Each run's options. Every live run has the final world tracked.
        for (var j = 0; j < m; j++) {
          final o = options[j]..clear();
          if (!_live(j, status)) {
            o.add(_gone);
            continue;
          }
          for (var d = 0; d < 4; d++) {
            var useful = false;
            for (var k = j; k < m && !useful; k++) {
              if (tracked[k]) {
                useful = s._target[pos[_offset(k) + j] * 4 + d] >= 0;
              }
            }
            if (useful) o.add(d);
          }
          o.add(_wait);
          if (j < m - 1) o.add(_end);
        }

        for (var k = 0; k < m; k++) {
          if (!tracked[k]) continue;
          final off = _offset(k);
          for (var i = 0; i <= k; i++) {
            final slot = off + i;
            final shift = _fieldShift[1 + slot];
            for (final o in options[i]) {
              final p = o < _end ? moved[slot * 5 + o] : _parked(pos[slot]);
              contrib[slot * 7 + o] = p << shift;
            }
          }
        }

        final t = tick + 1;
        cursor.fillRange(0, m, 0);
        combos:
        while (true) {
          var next = status;
          var cost = 0;
          for (var j = 0; j < m; j++) {
            final c = options[j][cursor[j]];
            choice[j] = c;
            if (c == _end) next &= ~(1 << j);
            if (c < _end) cost++;
          }
          var ok = true;
          var won = false;
          for (var k = 0; k < m && ok; k++) {
            if (!tracked[k] || choice[k] >= _end) continue;
            final p = moved[(_offset(k) + k) * 5 + choice[k]];
            if (p == exit) {
              // An earlier world's win is a win with fewer runs: not an
              // m-run play.
              ok = k == m - 1;
              won = ok;
            }
            if (p == spark && k == collector) next |= _gotBit;
          }
          if (won && next & _gotBit != 0) return true;
          // A win without the spark ends the play, and so does the
          // collector's run ending without it: dead ends.
          final got = next & _gotBit != 0;
          if (ok && !won && (got || _live(collector, next))) {
            final last = moved[finalSlot * 5 + choice[m - 1]];
            final mine = got ? 0 : moved[mineSlot * 5 + choice[collector]];
            final hTick = _hTick(next, last, mine);
            if (t + hTick <= cap) {
              key.fillRange(0, words, 0);
              _packStatus(key, next);
              for (var k = 0; k < m; k++) {
                if (!_tracked(k, next)) continue;
                final off = _offset(k);
                for (var i = 0; i <= k; i++) {
                  final slot = off + i;
                  key[_fieldWord[1 + slot]] |= contrib[slot * 7 + choice[i]];
                }
              }
              final id = _keyId(key, hTick, _hScore(next, last, mine));
              if (_keyClosedTick[id] > t) {
                final g1 = g + cost;
                var l = _keyFirstLabel[id];
                while (l >= 0 && _labelTick[l] != t) {
                  l = _labelNext[l];
                }
                // The order is only a guide (see the class comment), so a
                // label due in an earlier bucket just joins this one.
                final due = g1 + _keyHScore[id];
                final at = due < f ? f : due;
                if (l < 0) {
                  buckets[at].add(_label(id, t, g1));
                } else if (g1 < _labelG[l]) {
                  _labelG[l] = g1;
                  buckets[at].add(l);
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
    return false;
  }

  int _parked(int cell) => s._matters[cell] ? cell : s._startIndex;

  bool _occupied(Int32List pos, int off, int k, int cell) {
    for (var i = 0; i <= k; i++) {
      if (pos[off + i] == cell) return true;
    }
    return false;
  }

  void _packStatus(Int64List key, int status) {
    key[_fieldWord[0]] |= status << _fieldShift[0];
  }

  /// Writes key [kid]'s positions into [pos] and returns its status.
  int _decode(int kid, Int32List pos) {
    final base = kid * words;
    for (var slot = 0; slot < actors; slot++) {
      final f = 1 + slot;
      pos[slot] = (_keys[base + _fieldWord[f]] >> _fieldShift[f]) & _posMask;
    }
    return (_keys[base + _fieldWord[0]] >> _fieldShift[0]) & _statusMask;
  }

  /// Id of [key], adding it with its two h values if new.
  int _keyId(Int64List key, int hTick, int hScore) {
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
    if (_keyCount > _keyHTick.length) {
      final n = _keyHTick.length * 2;
      _keys = _JointRuns._grown64(_keys, n * words);
      _keyHTick = _JointRuns._grown32(_keyHTick, n);
      _keyHScore = _JointRuns._grown32(_keyHScore, n);
      _keyClosedTick = _JointRuns._grown32(_keyClosedTick, n);
      _keyFirstLabel = _JointRuns._grown32(_keyFirstLabel, n);
    }
    _keys.setRange(id * words, id * words + words, key);
    _keyHTick[id] = hTick;
    _keyHScore[id] = hScore * _orderWeight;
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

  /// A new label of key [kid] at [tick] with score [g].
  int _label(int kid, int tick, int g) {
    final id = _labelCount++;
    if (_labelCount > _labelKey.length) {
      final n = _labelKey.length * 2;
      _labelKey = _JointRuns._grown32(_labelKey, n);
      _labelTick = _JointRuns._grown32(_labelTick, n);
      _labelG = _JointRuns._grown32(_labelG, n);
      _labelNext = _JointRuns._grown32(_labelNext, n);
      _labelClosed = Uint8List(n)
        ..setRange(0, _labelClosed.length, _labelClosed);
    }
    _labelKey[id] = kid;
    _labelTick[id] = tick;
    _labelG[id] = g;
    _labelClosed[id] = 0;
    _labelNext[id] = _keyFirstLabel[kid];
    _keyFirstLabel[kid] = id;
    return id;
  }
}

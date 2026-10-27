part of 'solver.dart';

/// The dead-ghost marker in a world's actor slots (one past the last cell).
/// A dead echo affects nothing for the rest of its run, so where it fell is
/// forgotten.
int _deadCell(int cells) => cells;

/// Per-level tables of the every-world search ([_TrackedRuns]), built once
/// and shared by every run count.
class _DangerTables {
  _DangerTables(_JointSearch s) : level = s.level, cells = s.cells {
    laserBeat = Int8List(cells);
    crackBit = Int32List(cells)..fillRange(0, cells, -1);
    doorBit = Int32List(cells)..fillRange(0, cells, -1);
    var cracks = 0;
    for (var c = 0; c < cells; c++) {
      final p = s._pos(c);
      laserBeat[c] = level.lasers[p] ?? 0;
      if (level.cracked.contains(p)) crackBit[c] = cracks++;
      if (level.tileAt(p).kind == TileKind.door) {
        doorBit[c] = doorCells.length;
        doorCells.add(p);
      }
    }
    this.cracks = cracks;
    if (cracks > 62) {
      throw UnsupportedError('more than 62 cracked tiles');
    }
    shadeStarts = Int32List.fromList([
      for (final p in level.shadeStarts) s._index(p),
    ]);
    hasLasers = level.lasers.isNotEmpty;
    // A live ghost that only waits matters on a plate, a door, a crack it
    // keeps up or a laser that can hit it; with Shades, anywhere (it is a
    // light, and can be caught).
    matters = [
      for (var c = 0; c < cells; c++)
        level.shadeStarts.isNotEmpty ||
            s._matters[c] ||
            laserBeat[c] != 0 ||
            crackBit[c] >= 0,
    ];
    shadeDirs = Int32List.fromList([
      for (final d in Rules.shadeDirections) _jointMoves.indexOf(d),
    ]);
  }

  final Level level;
  final int cells;

  /// Laser beat (1-3) per cell, 0 for none.
  late final Int8List laserBeat;

  /// Bit of each cracked cell in a world's hole mask, -1 for other cells.
  late final Int32List crackBit;
  late final int cracks;

  /// Bit of each door cell in an open-door mask, -1 for other cells.
  late final Int32List doorBit;
  final doorCells = <Position>[];

  late final Int32List shadeStarts;
  late final bool hasLasers;

  /// Where a ghost whose run has ended may still matter (see the class
  /// comment of [_TrackedRuns]).
  late final List<bool> matters;

  /// [Rules.shadeDirections] as indices into [_jointMoves].
  late final Int32List shadeDirs;

  /// [Rules.shadeDistances] per open-door mask and target cell.
  final _fields = <int, Int32List>{};

  /// [Rules.shadeDistances] to [target] with the doors of [doorMask] open.
  Int32List field(int doorMask, int target) {
    final key = doorMask * cells + target;
    final cached = _fields[key];
    if (cached != null) return cached;
    final open = {
      for (var b = 0; b < doorCells.length; b++)
        if (doorMask & (1 << b) != 0) doorCells[b],
    };
    final f = Int32List.fromList(
      Rules.shadeDistances(
        level,
        open,
        Position(target % level.width, target ~/ level.width),
      ),
    );
    _fields[key] = f;
    return f;
  }
}

/// Search over the joint states of every `m`-run play in which every world
/// of a live run is tracked: the exact search for levels with dangers
/// (lasers, cracked floor, Shades), and valid on any level.
///
/// As in [_JointRuns], world `k` holds runs `0..k` (run `k` being its
/// player) and each run's action at a tick is applied to its player in its
/// own world and to its ghost in every later world. With dangers a world
/// also holds its holes and its Shades, and a ghost may be dead (hit). Each
/// beat follows [Rules.step] exactly, world by world: moves against the
/// previous beat's doors, [Rules.collapse], [Rules.shadeStep] for each Shade
/// (mirrored with cached [Rules.shadeDistances] fields), hits as
/// [Rules.isHit] (lasers by [Rules.laserFires]), then
/// [Rules.collapseUnderDissolved]. A hit player ends its run at that tick
/// (forced rewind: the fatal move is the run's last and is paid for); for
/// the final run it is a loss, so that branch ends. A hit player on the exit
/// does not win.
///
/// The key packs the live-run mask, `tick % 3` when the level has lasers,
/// and per tracked world its actors (a dead ghost as [_deadCell]), its hole
/// mask and its Shades. Reductions, each exact with dangers:
/// - Every world of a live run is tracked. ([_JointRuns] may track only the
///   final world; with dangers it cannot, since whether run `k` is cut short
///   by a hit is decided in world `k`.) A world whose run has ended is
///   frozen and irrelevant: its slots are 0.
/// - A ghost whose run has ended waits forever. If it stands on no plate,
///   door, crack or laser and the level has no Shades, nothing can happen to
///   it and it affects nothing, so it is stored on the start tile (which is
///   none of those). Otherwise it stays where it is.
/// - A dead ghost's tile is forgotten: it moves, presses, holds, keeps up
///   and lights nothing, and cannot be hit again.
/// - A direction into a wall or the grid edge for every live tracked copy of
///   a run is skipped: in [Rules.step] that bump leaves every position, hole,
///   Shade and hit exactly as a wait does, and walls never change.
/// - Transitions depend on the tick only through `tick % 3` (lasers; it is
///   in the key) and the cap, which is monotone in the tick. So a label is
///   dominated by a label of the same key with no later tick and no higher
///   cost, as in [_JointRuns], whose A* order and h (final player's distance
///   to the exit, doors as floor; holes, lasers and Shades only hit) carry
///   over unchanged.
///
/// [avoid] (a cell, or -1) forbids every transition that puts an actor of
/// any tracked world on it: the search then finds the cheapest winning play
/// in which no actor ever enters [avoid] (see [solveTracked]).
///
/// The spark search ([collects]) uses the same worlds; see there.
class _TrackedRuns {
  _TrackedRuns(
    this.s,
    this.t,
    this.m, {
    this.avoid = -1,
    this.collector = -1,
    this.spark = -1,
  }) : actors = m * (m + 1) ~/ 2,
       ns = t.shadeStarts.length,
       dead = _deadCell(s.cells) {
    final posBits = s.cells.bitLength;
    final widths = <int>[];
    int field(int width) {
      widths.add(width);
      return widths.length - 1;
    }

    _statusField = field(m + 1);
    _phaseField = t.hasLasers ? field(2) : -1;
    _posField = Int32List(actors);
    _holesField = Int32List(m)..fillRange(0, m, -1);
    _shadeField = Int32List(m * ns);
    for (var k = 0; k < m; k++) {
      for (var i = 0; i <= k; i++) {
        _posField[_offset(k) + i] = field(posBits);
      }
      if (t.cracks > 0) _holesField[k] = field(t.cracks);
      for (var q = 0; q < ns; q++) {
        _shadeField[k * ns + q] = field(posBits);
      }
    }
    var word = 0;
    var used = 0;
    for (final w in widths) {
      if (used + w > 62) {
        word++;
        used = 0;
      }
      _fieldWord.add(word);
      _fieldShift.add(used);
      _fieldMask.add((1 << w) - 1);
      used += w;
    }
    words = word + 1;
    _keys = Int64List(words << 10);
    _key = Int64List(words);

    _pos = Int32List(actors);
    _npos = Int32List(actors);
    _holes = Int64List(m);
    _nholes = Int64List(m);
    _shades = Int32List(m * ns);
    _nshades = Int32List(m * ns);
    _doorMask = Int32List(m);
    _moved = Int32List(actors * 5);
    _options = List.generate(m, (_) => <int>[]);
    _choice = Int32List(m);
    _stop = Int32List(m);
    _lights = Int32List(m);

    if (spark >= 0) {
      _sparkDist = Int32List(s.cells)..fillRange(0, s.cells, _unreachable);
      final queue = Queue<int>()..add(spark);
      _sparkDist[spark] = 0;
      while (queue.isNotEmpty) {
        final c = queue.removeFirst();
        for (var d = 0; d < 4; d++) {
          final to = s._target[c * 4 + d];
          if (to >= 0 && _sparkDist[to] == _unreachable) {
            _sparkDist[to] = _sparkDist[c] + 1;
            queue.add(to);
          }
        }
      }
    }
  }

  final _JointSearch s;
  final _DangerTables t;
  final int m;
  final int actors;

  /// Number of Shades.
  final int ns;
  final int dead;
  final int avoid;

  /// Spark search only: the run whose player's collection counts, and the
  /// spark cell.
  final int collector;
  final int spark;
  late final Int32List _sparkDist;

  late final int words;
  final _fieldWord = <int>[];
  final _fieldShift = <int>[];
  final _fieldMask = <int>[];
  late final int _statusField;
  late final int _phaseField;
  late final Int32List _posField;
  late final Int32List _holesField;
  late final Int32List _shadeField;

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

  // Expansion scratch: the state being expanded (pos, holes, shades per
  // world, status) and the successor being built (npos, nholes, nshades).
  late final Int64List _key;
  late final Int32List _pos;
  late final Int32List _npos;
  late final Int64List _holes;
  late final Int64List _nholes;
  late final Int32List _shades;
  late final Int32List _nshades;
  late final Int32List _doorMask;
  late final Int32List _moved;
  late final List<List<int>> _options;
  late final Int32List _choice;

  /// Per world after [_eval]: 0 running, 1 ended by choice, 2 forced end.
  late final Int32List _stop;
  late final Int32List _lights;
  int _status = 0;
  int _tick = 0;
  bool _finalWon = false;
  bool _gotNow = false;

  // What the successor callback does: the A* insertion or the spark BFS.
  int _label = -1;
  int _g = 0;
  int? _bound;
  List<List<int>>? _buckets;
  List<int>? _frontier;
  bool _found = false;

  int get _gotBit => 1 << (m - 1);
  int get _wonBit => 1 << m;

  int _offset(int world) => world * (world + 1) ~/ 2;

  bool _live(int run, int status) =>
      run == m - 1 ? status & _wonBit == 0 : status & (1 << run) != 0;

  /// The worlds of live runs; after the final win (spark search) only those
  /// up to the collector are live.
  bool _tracked(int k, int status) => _live(k, status);

  int _get(Int64List key, int base, int field) =>
      (key[base + _fieldWord[field]] >> _fieldShift[field]) & _fieldMask[field];

  void _put(Int64List key, int field, int value) {
    key[_fieldWord[field]] |= value << _fieldShift[field];
  }

  /// The initial key: every world at its start.
  Int64List _initialKey() {
    final key = Int64List(words);
    _put(key, _statusField, (1 << (m - 1)) - 1);
    final start = s._startIndex;
    for (var k = 0; k < m; k++) {
      for (var i = 0; i <= k; i++) {
        _put(key, _posField[_offset(k) + i], start);
      }
      for (var q = 0; q < ns; q++) {
        _put(key, _shadeField[k * ns + q], t.shadeStarts[q]);
      }
    }
    return key;
  }

  /// Cheapest `m`-run play costing less than [bound] (any cost when null),
  /// or null if there is none.
  Solved? cheapest(int? bound) {
    final start = s._startIndex;
    final buckets = List.generate(Rules.maxTicksPerRun * m + 2, (_) => <int>[]);
    final firstKey = _keyId(_initialKey(), s._dist[start]);
    buckets[_keyH[firstKey]].add(_newLabel(firstKey, 0, 0, -1, 0));
    _buckets = buckets;
    _bound = bound;
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
        _label = label;
        _g = g0;
        _expand(k0, tick);
      }
    }
    return null;
  }

  /// Spark search: whether some winning `m`-run play has run [collector]'s
  /// player collect [spark] (step onto it in its own world while its run is
  /// live; a hit on that beat still collects, as in [Rules.step]).
  ///
  /// The status adds *got* and *won* (the final world has won). Unlike
  /// [_SparkRuns], the search does not stop at the final world's win: in the
  /// game every earlier run is played in full first, and with dangers the
  /// final player cannot always wait next to the exit for it. After the win
  /// the final world is dropped and so are the runs after the collector: they
  /// cannot affect the collector's world, and if one of them would have
  /// reached the exit, the play with that run last is itself a winning play
  /// in which the collector collects, so the answer (an OR over run counts)
  /// is the same. An earlier world's player reaching the exit is a play with
  /// fewer runs, searched on its own. A win without the spark when the
  /// collector is the final run, or the collector's run ending without it,
  /// is a dead end.
  ///
  /// States are searched tick by tick, each key at the earliest tick it is
  /// reached (dominance as for [cheapest]; cost plays no part). A state is
  /// cut when its tick plus the ticks still needed passes the cap: the final
  /// player's distance to the exit (until won) and the collector's distance
  /// to the spark (until got; plus the spark's to the exit when the collector
  /// is the final run), doors as floor.
  bool collects() {
    final first = _keyId(_initialKey(), 0);
    _keyClosedTick[first] = 0;
    var frontier = [first];
    for (var tick = 0; tick < Rules.maxTicksPerRun; tick++) {
      final next = <int>[];
      _frontier = next;
      for (final kid in frontier) {
        if (++s.nodes > s.maxNodes) throw const _BudgetAbort();
        _expand(kid, tick);
        if (_found) return true;
      }
      frontier = next;
      if (frontier.isEmpty) break;
    }
    return false;
  }

  /// Ticks still needed by the spark search from [status] with the final
  /// player on [last] and the collector's on [mine].
  int _hTick(int status, int last, int mine) {
    final won = status & _wonBit != 0;
    final got = status & _gotBit != 0;
    final exit = won ? 0 : s._dist[last];
    if (got) return exit;
    final toSpark = collector == m - 1
        ? _sparkDist[last] + s._dist[spark]
        : _sparkDist[mine];
    return toSpark > exit ? toSpark : exit;
  }

  /// Expands key [kid] at [tick]: every combination of run options, each
  /// world stepped as [Rules.step] would, handed to [_emit].
  void _expand(int kid, int tick) {
    final base = kid * words;
    final status = _get(_keys, base, _statusField);
    _status = status;
    _tick = tick;
    for (var k = 0; k < m; k++) {
      if (!_tracked(k, status)) continue;
      final off = _offset(k);
      for (var i = 0; i <= k; i++) {
        _pos[off + i] = _get(_keys, base, _posField[off + i]);
      }
      _holes[k] = t.cracks > 0 ? _get(_keys, base, _holesField[k]) : 0;
      for (var q = 0; q < ns; q++) {
        _shades[k * ns + q] = _get(_keys, base, _shadeField[k * ns + q]);
      }
      // Doors from the end of the previous tick: a pressed plate's doors,
      // and any door with a live actor in it.
      var pressed = 0;
      var mask = 0;
      for (var i = 0; i <= k; i++) {
        final p = _pos[off + i];
        if (p == dead) continue;
        final ch = s._plateChannel[p];
        if (ch >= 0) pressed |= 1 << ch;
        final b = t.doorBit[p];
        if (b >= 0) mask |= 1 << b;
      }
      for (var b = 0; b < t.doorCells.length; b++) {
        final ch = s._doorChannel[s._index(t.doorCells[b])];
        if (pressed & (1 << ch) != 0) mask |= 1 << b;
      }
      _doorMask[k] = mask;
      for (var i = 0; i <= k; i++) {
        final from = _pos[off + i];
        if (from == dead) continue;
        for (var d = 0; d < 4; d++) {
          var to = s._target[from * 4 + d];
          if (to < 0) {
            to = from;
          } else {
            final b = t.doorBit[to];
            if (b >= 0 && mask & (1 << b) == 0) to = from;
          }
          _moved[(off + i) * 5 + d] = to;
        }
        _moved[(off + i) * 5 + _wait] = from;
      }
    }

    // Each run's options. A direction into a wall or the grid edge for
    // every live tracked copy of the run is the same as waiting.
    for (var j = 0; j < m; j++) {
      final o = _options[j]..clear();
      if (!_live(j, status)) {
        o.add(_gone);
        continue;
      }
      for (var d = 0; d < 4; d++) {
        var useful = false;
        for (var k = j; k < m && !useful; k++) {
          if (!_tracked(k, status)) continue;
          final p = _pos[_offset(k) + j];
          if (p != dead) useful = s._target[p * 4 + d] >= 0;
        }
        if (useful) o.add(d);
      }
      o.add(_wait);
      if (j < m - 1) o.add(_end);
    }
    _finalWon = false;
    _gotNow = false;
    _choose(0);
  }

  /// Picks run [j]'s option; world [j] depends only on runs `0..j`, so it is
  /// stepped as soon as its run has chosen.
  void _choose(int j) {
    if (j == m) {
      _emit();
      return;
    }
    final tracked = _tracked(j, _status);
    for (final o in _options[j]) {
      if (_found) return;
      _choice[j] = o;
      if (tracked) {
        final gotBefore = _gotNow;
        if (_eval(j)) _choose(j + 1);
        _gotNow = gotBefore;
      } else {
        _choose(j + 1);
      }
    }
  }

  /// Steps world [k] by the chosen options; false when the combination is
  /// no `m`-run play (the final player hit, an earlier player winning, or an
  /// actor entering [avoid]).
  bool _eval(int k) {
    final off = _offset(k);
    if (k == m - 1) _finalWon = false;
    if (_choice[k] == _end) {
      _stop[k] = 1;
      return true;
    }
    final tick = _tick + 1;
    // 1. Moves.
    for (var i = 0; i <= k; i++) {
      final from = _pos[off + i];
      if (from == dead) {
        _npos[off + i] = dead;
        continue;
      }
      final c = _choice[i];
      final to = c < _end ? _moved[(off + i) * 5 + c] : from;
      if (to == avoid) return false;
      _npos[off + i] = to;
    }
    // 2. Collapse: cracks a live actor stood on and no live actor stands on.
    var holes = _holes[k];
    if (t.cracks > 0) {
      for (var i = 0; i <= k; i++) {
        final from = _pos[off + i];
        if (from == dead) continue;
        final bit = t.crackBit[from];
        if (bit < 0 || holes & (1 << bit) != 0) continue;
        var kept = false;
        for (var j = 0; j <= k && !kept; j++) {
          kept = _pos[off + j] != dead && _npos[off + j] == from;
        }
        if (!kept) holes |= 1 << bit;
      }
    }
    // 3. Shades, toward the live actors: the player first, then the ghosts.
    if (ns > 0) {
      var n = 0;
      _lights[n++] = _npos[off + k];
      for (var i = 0; i < k; i++) {
        if (_pos[off + i] != dead) _lights[n++] = _npos[off + i];
      }
      for (var q = 0; q < ns; q++) {
        _nshades[k * ns + q] = _shadeStep(_doorMask[k], _shades[k * ns + q], n);
      }
    }
    // 4. Hits.
    var hit = 0;
    for (var i = 0; i <= k; i++) {
      final from = _pos[off + i];
      if (from == dead) continue;
      if (_isHit(k, holes, from, _npos[off + i], tick)) hit |= 1 << i;
    }
    final player = _npos[off + k];
    final playerHit = hit & (1 << k) != 0;
    if (playerHit && k == m - 1) return false; // lost
    // 4b. A crack under a dissolving echo breaks unless a live actor not
    // hit still stands on it.
    if (hit & ~(1 << k) != 0) {
      for (var i = 0; i < k; i++) {
        if (hit & (1 << i) == 0) continue;
        final cell = _npos[off + i];
        final bit = t.crackBit[cell];
        if (bit < 0 || holes & (1 << bit) != 0) continue;
        var standing = false;
        for (var j = 0; j <= k && !standing; j++) {
          standing =
              _pos[off + j] != dead &&
              hit & (1 << j) == 0 &&
              _npos[off + j] == cell;
        }
        if (!standing) holes |= 1 << bit;
      }
      for (var i = 0; i < k; i++) {
        if (hit & (1 << i) != 0) _npos[off + i] = dead;
      }
    }
    _nholes[k] = holes;
    if (k == collector && player == spark) _gotNow = true;
    if (playerHit) {
      _stop[k] = 2; // forced rewind
      return true;
    }
    if (player == s._index(s.level.exit)) {
      // An earlier world's win is a win with fewer runs.
      if (k < m - 1) return false;
      _finalWon = true;
    }
    _stop[k] = 0;
    return true;
  }

  /// [Rules.isHit] for an actor of world [k] that moved [from] → [to], with
  /// [holes] after the collapse and [tick] the new tick.
  bool _isHit(int k, int holes, int from, int to, int tick) {
    final beat = t.laserBeat[to];
    if (beat != 0 && Rules.laserFires(beat, tick)) return true;
    final bit = t.crackBit[to];
    if (bit >= 0 && holes & (1 << bit) != 0) return true;
    for (var q = 0; q < ns; q++) {
      final now = _nshades[k * ns + q];
      if (now == to) return true;
      if (_shades[k * ns + q] == to && now == from) return true;
    }
    return false;
  }

  /// [Rules.shadeStep] for a Shade on [shade] with the first [n] of
  /// [_lights] as lights and the doors of [doorMask] open.
  int _shadeStep(int doorMask, int shade, int n) {
    var best = -1;
    Int32List? field;
    for (var l = 0; l < n; l++) {
      final f = t.field(doorMask, _lights[l]);
      final d = f[shade];
      if (d >= 0 && (best < 0 || d < best)) {
        best = d;
        field = f;
      }
    }
    if (best <= 0) return shade;
    for (final d in t.shadeDirs) {
      final to = s._target[shade * 4 + d];
      if (to < 0) continue;
      final b = t.doorBit[to];
      if (b >= 0 && doorMask & (1 << b) == 0) continue;
      if (field![to] == best - 1) return to;
    }
    throw StateError('unreachable: a shortest path has a first step');
  }

  /// A ghost whose run has ended: stored where it is if it may still matter,
  /// else on the start tile.
  int _parked(int cell) =>
      cell == dead || t.matters[cell] ? cell : s._startIndex;

  /// One full combination: builds the successor and hands it on.
  void _emit() {
    final tick = _tick + 1;
    var status = _status;
    var cost = 0;
    var action = 0;
    for (var j = 0; j < m; j++) {
      final c = _choice[j];
      action |= c << (3 * j);
      if (c < _end) cost++;
      if (j < m - 1 && _live(j, _status)) {
        if (c == _end || _stop[j] == 2) status &= ~(1 << j);
      }
    }
    final sparkSearch = spark >= 0;
    if (sparkSearch) {
      if (_gotNow) status |= _gotBit;
      final got = status & _gotBit != 0;
      if (_finalWon) {
        if (!got && collector == m - 1) return;
        status |= _wonBit;
        for (var j = collector + 1; j < m - 1; j++) {
          status &= ~(1 << j);
        }
      }
      // The goal: the final world has won (now or earlier) and the spark
      // is collected (now or earlier).
      if (got && status & _wonBit != 0) {
        _found = true;
        return;
      }
      if (!got && !_live(collector, status)) return;
    }

    final key = _key..fillRange(0, words, 0);
    _put(key, _statusField, status);
    if (_phaseField >= 0) _put(key, _phaseField, tick % 3);
    for (var k = 0; k < m; k++) {
      if (!_tracked(k, status)) continue;
      final off = _offset(k);
      for (var i = 0; i <= k; i++) {
        final p = _npos[off + i];
        _put(
          key,
          _posField[off + i],
          i < k && !_live(i, status) ? _parked(p) : p,
        );
      }
      if (t.cracks > 0) _put(key, _holesField[k], _nholes[k]);
      for (var q = 0; q < ns; q++) {
        _put(key, _shadeField[k * ns + q], _nshades[k * ns + q]);
      }
    }

    if (sparkSearch) {
      // Each distance is only read while its world is live.
      final h = _hTick(
        status,
        _live(m - 1, status) ? _npos[_offset(m - 1) + m - 1] : 0,
        _live(collector, status) ? _npos[_offset(collector) + collector] : 0,
      );
      if (tick + h > Rules.maxTicksPerRun) return;
      final id = _keyId(key, 0);
      if (_keyClosedTick[id] <= tick) return;
      _keyClosedTick[id] = tick;
      _frontier!.add(id);
      return;
    }

    final h = s._dist[_npos[_offset(m - 1) + m - 1]];
    if (tick + h > Rules.maxTicksPerRun) return;
    final g = _g + cost;
    if (_bound != null && g + h >= _bound!) return;
    final kid = _keyId(key, h);
    if (_keyClosedTick[kid] <= tick) return;
    var l = _keyFirstLabel[kid];
    while (l >= 0 && _labelTick[l] != tick) {
      l = _labelNext[l];
    }
    if (l < 0) {
      _buckets![g + h].add(_newLabel(kid, tick, g, _label, action));
    } else if (g < _labelG[l]) {
      _labelG[l] = g;
      _labelParent[l] = _label;
      _labelAction[l] = action;
      _buckets![g + h].add(l);
    }
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
      _keys = _JointRuns._grown64(_keys, n * words);
      _keyH = _JointRuns._grown32(_keyH, n);
      _keyClosedTick = _JointRuns._grown32(_keyClosedTick, n);
      _keyFirstLabel = _JointRuns._grown32(_keyFirstLabel, n);
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
  int _newLabel(int kid, int tick, int g, int parent, int action) {
    final id = _labelCount++;
    if (_labelCount > _labelKey.length) {
      final n = _labelKey.length * 2;
      _labelKey = _JointRuns._grown32(_labelKey, n);
      _labelTick = _JointRuns._grown32(_labelTick, n);
      _labelG = _JointRuns._grown32(_labelG, n);
      _labelParent = _JointRuns._grown32(_labelParent, n);
      _labelAction = _JointRuns._grown32(_labelAction, n);
      _labelNext = _JointRuns._grown32(_labelNext, n);
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

  /// Each run's moves up to its end (or the winning tick for the final run).
  /// A run cut short by a hit ends with its fatal move.
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

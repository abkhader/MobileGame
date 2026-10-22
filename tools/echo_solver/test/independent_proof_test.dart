import 'dart:io';

import 'package:echo_core/echo_core.dart';
import 'package:test/test.dart';

/// An independent check of the "needs every run" proofs. It shares no code
/// with `solve` or `solveSequential`: it only reads the level geometry from
/// echo_core's [Level] and re-implements the movement rules itself.
///
/// With [m] runs the final world holds m actors: m - 1 ghosts and the player.
/// A ghost replays its recording, so "ghost i does X at tick t" is the same
/// as "run i chose X at tick t"; choosing END at tick t makes it wait from
/// then on. The search is therefore a plain reachability search over
/// (positions of all m actors, which ghost runs are still alive), keyed on
/// the earliest tick at which a state is seen. It answers exactly: can any
/// play using at most [m] runs bring the player to the exit within
/// [Rules.maxTicksPerRun] ticks? (A win in an earlier world is a play with
/// fewer runs, and a ghost that ended immediately just waits on the start.)
bool canReachExit(Level level, int m) {
  final w = level.width;
  final h = level.height;
  final cells = w * h;
  int idx(int x, int y) => y * w + x;
  Position at(int i) => Position(i % w, i ~/ w);

  // 0 floor, 1 wall, 2 door; plate -> list of door cells.
  final kind = List<int>.filled(cells, 0);
  final plateDoors = List<List<int>>.generate(cells, (_) => const []);
  for (var i = 0; i < cells; i++) {
    final tile = level.tileAt(at(i));
    switch (tile.kind) {
      case TileKind.wall:
        kind[i] = 1;
      case TileKind.door:
        kind[i] = 2;
      case TileKind.plate:
        plateDoors[i] = [
          for (final d in level.doors[tile.channel] ?? const <Position>[])
            idx(d.x, d.y),
        ];
      default:
        break;
    }
  }

  // moveTo[i][k]: where an actor on cell i ends up for U, D, L, R, W,
  // given the open-door mask. Computed per state from the door flags.
  const dx = [0, 0, -1, 1, 0];
  const dy = [-1, 1, 0, 0, 0];
  int target(int i, int k, List<bool> open) {
    final x = i % w + dx[k];
    final y = i ~/ w + dy[k];
    if (x < 0 || y < 0 || x >= w || y >= h) return i;
    final j = idx(x, y);
    if (kind[j] == 1) return i;
    if (kind[j] == 2 && !open[j]) return i;
    return j;
  }

  final start = idx(level.start.x, level.start.y);
  final exit = idx(level.exit.x, level.exit.y);
  final ghosts = m - 1;

  int pack(List<int> pos, int alive) {
    var key = alive;
    for (final p in pos) {
      key = key * 128 + p;
    }
    return key;
  }

  void openDoors(List<int> pos, List<bool> open) {
    open.fillRange(0, cells, false);
    for (final p in pos) {
      if (kind[p] == 2) open[p] = true;
      for (final d in plateDoors[p]) {
        open[d] = true;
      }
    }
  }

  final allAlive = (1 << ghosts) - 1;
  final first = List<int>.filled(m, start);
  final seen = <int>{pack(first, allAlive)};
  var frontier = <int>[pack(first, allAlive)];
  final open = List<bool>.filled(cells, false);
  final pos = List<int>.filled(m, 0);

  for (var tick = 0; tick < Rules.maxTicksPerRun; tick++) {
    final next = <int>[];
    for (final key in frontier) {
      var rest = key;
      for (var a = m - 1; a >= 0; a--) {
        pos[a] = rest % 128;
        rest ~/= 128;
      }
      final alive = rest;
      openDoors(pos, open);

      // Per actor: the reachable (cell, stillAlive) options this tick.
      final cellOptions = <List<int>>[];
      for (var a = 0; a < m; a++) {
        cellOptions.add([for (var k = 0; k < 5; k++) target(pos[a], k, open)]);
      }

      final cur = List<int>.filled(m, 0);
      void expand(int a, int aliveNext) {
        if (a == m) {
          final k = pack(cur, aliveNext);
          if (seen.add(k)) next.add(k);
          return;
        }
        final isPlayer = a == m - 1;
        final isAlive = isPlayer || (alive >> a) & 1 == 1;
        if (!isAlive) {
          cur[a] = pos[a];
          expand(a + 1, aliveNext);
          return;
        }
        for (final c in cellOptions[a].toSet()) {
          cur[a] = c;
          expand(a + 1, isPlayer ? aliveNext : aliveNext | (1 << a));
        }
        if (!isPlayer) {
          cur[a] = pos[a]; // END: waits from now on
          expand(a + 1, aliveNext);
        }
      }

      // Win check: does any player move reach the exit this tick?
      if (cellOptions[m - 1].contains(exit)) return true;
      expand(0, 0);
    }
    frontier = next;
    if (frontier.isEmpty) return false;
  }
  return false;
}

void main() {
  final files =
      Directory('../../app/assets/levels')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final levels = [
    for (final f in files) LevelLoader.parse(f.readAsStringSync()),
  ];

  test('the search itself finds exits that need every run', () {
    Level l(List<String> g, int runs) => LevelLoader.fromMap({
      'id': '1-03',
      'name': 't',
      'runLimit': runs,
      'grid': g,
    });
    // Plate a must be held while another actor passes door A.
    const hold = ['#######', '#Sa.AE#', '#######'];
    expect(canReachExit(l(hold, 2), 1), isFalse);
    expect(canReachExit(l(hold, 2), 2), isTrue);
    expect(canReachExit(l(['#######', '#S...E#', '#######'], 1), 1), isTrue);
    expect(canReachExit(l(['#S#E#'], 1), 1), isFalse);
  });

  // Controls that the search is not vacuously false. Levels with 4 runs are
  // left out: their m = 4 search is slow and the m = 3 proofs below are the
  // point of this file.
  group('runLimit runs can reach the exit (the search is not vacuous)', () {
    for (final level in levels.where((l) => l.runLimit <= 3)) {
      test(level.id, () {
        expect(canReachExit(level, level.runLimit), isTrue);
      });
    }
  });

  group('runLimit - 1 runs cannot reach the exit within 25 ticks', () {
    for (final level in levels.where((l) => l.runLimit > 1)) {
      test(level.id, () {
        expect(canReachExit(level, level.runLimit - 1), isFalse);
      });
    }
  });
}

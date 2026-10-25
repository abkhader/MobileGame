import 'package:echo_core/echo_core.dart';
import 'package:echo_solver/echo_solver.dart';
import 'package:test/test.dart';

import 'data/multirun_levels.dart';

Level l(List<String> g, int runs) =>
    LevelLoader.fromMap({'id': 't', 'name': 't', 'runLimit': runs, 'grid': g});

/// An independent reference for [sparkProof]. It shares no code with the
/// solver: it reads only the level geometry and re-implements the movement
/// rules, and it uses none of the solver's reductions beyond two plain ones:
/// a stopped world is forgotten (its actors stored on the start), and each
/// state is kept at the earliest tick it is seen (the moves do not depend on
/// the tick, so an earlier tick can do all a later one can). There is no
/// ghost parking, no untracked live world, no distance prune, no skipped
/// move and no run count left out.
///
/// An `m`-run play is `m` worlds stepped tick by tick: world `k` holds the
/// runs `0..k`, run `k` being its live player. Each live run picks a move or
/// (before the final run) ends; its choice is applied to its actor in every
/// world that is still running. A world stops when its run ends; the final
/// world stops when its player reaches the exit, and the other worlds keep
/// going (an earlier run was played in full before the final run). The play
/// is invalid if an earlier world's player reaches the exit (that would be a
/// win with fewer runs). Returns whether some play with at most `runLimit`
/// runs wins and has the player of a run in [collectors] step onto [spark]
/// while its run is live, or null when a run count sees more than
/// [maxStates] states.
bool? referenceCollects(
  Level level,
  Position spark,
  Set<int> collectors, {
  int maxStates = 1 << 62,
}) {
  for (var m = 1; m <= level.runLimit; m++) {
    final found = _referenceRuns(level, spark, collectors, m, maxStates);
    if (found != false) return found;
  }
  return false;
}

bool? _referenceRuns(
  Level level,
  Position spark,
  Set<int> collectors,
  int m,
  int maxStates,
) {
  final w = level.width;
  final h = level.height;
  final cells = w * h;
  int idx(Position p) => p.y * w + p.x;
  final kind = [
    for (var i = 0; i < cells; i++) level.tileAt(Position(i % w, i ~/ w)),
  ];
  final start = idx(level.start);
  final exit = idx(level.exit);
  final target = idx(spark);
  int off(int k) => k * (k + 1) ~/ 2;
  final actors = off(m);
  const dx = [0, 0, -1, 1, 0];
  const dy = [-1, 1, 0, 0, 0];

  // State: actor positions, alive bits of runs 0..m-2, won, collected.
  int pack(List<int> pos, int alive, bool won, bool got) {
    var key = alive * 4 + (won ? 2 : 0) + (got ? 1 : 0);
    for (final p in pos) {
      key = key * cells + p;
    }
    return key;
  }

  final first = pack(
    List.filled(actors, start),
    (1 << (m - 1)) - 1,
    false,
    false,
  );
  final seen = <int>{first};
  var frontier = <int>[first];
  final pos = List<int>.filled(actors, 0);
  for (var tick = 0; tick < Rules.maxTicksPerRun; tick++) {
    final next = <int>[];
    for (final key in frontier) {
      var rest = key;
      for (var a = actors - 1; a >= 0; a--) {
        pos[a] = rest % cells;
        rest ~/= cells;
      }
      final got = rest & 1 == 1;
      final won = rest & 2 == 2;
      final alive = rest >> 2;
      bool runLive(int j) => j == m - 1 ? !won : alive & (1 << j) != 0;

      // Per world, where each actor goes for each of the 5 moves.
      final moved = List<List<int>>.generate(actors, (_) => List.filled(5, 0));
      for (var k = 0; k < m; k++) {
        final open = <int>{};
        for (var i = 0; i <= k; i++) {
          final t = kind[pos[off(k) + i]];
          if (t.kind == TileKind.door) open.add(pos[off(k) + i]);
          if (t.kind == TileKind.plate) {
            open.addAll(level.doors[t.channel]?.map(idx) ?? const <int>[]);
          }
        }
        for (var i = 0; i <= k; i++) {
          final p = pos[off(k) + i];
          for (var d = 0; d < 5; d++) {
            final x = p % w + dx[d];
            final y = p ~/ w + dy[d];
            var to = p;
            if (x >= 0 && y >= 0 && x < w && y < h) {
              final q = y * w + x;
              final t = kind[q].kind;
              if (t != TileKind.wall &&
                  (t != TileKind.door || open.contains(q))) {
                to = q;
              }
            }
            moved[off(k) + i][d] = to;
          }
        }
      }

      // Choices: 0-4 move, 5 end, 6 not live.
      final choice = List<int>.filled(m, 0);
      bool expand(int j) {
        if (j < m) {
          if (!runLive(j)) {
            choice[j] = 6;
            return expand(j + 1);
          }
          for (var c = 0; c < (j < m - 1 ? 6 : 5); c++) {
            choice[j] = c;
            if (expand(j + 1)) return true;
          }
          return false;
        }
        final nextPos = List<int>.of(pos);
        var nextAlive = alive;
        var nextWon = won;
        var nextGot = got;
        for (var k = 0; k < m; k++) {
          if (!runLive(k)) continue; // world k has stopped
          for (var i = 0; i <= k; i++) {
            final c = choice[i];
            if (c < 5) nextPos[off(k) + i] = moved[off(k) + i][c];
          }
          if (choice[k] == 5) {
            nextAlive &= ~(1 << k);
            continue;
          }
          final player = nextPos[off(k) + k];
          if (collectors.contains(k) && player == target) nextGot = true;
          if (player == exit) {
            if (k < m - 1) return false; // a win with fewer runs
            nextWon = true;
          }
        }
        if (nextWon && nextGot) return true;
        for (var k = 0; k < m; k++) {
          final stopped = k == m - 1 ? nextWon : nextAlive & (1 << k) == 0;
          if (stopped) nextPos.fillRange(off(k), off(k) + k + 1, start);
        }
        final key = pack(nextPos, nextAlive, nextWon, nextGot);
        if (seen.add(key)) next.add(key);
        if (seen.length > maxStates) throw const _TooBig();
        return false;
      }

      try {
        if (expand(0)) return true;
      } on _TooBig {
        return null;
      }
    }
    frontier = next;
  }
  return false;
}

class _TooBig implements Exception {
  const _TooBig();
}

/// [grid] with a spark on cell ([x], [y]).
List<String> withSpark(List<String> grid, int x, int y) => [
  for (var r = 0; r < grid.length; r++)
    r == y ? grid[r].replaceRange(x, x + 1, '*') : grid[r],
];

void main() {
  group('hand-built levels', () {
    test('a spark on the open route is collectible in run 1', () {
      final level = l(['#######', '#S.*.E#', '#######'], 1);
      final proof = sparkProof(level, level.sparks.single);
      expect(proof.budgetExceeded, isFalse);
      expect(proof.collectible, isTrue);
      expect(proof.echoNeeded, isFalse);
    });

    test('a spark on the open route of a 2-run level needs no echo', () {
      final level = l(['#######', '#S*aAE#', '#######'], 2);
      final proof = sparkProof(level, level.sparks.single);
      expect(proof.collectible, isTrue);
      expect(proof.echoNeeded, isFalse);
    });

    test('a walled-off spark is not collectible', () {
      final level = l(['S.E', '###', '.*.'], 2);
      final proof = sparkProof(level, level.sparks.single);
      expect(proof.budgetExceeded, isFalse);
      expect(proof.collectible, isFalse);
      expect(proof.echoNeeded, isFalse);
    });

    test('a spark behind a door an echo must hold needs an echo', () {
      const grid = ['Sa..E', '##A##', '##*##'];
      final two = l(grid, 2);
      final proof = sparkProof(two, two.sparks.single);
      expect(proof.collectible, isTrue);
      expect(proof.echoNeeded, isTrue);
      final one = l(grid, 1);
      expect(sparkProof(one, one.sparks.single).collectible, isFalse);
    });

    // The detour is 12 out and 12 back, the exit 3 more: 27 > 25 ticks.
    const detour = [
      '.......*',
      '.#######',
      '.#######',
      '.#######',
      '.#######',
      'S..E####',
    ];

    test('a detour that leaves no time to win is not collectible', () {
      final level = l(detour, 1);
      expect(solve(level), isA<Solved>());
      expect(sparkProof(level, level.sparks.single).collectible, isFalse);
    });

    // A run that touches no plate or door, only grabs the spark and ends:
    // the useless-run prune of the plain solver must not apply here.
    test('a first run may only grab the spark and end', () {
      final level = l(detour, 2);
      final proof = sparkProof(level, level.sparks.single);
      expect(proof.collectible, isTrue);
      expect(proof.echoNeeded, isFalse);
    });

    // Run 1 holds plate a on ticks 1-2 so run 2 can step into door A at
    // tick 3, then walks the 22 tiles to the spark (tick 24). Run 2 waits in
    // the door, which its presence keeps open, and wins at tick 25. Going to
    // the spark first leaves no time to hold the plate, and nobody can pass
    // the door alone (it is not next to the plate). The reference also lets
    // run 1 collect after run 2 has won; the solver stops at the win.
    test('an earlier run collects while the final run waits in a door', () {
      const grid = [
        'Sa.AE###',
        '#.######',
        '#......#',
        '######.#',
        '#......#',
        '#.######',
        '#......#',
        '######*#',
      ];
      final level = l(grid, 2);
      expect(solve(l(grid, 1)), isA<Unsolvable>());
      final proof = sparkProof(level, level.sparks.single);
      expect(proof.collectible, isTrue);
      expect(proof.echoNeeded, isFalse);
      expect(
        referenceCollects(level, level.sparks.single, {0}),
        isTrue,
        reason: 'the reference agrees',
      );
    });

    // Run 1 alone reaches the spark (tick 12), but in a winning play it must
    // hold plate a until run 2, which passes the spark on its way, steps into
    // door A at tick 14. Spark first puts run 1 on the plate at tick 25;
    // after the hold the spark is 13 tiles away (tick 26).
    test('a spark run 1 could reach, but only while not holding the plate, '
        'needs an echo', () {
      final level = l(['aS......', '#######.', 'EA.*....'], 2);
      final proof = sparkProof(level, level.sparks.single);
      expect(proof.collectible, isTrue);
      expect(proof.echoNeeded, isTrue);
      expect(referenceCollects(level, level.sparks.single, {0}), isFalse);
      expect(referenceCollects(level, level.sparks.single, {1}), isTrue);
    });

    // Plate a lies past the exit: a run stepping on E wins there and then,
    // so no ghost ever holds the plate, and nobody alone can pass door A
    // (not next to the plate) to the spark.
    test('an earlier run cannot cross the exit to help a later one', () {
      const grid = ['S.E.a', '#A###', '#*###'];
      for (final runs in [2, 3]) {
        final level = l(grid, runs);
        final proof = sparkProof(level, level.sparks.single);
        expect(proof.collectible, isFalse, reason: 'runs=$runs');
        expect(
          referenceCollects(level, level.sparks.single, {0, 1, 2}),
          isFalse,
          reason: 'the reference agrees, runs=$runs',
        );
      }
    });

    test('a spark that is not one of the level sparks is rejected', () {
      final level = l(['#######', '#S.*.E#', '#######'], 1);
      expect(
        () => sparkProof(level, const Position(2, 1)),
        throwsArgumentError,
      );
    });

    test('a tiny budget reports budgetExceeded', () {
      final level = l(['Sa..E', '##A##', '##*##'], 2);
      final proof = sparkProof(level, level.sparks.single, maxNodes: 5);
      expect(proof.budgetExceeded, isTrue);
      expect(proof.collectible, isFalse);
    });

    test('sparks do not change solve', () {
      const grid = ['#######', '#Sa.AE#', '#######'];
      final plain = solve(l(grid, 2)) as Solved;
      final sparked = solve(l(withSpark(grid, 3, 1), 2)) as Solved;
      expect(sparked.bestScore, plain.bestScore);
      expect(sparked.solution, plain.solution);
    });
  });

  // The reference has no reductions, so some 3-run cases are too big for
  // it: those (more than [cap] states for one run count) are skipped, and
  // the count of compared cases keeps the check meaningful.
  test('sparkProof agrees with the independent reference on the multi-run '
      'test levels', () {
    const cap = 20000;
    var checked = 0, threeRuns = 0, collectible = 0, echo = 0, none = 0;
    for (var n = 0; n < multiRunLevels.length; n++) {
      final (grid, runs) = multiRunLevels[n];
      final floor = <(int, int)>[
        for (var y = 0; y < grid.length; y++)
          for (var x = 0; x < grid[y].length; x++)
            if (grid[y][x] == '.') (x, y),
      ];
      if (floor.isEmpty) continue;
      final picks = {floor.first, floor[floor.length ~/ 2], floor.last};
      for (final (x, y) in picks) {
        final level = l(withSpark(grid, x, y), runs);
        final spark = level.sparks.single;
        final all = {for (var j = 0; j < runs; j++) j};
        final any = referenceCollects(level, spark, all, maxStates: cap);
        if (any == null) continue;
        final first = referenceCollects(level, spark, {0}, maxStates: cap);
        if (first == null) continue;
        final proof = sparkProof(level, spark);
        final label = 'level $n spark ($x,$y)';
        expect(proof.budgetExceeded, isFalse, reason: label);
        expect(proof.collectible, any, reason: label);
        expect(proof.echoNeeded, any && !first, reason: label);
        checked++;
        if (runs == 3) threeRuns++;
        if (!any) none++;
        if (any && !first) echo++;
        if (any) collectible++;
      }
    }
    // The comparison is not vacuous: every outcome occurs.
    expect(checked, greaterThan(200));
    expect(threeRuns, greaterThan(50));
    expect(collectible, greaterThan(0));
    expect(none, greaterThan(0));
    expect(echo, greaterThan(0));
  });
}

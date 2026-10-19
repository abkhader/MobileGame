import 'dart:math';

import 'package:echo_core/echo_core.dart';
import 'package:echo_solver/echo_solver.dart';
import 'package:test/test.dart';

import 'data/multirun_levels.dart';

Level l(List<String> g, int runs) =>
    LevelLoader.fromMap({'id': 't', 'name': 't', 'runLimit': runs, 'grid': g});

void main() {
  test('corridor', () {
    final r = solve(l(['#######', '#S...E#', '#######'], 1)) as Solved;
    expect(r.bestScore, 4);
    expect(r.solution, [
      [Move.right, Move.right, Move.right, Move.right],
    ]);
  });
  test('single-run plate and door', () {
    expect(
      (solve(l(['#######', '#S.aAE#', '#######'], 1)) as Solved).bestScore,
      4,
    );
  });
  test('two-run echo level', () {
    final level = l(['#######', '#Sa.AE#', '#######'], 2);
    final r = solve(level) as Solved;
    expect(r.bestScore, 5);
    expect(replayScore(level, r.solution), 5);
  });
  test('the echo level is unsolvable with one run', () {
    expect(solve(l(['#######', '#Sa.AE#', '#######'], 1)), isA<Unsolvable>());
  });
  test('an unreachable exit is unsolvable', () {
    expect(solve(l(['S#E'], 4)), isA<Unsolvable>());
  });
  test('a tiny budget reports BudgetExceeded instead of searching on', () {
    expect(
      solve(l(['#######', '#Sa.AE#', '#######'], 2), maxNodes: 10),
      isA<BudgetExceeded>(),
    );
  });
  test('replayScore rejects non-winning and over-long solutions', () {
    final level = l(['S..E'], 1);
    expect(
      replayScore(level, [
        [Move.right],
      ]),
      isNull,
    );
    expect(
      replayScore(level, [
        [Move.right, Move.right, Move.right, Move.wait],
      ]),
      isNull,
    );
  });
  test('replayScore rejects runs longer than 25 moves', () {
    final level = l(['S.E'], 2);
    final run = [...List.filled(25, Move.wait), Move.right];
    expect(
      replayScore(level, [
        run,
        [Move.right],
      ]),
      isNull,
    );
  });

  test('nodes are reported', () {
    final level = l(['#######', '#Sa.AE#', '#######'], 2);
    expect((solve(level) as Solved).nodes, greaterThan(0));
  });
  test('speed: two-door corridor', () {
    final r =
        solve(l(['a.S...b.', '#######A', '#######B', '#######E'], 3)) as Solved;
    expect(r.bestScore, 14);
    expect(r.nodes, lessThan(200000));
  });
  test('differential: pruning never changes the best score', () {
    for (final (grid, runs) in multiRunLevels) {
      final level = l(grid, runs);
      final label = '${grid.join('/')} runs=$runs';
      final unpruned = solveForTesting(level, prune: false);
      final pruned = solveForTesting(level);
      expect(unpruned, isA<Solved>(), reason: label);
      expect(pruned, isA<Solved>(), reason: label);
      final best = (unpruned as Solved).bestScore;
      expect((pruned as Solved).bestScore, best, reason: label);
      expect(replayScore(level, pruned.solution), best, reason: label);
      expect(pruned.nodes, lessThanOrEqualTo(unpruned.nodes), reason: label);
    }
  });
  // The only cheaper plan has a first run that never touches a plate: it just
  // pushes into door A (blocked while closed, then through once the final run
  // opens it) and pushes on. Dropping door targets from the pruning rule
  // makes the solver miss it and report 10.
  test('regression: a run that only targets a door still counts', () {
    final level = l(['bCaS', 'B.CA', '#E#c'], 3);
    final r = solve(level) as Solved;
    expect(r.bestScore, 9);
    expect(replayScore(level, r.solution), 9);
  });
  test('differential: pruned solver matches exhaustive search', () {
    final rng = Random(42);
    var compared = 0;
    var solvable = 0;
    var needingGhosts = 0;
    for (var i = 0; i < 300; i++) {
      final grid = _randomGrid(rng);
      final runs = 1 + rng.nextInt(3);
      final Level level;
      try {
        level = LevelLoader.fromMap({
          'id': 't',
          'name': 't',
          'runLimit': runs,
          'grid': grid,
        });
      } on LevelFormatException {
        continue;
      }
      compared++;
      final reference = _referenceBest(level);
      final result = solve(level, maxNodes: _nodeBudget);
      final label = '${grid.join('/')} runs=$runs';
      if (reference != null) {
        solvable++;
        expect(result, isA<Solved>(), reason: label);
        expect((result as Solved).bestScore, reference, reason: label);
        if (result.solution.length > 1) needingGhosts++;
      } else if (result is Solved) {
        expect(result.bestScore, greaterThan(_cap), reason: label);
      }
      if (result is Solved) {
        expect(
          replayScore(level, result.solution),
          result.bestScore,
          reason: label,
        );
      }
    }
    expect(compared, greaterThan(100));
    expect(solvable, greaterThan(50));
    expect(needingGhosts, greaterThan(0));
  });
}

// Total-score cap for the exhaustive reference. The brief asked for 9; that
// is far over the 30 s test budget for an unpruned search, so it is 6 here.
const _cap = 6;

// Plenty for any level the reference solves; stops unsolvable random levels
// (which the solver cannot rule out cheaply) from burning the full default.
const _nodeBudget = 500000;

List<String> _randomGrid(Random rng) {
  final w = 4 + rng.nextInt(2);
  final h = 2 + rng.nextInt(2);
  final cells = [
    for (var y = 0; y < h; y++)
      [for (var x = 0; x < w; x++) rng.nextDouble() < 0.2 ? '#' : '.'],
  ];
  final free = [
    for (var y = 0; y < h; y++)
      for (var x = 0; x < w; x++) (x, y),
  ]..shuffle(rng);
  void put(String c) {
    final (x, y) = free.removeLast();
    cells[y][x] = c;
  }

  put('S');
  put('E');
  final plates = rng.nextInt(3);
  for (var p = 0; p < plates; p++) {
    final letter = 'ab'[p];
    put(letter);
    for (var d = 1 + rng.nextInt(2); d > 0; d--) {
      put(letter.toUpperCase());
    }
  }
  return [for (final row in cells) row.join()];
}

/// Exhaustive reference: iterative deepening on total score over every action
/// sequence (all five moves each tick, endRun at any tick). No pruning rule;
/// the only shortcut is skipping a state already explored with at least as
/// much score budget left, keyed on everything that determines its future
/// (so the recording only counts before the last run).
int? _referenceBest(Level level) {
  final seen = <String, int>{};

  bool dfs(GameState s, int bound) {
    if (s.status == GameStatus.won) return true;
    if (s.status == GameStatus.lost) return false;
    final remaining = bound - s.score;
    if (remaining <= 0) return false;
    final key = [
      s.runIndex,
      s.tick,
      s.player,
      s.ghostPositions.join(','),
      s.ghosts.map((g) => g.map((m) => m.name).join()).join('|'),
      // In the last run the recording can never become a ghost.
      if (s.runIndex < level.runLimit - 1)
        s.currentRun.map((m) => m.name).join(),
    ].join(';');
    final prior = seen[key];
    if (prior != null && prior >= remaining) return false;
    seen[key] = remaining;
    for (final m in Move.values) {
      if (dfs(Rules.step(s, m), bound)) return true;
    }
    if (s.runIndex < level.runLimit - 1 && dfs(Rules.endRun(s), bound)) {
      return true;
    }
    return false;
  }

  for (var bound = 1; bound <= _cap; bound++) {
    seen.clear();
    if (dfs(GameState.initial(level), bound)) return bound;
  }
  return null;
}

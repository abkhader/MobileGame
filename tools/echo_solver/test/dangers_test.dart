import 'package:echo_core/echo_core.dart';
import 'package:echo_solver/echo_solver.dart';
import 'package:test/test.dart';

import 'danger_reference.dart';

Level l(List<String> g, int runs) =>
    LevelLoader.fromMap({'id': 't', 'name': 't', 'runLimit': runs, 'grid': g});

List<List<Move>> moves(String runs) => [
  for (final run in runs.split('|'))
    [for (final c in run.trim().split('')) Move.fromCode(c)],
];

/// [solve] and the independent [DangerReference] agree that [level]'s best
/// score is [best] (null: unsolvable), and the solution replays to it. A
/// solvable level is also checked against [solveSequential] (on unsolvable
/// danger levels it runs out of budget: it cannot rule them out cheaply).
void expectBest(Level level, int? best) {
  final result = solve(level);
  if (best == null) {
    expect(result, isA<Unsolvable>());
  } else {
    expect(result, isA<Solved>());
    final solved = result as Solved;
    expect(solved.bestScore, best);
    expect(replayScore(level, solved.solution), best);
    final sequential = solveSequential(level);
    expect(sequential, isA<Solved>(), reason: 'solveSequential');
    expect((sequential as Solved).bestScore, best, reason: 'solveSequential');
  }
  expect(DangerReference(level).best(), best, reason: 'the reference');
}

void main() {
  group('hand-built danger levels: solve agrees with Rules.step', () {
    // The beat-2 laser fires on ticks 2, 5, 8...: walking straight puts Pip
    // on it at tick 2, so he waits one beat first.
    test('laser timing forces a wait', () {
      expectBest(l(['S.2.E'], 1), 5);
      expectBest(l(['S...E'], 1), 4);
    });

    // Pip must hold plate b (a dead end) while the echo passes door B, then
    // cross the crack to door A, which the echo opens from plate a. The
    // echo crosses the crack first and it breaks behind it: Pip cannot
    // follow. With plain floor that plan costs 12; with the crack 2 runs
    // are not enough, and 3 runs win at 12 (an echo holds b while Pip
    // follows the other echo across). The reference takes about 6 minutes
    // for 3 runs, so that case is checked by replay only.
    const bridge = ['b.S~.Ba', '###.###', '###A###', '###E###'];
    test('a crack bridge only one crossing can use', () {
      expectBest(l(bridge, 2), null);
      expectBest(l([for (final r in bridge) r.replaceAll('~', '.')], 2), 12);
      final three = solve(l(bridge, 3)) as Solved;
      expect(three.bestScore, 12);
      expect(three.solution, hasLength(3));
      expect(replayScore(l(bridge, 3), three.solution), 12);
      final sequential = solveSequential(l(bridge, 3));
      expect((sequential as Solved).bestScore, 12);
    });

    // Alone, Pip meets the Shade wherever he goes. An echo that steps right
    // and stops is nearer to the Shade once Pip turns up: the Shade takes
    // the echo and Pip slips past to the exit.
    test('an echo lures a Shade so Pip passes', () {
      const decoy = ['..xE.', 'S....'];
      expectBest(l(decoy, 1), null);
      expectBest(l(decoy, 2), 5);
      expectBest(l(['...E.', 'S....'], 1), 4);
    });

    // The Shade's closet opens only through door A. Pip opens it himself by
    // stepping on plate a, and is on the exit before the Shade gets out.
    // Without the door the Shade catches him.
    test('a Shade trapped behind a door', () {
      expectBest(l(['aE##', 'SAx.'], 1), 2);
      expectBest(l(['.E##', 'S.x.'], 1), null);
    });

    // Run 1 walks into the Shade and is caught: a forced rewind, so its
    // single move becomes the echo. That echo is the Shade's bait while Pip
    // passes the beat-1 laser (safe on tick 2) and plate a to door A. Ending
    // run 1 by hand before the fatal move leaves the echo on the start,
    // where Pip is the Shade's first choice; one run alone loses.
    test('a Pip hit forces a rewind, which counts as a run', () {
      const row = ['EAa1Sx'];
      expectBest(l(row, 1), null);
      expectBest(l(row, 2), 6);
      final solution = (solve(l(row, 2)) as Solved).solution;
      expect(solution.first, [Move.right]);
      final hit = Rules.step(GameState.initial(l(row, 2)), Move.right);
      expect((hit.lastHits.pip, hit.runIndex), (true, 1));
    });

    // Pip holds plate a so the echo can pass door A. In its own run door A
    // never opened (it bumped into it on the start), but in Pip's world the
    // echo walks on and stands on the beat-3 laser at tick 3: it dies there
    // and never reaches plate b, so Pip never gets through door B. The same
    // plan wins at 10 without the laser; the echo has to wait a beat (12).
    test('an echo dies on a laser it reached by divergence', () {
      const danger = ['EBaSA3b'];
      const plain = ['EBaSA.b'];
      expectBest(l(danger, 2), 12);
      expectBest(l(plain, 2), 10);
      final plan = moves('RRRR | LLLLLL');
      expect(replayScore(l(plain, 2), plan), 10);
      expect(replayScore(l(danger, 2), plan), isNull);
      // Run 1 alone: bumps into the closed door on every move.
      var s = GameState.initial(l(danger, 2));
      for (final m in plan.first) {
        s = Rules.step(s, m);
      }
      expect(s.player, const Position(3, 0));
      // Pip's world: the echo passes door A and is zapped at tick 3.
      s = Rules.endRun(s);
      for (final m in plan.last.take(3)) {
        s = Rules.step(s, m);
      }
      expect(s.lastHits.ghosts, [0]);
      expect(s.ghostPositions.single, const Position(5, 0));
    });

    // Two Shades flank the way to the exit. Runs 1 and 2 are each caught at
    // once as bait (forced rewinds), run 3 ends at tick 0 so its echo waits
    // on the start as a third light, and Pip walks out: all 4 runs needed.
    test('a 4-run danger level needs every run', () {
      const grid = ['.xE', '#S.', '..x'];
      expectBest(l(grid, 4), 5);
      expect((solve(l(grid, 4)) as Solved).solution, hasLength(4));
      expectBest(l(grid, 3), null);
    });

    test('a 4-run limit on a level that needs 2 runs', () {
      expectBest(l(['EAa1Sx'], 4), 6);
    });
  });

  group('spark proofs on danger levels agree with Rules.step', () {
    // Run 1 can collect the spark (wait, then pass the laser on tick 2),
    // but only after Pip has won at tick 1 in the final world: Pip cannot
    // wait beside the exit, because the Shade would catch him there. So the
    // search must keep earlier worlds going after the final win.
    test('an earlier run collects after the final run has won', () {
      final level = l(['*#.x', '1SE.', '.#..'], 2);
      final spark = level.sparks.single;
      final proof = sparkProof(level, spark);
      expect(proof.budgetExceeded, isFalse);
      expect(proof.collectible, isTrue);
      expect(proof.echoNeeded, isFalse);
      final reference = DangerReference(level);
      expect(reference.collects(spark, {0}), isTrue);
      expect(
        reference.collects(spark, {0}, stopAtWin: true),
        isFalse,
        reason: 'only a collection after the win exists',
      );
    });

    // Every floor cell of each level as the spark: collectible and "needs
    // an echo" match the reference.
    const levels = <(List<String>, int)>[
      (['..xE.', 'S....'], 2),
      (['.xE', '#S.', '..x'], 4),
      (['S.2.E', '.#.#.'], 1),
      (['x.*', 'ASE', 'a..'], 2),
      (['*AE.a', '..S.x'], 2),
      (['S~.E', '..a#', '#A..'], 2),
    ];
    for (final (grid, runs) in levels) {
      test('${grid.join('/')} runs=$runs', () {
        final cells = [
          for (var y = 0; y < grid.length; y++)
            for (var x = 0; x < grid[y].length; x++)
              if (grid[y][x] == '.' || grid[y][x] == '*') (x, y),
        ];
        var collectible = 0;
        for (final (x, y) in cells) {
          final g = [
            for (var r = 0; r < grid.length; r++)
              r == y
                  ? grid[r].replaceAll('*', '.').replaceRange(x, x + 1, '*')
                  : grid[r].replaceAll('*', '.'),
          ];
          final level = l(g, runs);
          final spark = Position(x, y);
          final reference = DangerReference(level);
          final any = reference.collects(spark, {0, 1, 2, 3});
          final first = reference.collects(spark, {0});
          final proof = sparkProof(level, spark);
          final label = '${g.join('/')} spark ($x,$y)';
          expect(proof.budgetExceeded, isFalse, reason: label);
          expect(proof.collectible, any, reason: label);
          expect(proof.echoNeeded, any && !first, reason: label);
          if (any) collectible++;
        }
        expect(collectible, greaterThan(0));
      });
    }
  });

  test('replayScore counts a run cut short by a hit and rejects moves after '
      'it', () {
    final level = l(['EAa1Sx'], 2);
    expect(replayScore(level, moves('R | WLLLL')), 6);
    expect(replayScore(level, moves('RL | WLLLL')), isNull);
  });
}

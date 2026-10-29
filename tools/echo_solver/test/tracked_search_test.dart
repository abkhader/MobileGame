import 'dart:io';

import 'package:echo_core/echo_core.dart';
import 'package:echo_solver/echo_solver.dart';
import 'package:test/test.dart';

import 'danger_reference.dart';
import 'data/multirun_levels.dart';

Level l(List<String> g, int runs) =>
    LevelLoader.fromMap({'id': 't', 'name': 't', 'runLimit': runs, 'grid': g});

/// [level] with [cell] walled and no sparks (the pre-danger optional proof).
Level walled(Level level, Position cell) => Level(
  id: level.id,
  name: level.name,
  runLimit: level.runLimit,
  grid: [
    for (var y = 0; y < level.height; y++)
      [
        for (var x = 0; x < level.width; x++)
          Position(x, y) == cell
              ? const Tile(TileKind.wall)
              : level.tileAt(Position(x, y)),
      ],
  ],
  start: level.start,
  exit: level.exit,
  plates: level.plates,
  doors: level.doors,
  sparks: const [],
  lasers: level.lasers,
  cracked: level.cracked,
  shadeStarts: level.shadeStarts,
);

/// [grid] with a spark on cell ([x], [y]).
List<String> withSpark(List<String> grid, int x, int y) => [
  for (var r = 0; r < grid.length; r++)
    r == y ? grid[r].replaceRange(x, x + 1, '*') : grid[r],
];

void main() {
  test('chapters 1-3 have no dangers, so they keep the old search; '
      'every chapter 4 level has dangers', () {
    final files = Directory(
      '../../app/assets/levels',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
    for (final f in files) {
      final level = LevelLoader.parse(f.readAsStringSync());
      expect(hasDangers(level), level.id.startsWith('4-'), reason: level.id);
    }
  });

  // The every-world search is what solve uses on danger levels. On levels
  // without dangers it must agree with the established joint search.
  test('the every-world search matches solve on the multi-run levels', () {
    for (final (grid, runs) in multiRunLevels) {
      final level = l(grid, runs);
      final label = '${grid.join('/')} runs=$runs';
      final plain = solve(level) as Solved;
      final tracked = solveTracked(level);
      expect(tracked, isA<Solved>(), reason: label);
      expect((tracked as Solved).bestScore, plain.bestScore, reason: label);
      expect(
        replayScore(level, tracked.solution),
        plain.bestScore,
        reason: label,
      );
    }
  });

  test('the every-world spark search matches sparkProof on the multi-run '
      'levels', () {
    var echo = 0, none = 0, first = 0;
    for (final (grid, runs) in multiRunLevels.where((e) => e.$2 == 2)) {
      final floor = <(int, int)>[
        for (var y = 0; y < grid.length; y++)
          for (var x = 0; x < grid[y].length; x++)
            if (grid[y][x] == '.') (x, y),
      ];
      if (floor.isEmpty) continue;
      for (final (x, y) in {
        floor.first,
        floor[floor.length ~/ 2],
        floor.last,
      }) {
        final level = l(withSpark(grid, x, y), runs);
        final spark = level.sparks.single;
        final plain = sparkProof(level, spark);
        final tracked = sparkProof(level, spark, tracked: true);
        final label = '${grid.join('/')} spark ($x,$y)';
        expect(tracked.budgetExceeded, isFalse, reason: label);
        expect(tracked.collectible, plain.collectible, reason: label);
        expect(tracked.echoNeeded, plain.echoNeeded, reason: label);
        if (!plain.collectible) none++;
        if (plain.echoNeeded) echo++;
        if (plain.collectible && !plain.echoNeeded) first++;
      }
    }
    // 3-run levels: one spark each, under a small budget (the every-world
    // search is exhaustive and a few of them take seconds); over-budget
    // cases are skipped and counted.
    var three = 0;
    for (final (grid, runs) in multiRunLevels.where((e) => e.$2 == 3)) {
      final floor = <(int, int)>[
        for (var y = 0; y < grid.length; y++)
          for (var x = 0; x < grid[y].length; x++)
            if (grid[y][x] == '.') (x, y),
      ];
      if (floor.isEmpty) continue;
      final (x, y) = floor[floor.length ~/ 2];
      final level = l(withSpark(grid, x, y), runs);
      final spark = level.sparks.single;
      final tracked = sparkProof(level, spark, tracked: true, maxNodes: 200000);
      if (tracked.budgetExceeded) continue;
      final plain = sparkProof(level, spark);
      final label = '${grid.join('/')} spark ($x,$y)';
      expect(tracked.collectible, plain.collectible, reason: label);
      expect(tracked.echoNeeded, plain.echoNeeded, reason: label);
      three++;
    }
    expect(three, greaterThan(30));
    expect(echo, greaterThan(0));
    expect(none, greaterThan(0));
    expect(first, greaterThan(0));
  });

  // Without dangers, walling the cell is exact (see cli.dart _avoidable),
  // so the avoid search must agree with it.
  test('avoid matches walling the cell on levels without dangers', () {
    var avoidable = 0, forced = 0;
    for (final (grid, runs) in multiRunLevels.take(40)) {
      final level = l(grid, runs);
      for (var y = 0; y < grid.length; y++) {
        for (var x = 0; x < grid[y].length; x++) {
          if (grid[y][x] != '.') continue;
          final cell = Position(x, y);
          final viaWall = solve(walled(level, cell)) is Solved;
          final viaAvoid = solveTracked(level, avoid: cell) is Solved;
          expect(viaAvoid, viaWall, reason: '${grid.join('/')} $cell');
          viaWall ? avoidable++ : forced++;
        }
      }
    }
    expect(avoidable, greaterThan(0));
    expect(forced, greaterThan(0));
  });

  // With Shades a wall also blocks the Shades, so walling answers a
  // different question; each of these got the wrong answer by walling. The
  // avoid search agrees with the reference.
  test('avoid matches the reference where walling the cell is wrong', () {
    const cases = <(List<String>, int, int, bool)>[
      // grid, spark x, y, some win avoids it
      (['SxE', '.*.'], 1, 1, true),
      (['S*.E', '...x', '#..#'], 1, 0, true),
      (['#S...', '1#*.#', '.x.E.'], 2, 1, true),
      (['x*S', 'E..', '.aA'], 1, 0, true),
      (['.A..#', 'x*..#', '.E#Sa'], 1, 1, false),
      (['.A..#', 'x.*.#', '.E#Sa'], 2, 1, false),
    ];
    for (final (grid, x, y, avoids) in cases) {
      final level = l(grid, 2);
      final cell = Position(x, y);
      final label = grid.join('/');
      expect(DangerReference(level).avoids(cell), avoids, reason: label);
      expect(solveTracked(level, avoid: cell) is Solved, avoids, reason: label);
      expect(
        solve(walled(level, cell)) is Solved,
        !avoids,
        reason: '$label: walling disagrees',
      );
    }
  });

  test('avoid on danger levels matches the reference on every floor cell', () {
    const levels = <(List<String>, int)>[
      (['..xE.', 'S....'], 2),
      (['S~.E', '..a#', '#A..'], 2),
      (['.xE', '#S.', '..x'], 4),
    ];
    var yes = 0, no = 0;
    for (final (grid, runs) in levels) {
      final level = l(grid, runs);
      final reference = DangerReference(level);
      for (var y = 0; y < grid.length; y++) {
        for (var x = 0; x < grid[y].length; x++) {
          if (grid[y][x] != '.') continue;
          final cell = Position(x, y);
          final expected = reference.avoids(cell);
          expect(
            solveTracked(level, avoid: cell) is Solved,
            expected,
            reason: '${grid.join('/')} $cell',
          );
          expected ? yes++ : no++;
        }
      }
    }
    expect(yes, greaterThan(0));
    expect(no, greaterThan(0));
  });
}

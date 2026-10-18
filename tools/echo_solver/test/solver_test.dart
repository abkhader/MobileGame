import 'package:echo_core/echo_core.dart';
import 'package:echo_solver/echo_solver.dart';
import 'package:test/test.dart';

Level l(List<String> g, int runs) =>
    LevelLoader.fromMap({'id': 't', 'name': 't', 'runLimit': runs, 'grid': g});

void main() {
  test('corridor', () {
    final r = solve(l(['#######', '#S...E#', '#######'], 1)) as Solved;
    expect(r.bestScore, 4);
    expect(r.solution, [
      [Move.right, Move.right, Move.right, Move.right]
    ]);
  });
  test('single-run plate and door', () {
    expect((solve(l(['#######', '#S.aAE#', '#######'], 1)) as Solved).bestScore,
        4);
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
    expect(solve(l(['#######', '#Sa.AE#', '#######'], 2), maxNodes: 10),
        isA<BudgetExceeded>());
  });
  test('replayScore rejects non-winning and over-long solutions', () {
    final level = l(['S..E'], 1);
    expect(
        replayScore(level, [
          [Move.right]
        ]),
        isNull);
    expect(
        replayScore(level, [
          [Move.right, Move.right, Move.right, Move.wait]
        ]),
        isNull);
  });
}

import 'package:echo_core/echo_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

// Plate at (0,0), start at (1,0), door at (2,0), exit at (3,0).
const G = ['aSAE'];

void main() {
  test('endRun records a ghost and resets actors to start', () {
    final s = play(GameState.initial(lvl(G, runLimit: 2)), 'L|');
    expect((s.runIndex, s.tick, s.completedTicks), (1, 0, 1));
    expect(s.ghosts, [
      [Move.left]
    ]);
    expect(s.player, const Position(1, 0));
    expect(s.ghostPositions, [const Position(1, 0)]);
  });
  test('a ghost opens a door only from the next tick', () {
    var s = play(GameState.initial(lvl(G, runLimit: 2)), 'L|R');
    expect(s.player, const Position(1, 0)); // blocked: door was closed
    expect(s.openDoors, {const Position(2, 0)});
    s = play(s, 'RR');
    expect((s.status, s.score), (GameStatus.won, 4));
  });
  test('a finished ghost stays where it stopped', () {
    final s = play(GameState.initial(lvl(G, runLimit: 2)), 'L|WW');
    expect(s.ghostPositions, [const Position(0, 0)]);
  });
  test('ghost moves are re-evaluated against current doors', () {
    final s = play(GameState.initial(lvl(G, runLimit: 2)), 'WR|LW');
    expect(s.ghostPositions, [const Position(2, 0)]);
  });
  test('a ghost on the exit does not win', () {
    final s = play(GameState.initial(lvl(G, runLimit: 2)), 'WRR|LWW');
    expect(s.ghostPositions, [const Position(3, 0)]);
    expect(s.status, GameStatus.playing);
  });
  test('ending the last run loses', () {
    final s = play(GameState.initial(lvl(G)), 'L|');
    expect(s.status, GameStatus.lost);
  });
  test('a run ends automatically after 25 ticks', () {
    final s = play(GameState.initial(lvl(G, runLimit: 2)), 'W' * 25);
    expect((s.runIndex, s.tick, s.completedTicks), (1, 0, 25));
  });
  test('reaching the exit on tick 25 wins', () {
    final s = play(GameState.initial(lvl(['S...E'])), '${'W' * 21}RRRR');
    expect((s.status, s.score), (GameStatus.won, 25));
  });
  test('ending a run at tick 0 records an empty ghost', () {
    final s = play(GameState.initial(lvl(G, runLimit: 2)), '|');
    expect(s.runIndex, 1);
    expect(s.ghosts, [<Move>[]]);
    expect(s.ghostPositions, [const Position(1, 0)]);
  });
  test('endRun on a finished state throws', () {
    final s = play(GameState.initial(lvl(G)), 'L|');
    expect(() => Rules.endRun(s), throwsStateError);
  });
}

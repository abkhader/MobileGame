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
      [Move.left],
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
  test('ending the last run loses and counts it once', () {
    final s = play(GameState.initial(lvl(G)), 'WW|');
    expect(s.status, GameStatus.lost);
    expect(s.score, 2);
    expect(s.ghosts, isEmpty);
    expect(s.ghostPositions, isEmpty);
    expect(s.currentRun, [Move.wait, Move.wait]);
    expect(s.tick, 2);
  });
  test('running out the clock on a one-run level scores 25', () {
    final s = play(GameState.initial(lvl(['S.E'])), 'W' * 25);
    expect(s.status, GameStatus.lost);
    expect(s.score, 25);
  });
  test(
    'losing on a later run keeps earlier ghosts and counts every tick once',
    () {
      final s = play(GameState.initial(lvl(G, runLimit: 2)), 'L|WW|');
      expect(s.status, GameStatus.lost);
      expect(s.score, 3);
      expect(s.ghosts, [
        [Move.left],
      ]);
      expect(s.ghostPositions.length, 1);
    },
  );
  test('a ghost blocked mid-replay stays put', () {
    // b plate (1,0) opens door B (2,1); a plate (4,0) opens door A (0,0).
    // Run 1: L onto b, then blocked by closed A. Ghost 1 = LLLL.
    // Run 2: ghost 1 sits on b, so B is open and the player passes at tick 3
    // (ghost 2 = WWWD). Run 3: the player (RRWW) reaches a at tick 1, so
    // ghost 1 walks through A at tick 2 and leaves b, closing B. Ghost 2's
    // D at tick 3 is then blocked by closed B and it stays at (2,0).
    final s = play(
      GameState.initial(lvl(['AbS.a', '##B##', '##.E#'], runLimit: 3)),
      'LLLL|WWWD|RRWW',
    );
    expect(s.ghostPositions, [const Position(0, 0), const Position(2, 0)]);
    expect(s.openDoors, {const Position(0, 0)});
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

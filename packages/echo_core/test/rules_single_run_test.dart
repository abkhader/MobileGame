import 'package:echo_core/echo_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  test('moving onto floor advances the player, tick and recording', () {
    final s = play(GameState.initial(lvl(['S..E'])), 'R');
    expect((s.player, s.tick), (const Position(1, 0), 1));
    expect(s.currentRun, [Move.right]);
  });
  test('walls and grid edges block, but the tick still counts', () {
    final s = play(GameState.initial(lvl(['#S.E'])), 'LU');
    expect((s.player, s.tick), (const Position(1, 0), 2));
  });
  test('a closed door blocks', () {
    final s = play(GameState.initial(lvl(['SAE', 'a..'])), 'R');
    expect(s.player, const Position(0, 0));
  });
  test(
      'a door opens at the end of the tick its plate is pressed, '
      'stays open while occupied, and the player wins on the exit', () {
    var s = play(GameState.initial(lvl(['SaAE'])), 'R');
    expect(s.openDoors, {const Position(2, 0)});
    s = play(s, 'R'); // into the doorway, plate released
    expect(s.openDoors, {const Position(2, 0)}); // no crushing
    s = play(s, 'R');
    expect((s.status, s.score), (GameStatus.won, 3));
  });
  test('a door closes when its plate and doorway are empty', () {
    final s = play(GameState.initial(lvl(['SaA.E'])), 'RL');
    expect(s.openDoors, isEmpty);
  });
  test('one plate opens every door with its letter', () {
    final s = play(GameState.initial(lvl(['SaAE', '..A.'])), 'R');
    expect(s.openDoors, {const Position(2, 0), const Position(2, 1)});
  });
  test('stepping after the level ends throws StateError', () {
    final s = play(GameState.initial(lvl(['SE'])), 'R');
    expect(() => Rules.step(s, Move.wait), throwsStateError);
  });
}

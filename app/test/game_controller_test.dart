import 'package:echo_app/game/game_controller.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter_test/flutter_test.dart';

Level _level(List<String> grid, {int runLimit = 2, int? bestScore}) =>
    LevelLoader.fromMap({
      'id': 't',
      'name': 't',
      'runLimit': runLimit,
      'grid': grid,
      'bestScore': ?bestScore,
    });

void main() {
  test('move and undo', () {
    final c = GameController(_level(['S..E']));
    c.move(Move.right);
    expect(c.state.player, const Position(1, 0));
    expect(c.lastEvent, GameEvent.moved);
    expect(c.previous!.player, const Position(0, 0));
    expect(c.canUndo, isTrue);
    c.undo();
    expect(c.state.player, const Position(0, 0));
    expect(c.previous, isNull);
    expect(c.lastEvent, GameEvent.none);
    expect(c.canUndo, isFalse);
  });

  test('win gives stars and ignores further moves silently', () {
    final c = GameController(_level(['S..E'], bestScore: 3));
    for (var i = 0; i < 3; i++) {
      c.move(Move.right);
    }
    expect(c.lastEvent, GameEvent.won);
    expect(c.stars, 3);
    expect(c.previous, isNotNull);
    expect(c.canUndo, isFalse);
    var n = 0;
    c.addListener(() => n++);
    final s = c.state;
    c.move(Move.left);
    expect(c.state, same(s));
    expect(n, 0);
  });

  test('end run', () {
    final c = GameController(_level(['aSAE']));
    expect(c.canEndRun, isFalse);
    c.move(Move.left);
    expect(c.canEndRun, isTrue);
    c.endRun();
    expect(c.lastEvent, GameEvent.runEnded);
    expect(c.state.runIndex, 1);
    expect(c.canUndo, isFalse);
    expect(c.previous, isNull);
  });

  test('automatic run end at tick 25 snaps', () {
    final c = GameController(_level(['aSAE']));
    for (var i = 0; i < 25; i++) {
      c.move(Move.wait);
    }
    expect(c.lastEvent, GameEvent.runEnded);
    expect(c.state.runIndex, 1);
    expect(c.previous, isNull);
    expect(c.canUndo, isFalse);
  });

  test('lose', () {
    final c = GameController(_level(['aSAE'], runLimit: 1));
    c.move(Move.left);
    c.endRun();
    expect(c.lastEvent, GameEvent.lost);
    expect(c.state.status, GameStatus.lost);
    expect(c.state.currentRun, [Move.left]);
    expect(c.canUndo, isFalse);
    expect(c.canEndRun, isFalse);
    expect(c.stars, isNull);
  });

  test('restart resets and notifies even at the start', () {
    final level = _level(['S..E']);
    final c = GameController(level);
    var n = 0;
    c.addListener(() => n++);
    c.restart();
    expect(n, 1);
    c.move(Move.right);
    c.restart();
    expect(n, 3);
    expect(c.state.player, GameState.initial(level).player);
    expect(c.state.tick, 0);
    expect(c.lastEvent, GameEvent.none);
    expect(c.previous, isNull);
    expect(c.canUndo, isFalse);
  });

  test('each action notifies exactly once; ignored actions do not', () {
    final c = GameController(_level(['aSAE']));
    var n = 0;
    c.addListener(() => n++);
    c.undo();
    c.endRun();
    expect(n, 0);
    c.move(Move.left);
    expect(n, 1);
    c.undo();
    expect(n, 2);
    c.move(Move.left);
    c.endRun();
    expect(n, 4);
  });
}

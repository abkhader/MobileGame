import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/game/flow_controller.dart';
import 'package:echo_app/game/game_clock.dart';
import 'package:echo_app/game/game_controller.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Level _level(List<String> grid, {int runLimit = 2}) => LevelLoader.fromMap({
  'id': 't',
  'name': 't',
  'runLimit': runLimit,
  'grid': grid,
});

FlowController _flow(GameController game) =>
    FlowController(game: game, speed: () => MoveSpeed.normal);

/// Advances in 50 ms frames, like a steady render loop.
void _hold(FlowController f, double seconds) {
  for (var t = 0.0; t < seconds - 1e-9; t += 0.05) {
    f.advance(0.05);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isBlocked: wall true, open tile false, wait false', () async {
    final level = await LevelRepository(PlatformAssetBundle()).load('1-01');
    final game = GameController(level);
    final p = game.state.player;
    final moves = [Move.up, Move.down, Move.left, Move.right];
    final blocked = [for (final m in moves) game.isBlocked(m)];
    expect(blocked, contains(true));
    expect(blocked, contains(false));
    for (var i = 0; i < moves.length; i++) {
      expect(
        game.isBlocked(moves[i]),
        Rules.step(game.state, moves[i]).player == p,
      );
    }
    expect(game.isBlocked(Move.wait), isFalse);
  });

  test('holding into a wall pushes: one tick and one bump per beat', () {
    final game = GameController(_level(['#S.E']));
    final f = _flow(game);
    f.setIntent(IntentKind.move, Move.left);
    _hold(f, 0.95);
    expect(game.state.tick, 5);
    expect(game.state.player, const Position(1, 0));
    expect(f.bumps.value, 5);
    expect(f.bumpDir.value, Move.left);
  });

  test('pushing a door that a ghost opens goes through the beat after', () {
    final game = GameController(_level(['a..SAE']));
    final f = _flow(game);
    f.setIntent(IntentKind.move, Move.left);
    _hold(f, 0.5);
    f.setIntent(IntentKind.none);
    _hold(f, 0.2);
    expect(game.state.tick, 3);
    game.endRun();
    expect(game.state.runIndex, 1);

    f.setIntent(IntentKind.move, Move.right); // beat 1
    _hold(f, 0.45); // beats 2 and 3
    expect(game.state.tick, 3);
    expect(game.state.player, const Position(3, 0));
    expect(f.bumps.value, 3);
    _hold(f, 0.2); // beat 4: the ghost holds the plate, the door is open
    expect(game.state.tick, 4);
    expect(game.state.player, const Position(4, 0));
    expect(f.bumps.value, 3);
  });

  test('stored solutions replay raw moves to bestScore', () async {
    final repo = LevelRepository(PlatformAssetBundle());
    for (final id in await repo.levelIds()) {
      final level = await repo.load(id);
      final game = GameController(level);
      final f = _flow(game);
      final solution = level.solution!;
      for (var i = 0; i < solution.length; i++) {
        for (final m in solution[i]) {
          f.setIntent(m == Move.wait ? IntentKind.wait : IntentKind.move, m);
          f.setIntent(IntentKind.none);
          f.advance(0.2);
        }
        if (game.state.status == GameStatus.playing &&
            game.state.runIndex == i) {
          game.endRun();
        }
      }
      expect(game.state.status, GameStatus.won, reason: id);
      expect(game.state.score, level.bestScore, reason: id);
    }
  });

  test('rewind stops at run start', () {
    final game = GameController(_level(['S...E']));
    final f = _flow(game);
    for (var i = 0; i < 3; i++) {
      f.setIntent(IntentKind.move, Move.right);
      f.setIntent(IntentKind.none);
      f.advance(0.2);
    }
    expect(game.state.tick, 3);
    f.setIntent(IntentKind.rewind);
    _hold(f, 1);
    expect(game.state.tick, 0);
    expect(f.clock.running, isFalse);
    expect(f.frozen, isTrue);
    expect(game.state.runIndex, 0);
  });

  test('rewind never crosses into a previous run', () {
    final game = GameController(_level(['aSAE']));
    final f = _flow(game);
    f.setIntent(IntentKind.move, Move.left);
    f.setIntent(IntentKind.none);
    f.advance(0.2);
    game.endRun();
    f.setIntent(IntentKind.rewind);
    _hold(f, 1);
    expect(game.state.runIndex, 1);
    expect(f.clock.running, isFalse);
  });

  test('run end stops the clock', () {
    final game = GameController(_level(['S...E']));
    final f = _flow(game);
    f.setIntent(IntentKind.move, Move.right);
    _hold(f, 0.25);
    expect(game.state.tick, 2);
    game.endRun();
    expect(f.clock.running, isFalse);
    expect(f.frozen, isTrue);
    expect(game.state.tick, 0);
    _hold(f, 1);
    expect(game.state.tick, 0);
    expect(game.state.runIndex, 1);
    expect(f.from, isNull);

    final g2 = GameController(_level(['aSAE'], runLimit: 3));
    final f2 = _flow(g2);
    f2.setIntent(IntentKind.wait);
    _hold(f2, 25 * 0.2 + 0.5);
    expect(g2.state.runIndex, 1);
    expect(f2.clock.running, isFalse);
    expect(f2.frozen, isTrue);
    final tick = g2.state.tick;
    _hold(f2, 2);
    expect(g2.state.tick, tick);
    expect(g2.state.runIndex, 1);
  });

  test('a win stops the clock and clears the intent', () {
    final game = GameController(_level(['SE']));
    final f = _flow(game);
    f.setIntent(IntentKind.move, Move.right);
    expect(game.lastEvent, GameEvent.won);
    expect(f.frozen, isTrue);
    _hold(f, 1);
    expect(game.state.tick, 1);
  });

  test('forward beat interpolates from the previous state', () {
    final game = GameController(_level(['S...E']));
    final f = _flow(game);
    final before = game.state;
    f.setIntent(IntentKind.move, Move.right);
    expect(f.from, same(before));
    expect(f.beatProgress, 0);
    f.advance(0.1);
    expect(f.beatProgress, closeTo(0.5, 1e-6));
    f.advance(0.0999);
    expect(f.beatProgress, closeTo(1, 0.01));
    expect(f.from, same(before));
  });

  test('rewind beat interpolates from the state before the undo', () {
    final game = GameController(_level(['S...E']));
    final f = _flow(game);
    for (var i = 0; i < 3; i++) {
      f.setIntent(IntentKind.move, Move.right);
      f.setIntent(IntentKind.none);
      f.advance(0.2);
    }
    final before = game.state;
    f.setIntent(IntentKind.rewind);
    expect(game.state.tick, 2);
    expect(f.from, same(before));
    expect(f.beatProgress, 0);
    f.advance(0.05);
    expect(f.beatProgress, closeTo(0.5, 1e-6));
  });

  test('the winning beat keeps from after the clock stops', () {
    final game = GameController(_level(['SE']));
    final f = _flow(game);
    final before = game.state;
    f.setIntent(IntentKind.move, Move.right);
    expect(f.frozen, isTrue);
    expect(f.from, same(before));
  });

  test('restart clears from', () {
    final game = GameController(_level(['S...E']));
    final f = _flow(game);
    for (var i = 0; i < 2; i++) {
      f.setIntent(IntentKind.move, Move.right);
      f.setIntent(IntentKind.none);
      f.advance(0.2);
    }
    expect(f.from, isNotNull);
    game.restart();
    expect(f.from, isNull);
  });

  group('after the game ends', () {
    /// One run of 25 waits: the battery runs out and the level is lost.
    (GameController, FlowController) lostByBattery() {
      final game = GameController(_level(['S.#E'], runLimit: 1));
      final f = _flow(game);
      f.press(IntentKind.wait);
      _hold(f, 25 * 0.2 + 0.5);
      f.release(IntentKind.wait);
      expect(game.state.status, GameStatus.lost);
      expect(f.clock.running, isFalse);
      return (game, f);
    }

    test('isBlocked is false once the game is not playing', () {
      final (game, _) = lostByBattery();
      for (final m in Move.values) {
        expect(game.isBlocked(m), isFalse);
      }
    });

    test('a held move after a loss fires no beats and throws nothing', () {
      final (game, f) = lostByBattery();
      final from = f.from;
      final state = game.state;
      var notified = 0;
      f.addListener(() => notified++);
      f.press(IntentKind.move, Move.right, InputSource.joystick);
      _hold(f, 1);
      f.press(IntentKind.move, Move.left, InputSource.keys);
      _hold(f, 1);
      expect(f.clock.running, isFalse);
      expect(f.frozen, isTrue);
      expect(f.bumps.value, 0);
      expect(f.from, same(from));
      expect(game.state, same(state));
      expect(notified, 0);
    });

    test('a held wait after a loss fires no beats and keeps from', () {
      final (game, f) = lostByBattery();
      final from = f.from;
      final state = game.state;
      var notified = 0;
      f.addListener(() => notified++);
      f.press(IntentKind.wait);
      _hold(f, 1);
      f.setIntent(IntentKind.wait);
      _hold(f, 1);
      expect(f.clock.running, isFalse);
      expect(f.from, same(from));
      expect(game.state, same(state));
      expect(notified, 0);
    });

    test('a held move after a win (during the win delay) is ignored', () {
      final game = GameController(_level(['SE#']));
      final f = _flow(game);
      f.setIntent(IntentKind.move, Move.right);
      expect(game.state.status, GameStatus.won);
      final from = f.from;
      f.press(IntentKind.move, Move.right, InputSource.joystick);
      _hold(f, 1);
      expect(f.clock.running, isFalse);
      expect(f.bumps.value, 0);
      expect(f.from, same(from));
    });
  });

  test('releaseAll bumps the release epoch; other releases do not', () {
    final game = GameController(_level(['S...E']));
    final f = _flow(game);
    final epoch = f.releaseEpoch.value;
    f.press(IntentKind.move, Move.right, InputSource.joystick);
    f.release(IntentKind.move, InputSource.joystick);
    f.releaseSource(InputSource.keys);
    expect(f.releaseEpoch.value, epoch);
    f.releaseAll();
    expect(f.releaseEpoch.value, epoch + 1);
  });

  test('a hit stops the clock and snaps like a run end', () {
    final game = GameController(_level(['S.2..E']));
    final f = _flow(game);
    f.setIntent(IntentKind.move, Move.right);
    _hold(f, 0.25); // beat 1 lands on (1, 0); beat 2 steps onto the laser
    expect(game.lastEvent, GameEvent.hit);
    expect(game.state.runIndex, 1);
    expect(f.clock.running, isFalse);
    expect(f.frozen, isTrue);
    expect(f.from, isNull);
    // The next run does not start walking on its own.
    _hold(f, 0.6);
    expect(game.state.tick, 0);
  });
}

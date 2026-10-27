import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/audio/game_sounds.dart';
import 'package:echo_app/game/game_controller.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter_test/flutter_test.dart';

// 1-02: "#S.aAE#" on one row; plate a at x=3, door A at x=4.
Level _level() => LevelLoader.fromMap({
  'id': '1-02',
  'name': 'Hold the Door',
  'runLimit': 1,
  'grid': ['#######', '#S.aAE#', '#######'],
});

GameState _step(GameState s, int times) {
  for (var i = 0; i < times; i++) {
    s = Rules.step(s, Move.right);
  }
  return s;
}

void main() {
  final start = GameState.initial(_level());

  test('moving along the floor plays only move', () {
    final after = _step(start, 1);
    expect(soundsFor(start, after, GameEvent.moved), [Sfx.move]);
  });

  test('stepping onto the plate plays move, plate and door', () {
    final before = _step(start, 1);
    final after = _step(start, 2);
    expect(soundsFor(before, after, GameEvent.moved), [
      Sfx.move,
      Sfx.plate,
      Sfx.door,
    ]);
  });

  test('a ghost stepping off the plate closes the door and plays door', () {
    final level = LevelLoader.fromMap({
      'id': '1-02',
      'name': 'Hold the Door',
      'runLimit': 2,
      'grid': ['#######', '#S.aAE#', '#######'],
    });
    var s = GameState.initial(level);
    for (final m in [Move.right, Move.right, Move.left]) {
      s = Rules.step(s, m);
    }
    s = Rules.endRun(s);
    final before = Rules.step(Rules.step(s, Move.wait), Move.wait);
    expect(before.openDoors, isNotEmpty, reason: 'ghost holds the plate');
    final after = Rules.step(before, Move.wait);
    expect(after.openDoors, isEmpty);
    expect(soundsFor(before, after, GameEvent.moved), [Sfx.move, Sfx.door]);
  });

  test('runEnded and lost play runEnd', () {
    expect(soundsFor(start, start, GameEvent.runEnded), [Sfx.runEnd]);
    expect(soundsFor(start, start, GameEvent.lost), [Sfx.runEnd]);
  });

  test('won plays move then win', () {
    expect(soundsFor(start, start, GameEvent.won), [Sfx.move, Sfx.win]);
  });

  test('none plays nothing', () {
    expect(soundsFor(start, start, GameEvent.none), isEmpty);
  });

  group('sparks', () {
    // Sparks at x=2 and x=4 on one row; the exit at x=5.
    final level = LevelLoader.fromMap({
      'id': '9-99',
      'name': 'Sparks',
      'runLimit': 1,
      'grid': ['#######', '#S*.*E#', '#######'],
    });
    final s0 = GameState.initial(level);

    test('collecting a spark plays move then spark, once', () {
      final s1 = Rules.step(s0, Move.right);
      expect(s1.collected, isNotEmpty);
      expect(soundsFor(s0, s1, GameEvent.moved), [Sfx.move, Sfx.spark]);
      // Standing on it again collects nothing new.
      final s2 = Rules.step(s1, Move.wait);
      expect(soundsFor(s1, s2, GameEvent.moved), [Sfx.move]);
    });

    test('a winning step that collects plays the spark too', () {
      final before = Rules.step(Rules.step(s0, Move.right), Move.right);
      final at = Rules.step(before, Move.right);
      expect(soundsFor(before, at, GameEvent.moved), [Sfx.move, Sfx.spark]);
      final won = Rules.step(at, Move.right);
      expect(won.status, GameStatus.won);
      expect(soundsFor(at, won, GameEvent.won), [Sfx.move, Sfx.win]);
    });

    test('a spark grabbed on the run-ending beat still chimes', () {
      final s1 = Rules.step(s0, Move.right);
      expect(soundsFor(s0, s1, GameEvent.runEnded), [Sfx.runEnd, Sfx.spark]);
      expect(soundsFor(s0, s1, GameEvent.lost), [Sfx.runEnd, Sfx.spark]);
      expect(soundsFor(s1, s1, GameEvent.runEnded), [Sfx.runEnd]);
    });

    test('a rewind or restart that drops a spark is silent', () {
      final s1 = Rules.step(s0, Move.right);
      expect(soundsFor(s1, s0, GameEvent.none), isEmpty);
      expect(soundsFor(s1, s0, GameEvent.restarted), isEmpty);
    });
  });

  test('restarted plays nothing', () {
    expect(soundsFor(start, start, GameEvent.restarted), isEmpty);
  });

  group('dangers', () {
    Level lvl(List<String> grid, {int runLimit = 2}) => LevelLoader.fromMap({
      'id': 't',
      'name': 't',
      'runLimit': runLimit,
      'grid': grid,
    });
    GameState play(GameState s, List<Move> moves) {
      for (final m in moves) {
        s = Rules.step(s, m);
      }
      return s;
    }

    const r = Move.right, w = Move.wait;

    test('a laser hit plays zap; a forced rewind plays no run-end chime', () {
      final s0 = GameState.initial(lvl(['S1.E']));
      final s1 = Rules.step(s0, r);
      expect(s1.runIndex, 1);
      expect(soundsFor(s0, s1, GameEvent.hit), [Sfx.zap]);
    });

    test('a hit on the last run zaps instead of the run-end chime', () {
      final s0 = GameState.initial(lvl(['S1.E'], runLimit: 1));
      final s1 = Rules.step(s0, r);
      expect(s1.status, GameStatus.lost);
      expect(soundsFor(s0, s1, GameEvent.lost), [Sfx.zap]);
    });

    test('a Shade catch plays shade, not zap', () {
      final s0 = GameState.initial(lvl(['Sx.E']));
      final s1 = Rules.step(s0, w);
      expect(soundsFor(s0, s1, GameEvent.hit), [Sfx.shade]);
      final last = GameState.initial(lvl(['Sx.E'], runLimit: 1));
      expect(soundsFor(last, Rules.step(last, w), GameEvent.lost), [Sfx.shade]);
    });

    test('a spark grabbed on the hit beat still chimes', () {
      final s0 = GameState.initial(lvl(['S*x.E']));
      final s1 = Rules.step(s0, r);
      expect(s1.lastHits.pip, isTrue);
      expect(soundsFor(s0, s1, GameEvent.hit), [Sfx.shade, Sfx.spark]);
    });

    test('a collapse plays crumble', () {
      final s0 = GameState.initial(lvl(['S~.E']));
      final s1 = Rules.step(s0, r);
      final s2 = Rules.step(s1, r);
      expect(s2.holes, isNotEmpty);
      expect(soundsFor(s1, s2, GameEvent.moved), [Sfx.move, Sfx.crumble]);
      // Rewinding over it is silent.
      expect(soundsFor(s2, s1, GameEvent.none), isEmpty);
    });

    test('an echo falling plays the soft echo zap', () {
      // Run 0 crosses the crack at tick 3; in run 1 Pip breaks it first.
      var s = play(GameState.initial(lvl(['S~..E'])), [w, w, r, r]);
      s = Rules.endRun(s);
      s = play(s, [r, r]);
      expect(s.holes, {const Position(1, 0)});
      final before = s;
      final after = Rules.step(s, w);
      expect(after.lastHits.ghosts, [0]);
      expect(soundsFor(before, after, GameEvent.moved), [
        Sfx.move,
        Sfx.echoZap,
      ]);
    });

    test('an echo caught by a Shade plays shade', () {
      // Run 0 is a 0-move echo waiting on the start. In run 1 Pip steps up,
      // so the echo is the nearer light and the Shade catches it.
      final level = lvl(['#.#..', 'xS..E']);
      final before = Rules.endRun(GameState.initial(level));
      expect(before.runIndex, 1);
      final s = Rules.step(before, Move.up);
      expect(s.lastHits.ghosts, [0]);
      expect(soundsFor(before, s, GameEvent.moved), [Sfx.move, Sfx.shade]);
    });

    test(
      'a laser warning plays laserWarn once on the beat before it fires',
      () {
        final s0 = GameState.initial(lvl(['S.2.E']));
        final s1 = Rules.step(s0, w); // tick 1: beat 2 warns
        expect(soundsFor(s0, s1, GameEvent.moved), [Sfx.move, Sfx.laserWarn]);
        final s2 = Rules.step(s1, w); // tick 2: it fires, no warning
        expect(soundsFor(s1, s2, GameEvent.moved), [Sfx.move]);
        // Never on a rewind, a run end or a restart.
        expect(soundsFor(s0, s1, GameEvent.none), isEmpty);
        expect(soundsFor(s0, s1, GameEvent.runEnded), [Sfx.runEnd]);
      },
    );
  });
}

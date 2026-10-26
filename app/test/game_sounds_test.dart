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
}

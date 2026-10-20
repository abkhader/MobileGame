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
}

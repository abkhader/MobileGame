import 'package:echo_app/game/game_clock.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<(IntentKind, Move?)> beats;
  late Duration length;
  late GameClock clock;

  setUp(() {
    beats = [];
    length = MoveSpeed.normal.beat;
    clock = GameClock(
      beatLength: () => length,
      onBeat: (k, d) => beats.add((k, d)),
    );
  });

  test('move fires immediately then every 200 ms at normal', () {
    clock.setIntent(IntentKind.move, Move.right);
    expect(beats.length, 1);
    expect(beats.first, (IntentKind.move, Move.right));
    clock.advance(0.199);
    expect(beats.length, 1);
    clock.advance(0.002);
    expect(beats.length, 2);
    expect(clock.running, isTrue);
  });

  test('slow and fast use 300 and 140 ms', () {
    expect(MoveSpeed.slow.beat, const Duration(milliseconds: 300));
    expect(MoveSpeed.normal.beat, const Duration(milliseconds: 200));
    expect(MoveSpeed.fast.beat, const Duration(milliseconds: 140));
    length = MoveSpeed.slow.beat;
    clock.setIntent(IntentKind.move, Move.up);
    clock.advance(0.299);
    expect(beats.length, 1);
    clock.advance(0.002);
    expect(beats.length, 2);
    clock.stop();
    beats.clear();
    length = MoveSpeed.fast.beat;
    clock.setIntent(IntentKind.move, Move.up);
    clock.advance(0.139);
    expect(beats.length, 1);
    clock.advance(0.002);
    expect(beats.length, 2);
  });

  test('release finishes the current beat without firing another', () {
    clock.setIntent(IntentKind.move, Move.left);
    clock.advance(0.1);
    expect(clock.beatProgress, closeTo(0.5, 1e-6));
    clock.setIntent(IntentKind.none);
    expect(clock.running, isTrue);
    clock.advance(1.0);
    expect(beats.length, 1);
    expect(clock.beatProgress, 1);
    expect(clock.running, isFalse);
  });

  test('direction change applies on the next beat', () {
    clock.setIntent(IntentKind.move, Move.right);
    clock.advance(0.1);
    clock.setIntent(IntentKind.move, Move.down);
    expect(beats.length, 1);
    clock.advance(0.11);
    expect(beats.length, 2);
    expect(beats.last, (IntentKind.move, Move.down));
  });

  test('wait fires wait beats', () {
    clock.setIntent(IntentKind.wait);
    clock.advance(0.2);
    expect(beats, [(IntentKind.wait, null), (IntentKind.wait, null)]);
  });

  test('rewind fires at half length', () {
    clock.setIntent(IntentKind.rewind);
    expect(beats.length, 1);
    clock.advance(0.099);
    expect(beats.length, 1);
    clock.advance(0.002);
    expect(beats.length, 2);
  });

  test('stop idles immediately', () {
    clock.setIntent(IntentKind.move, Move.right);
    clock.advance(0.1);
    clock.stop();
    expect(clock.running, isFalse);
    expect(clock.beatProgress, 1);
    clock.advance(5);
    expect(beats.length, 1);
  });

  test('a long stall fires at most 3 beats in one advance', () {
    clock.setIntent(IntentKind.move, Move.right);
    clock.advance(10);
    expect(beats.length, 1 + GameClock.maxBeatsPerAdvance);
    expect(clock.running, isTrue);
    clock.advance(0.1);
    expect(beats.length, 1 + GameClock.maxBeatsPerAdvance);
  });

  test('one advance spanning two beats fires two', () {
    clock.setIntent(IntentKind.move, Move.right);
    clock.advance(0.41);
    expect(beats.length, 3);
  });

  test('intent set while idle after release fires again', () {
    clock.setIntent(IntentKind.move, Move.right);
    clock.setIntent(IntentKind.none);
    clock.advance(0.2);
    expect(clock.running, isFalse);
    clock.setIntent(IntentKind.move, Move.up);
    expect(beats.length, 2);
  });
}

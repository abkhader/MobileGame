import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// One beat at Normal speed.
const beat = Duration(milliseconds: 200);

final board = find.byKey(const Key('board'));

/// Lets a running beat finish so the clock goes idle.
Future<void> settle(WidgetTester t) async {
  await t.pump(beat);
  await t.pump(beat);
}

/// A quick key tap: exactly one beat, then idle.
Future<void> tapKey(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyDownEvent(key);
  await t.sendKeyUpEvent(key);
  await settle(t);
}

/// Holds [key] for [duration] in 50 ms frames, then lets go and settles.
Future<void> holdKey(
  WidgetTester t,
  LogicalKeyboardKey key,
  Duration duration,
) async {
  await t.sendKeyDownEvent(key);
  await pumpFrames(t, duration);
  await t.sendKeyUpEvent(key);
  await settle(t);
}

/// Pumps [duration] as 50 ms frames, like a steady render loop.
Future<void> pumpFrames(WidgetTester t, Duration duration) async {
  const frame = Duration(milliseconds: 50);
  for (var d = Duration.zero; d < duration; d += frame) {
    await t.pump(frame);
  }
}

/// Puts a thumb down at [heightFraction] of the board and drags by [delta].
Future<TestGesture> dragJoystick(
  WidgetTester t,
  Offset delta, {
  double heightFraction = 0.8,
}) async {
  final r = t.getRect(board);
  final g = await t.startGesture(
    Offset(r.center.dx, r.top + r.height * heightFraction),
  );
  await g.moveBy(delta);
  return g;
}

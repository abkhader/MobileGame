import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_app/game/floating_joystick.dart';
import 'package:echo_app/game/flow_controller.dart';
import 'package:echo_app/game/game_clock.dart';
import 'package:echo_app/game/game_controller.dart';
import 'package:echo_app/screens/game_screen.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';
import 'support/flow_input.dart';

Future<void> _pumpGame(WidgetTester t, String levelId) async {
  SharedPreferences.setMockInitialValues({});
  final progress = (await t.runAsync(ProgressRepository.open))!;
  final services = AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
    ads: FakeAdService(),
    audio: const SilentAudioService(),
    story: StoryRepository(PlatformAssetBundle()),
  );
  await t.pumpWidget(
    MaterialApp(
      home: GameScreen(services: services, levelId: levelId),
    ),
  );
  await t.pump(beat);
  await t.pump(beat);
}

GameController _game(WidgetTester t) =>
    (t.state(find.byType(GameScreen)) as dynamic).controllerForTesting
        as GameController;

dynamic _flow(WidgetTester t) =>
    (t.state(find.byType(GameScreen)) as dynamic).flowForTesting;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('joystickDirection: dead zone, dominant axis, ties horizontal', () {
    expect(joystickDirection(const Offset(11, 0)), isNull);
    expect(joystickDirection(const Offset(13, 0)), Move.right);
    expect(joystickDirection(const Offset(-5, -20)), Move.up);
    expect(joystickDirection(const Offset(10, 10)), Move.right);
    expect(joystickDirection(const Offset(-10, 10)), Move.left);
    expect(joystickDirection(const Offset(0, 30)), Move.down);
  });

  testWidgets('the joystick spawns anywhere on the board area', (t) async {
    for (final fraction in [0.1, 0.5, 0.9]) {
      await _pumpGame(t, '1-01');
      final start = _game(t).state.player;
      final stick = await dragJoystick(
        t,
        const Offset(60, 0),
        heightFraction: fraction,
      );
      await t.pump(beat);
      expect(
        _game(t).state.player.x,
        greaterThan(start.x),
        reason: 'thumb at $fraction of the board height',
      );
      await stick.up();
      await settle(t);
    }
  });

  testWidgets('the joystick re-anchors: a dragged-out thumb turns quickly', (
    t,
  ) async {
    await _pumpGame(t, '2-03');
    final r = t.getRect(board);
    final g = await t.startGesture(
      Offset(r.center.dx - 50, r.top + r.height * 0.5),
    );
    for (var i = 0; i < 25; i++) {
      await g.moveBy(const Offset(4, 0));
    }
    final flow = _flow(t) as FlowController;
    expect(flow.held, [(InputSource.joystick, IntentKind.move, Move.right)]);
    // The steering centre trails 20 px behind the thumb, so at most 30 px
    // straight up turns it. Without re-anchoring the thumb, 100 px out,
    // would need more than 100 px.
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, -3));
    }
    expect(flow.held, [(InputSource.joystick, IntentKind.move, Move.up)]);
    await g.up();
    await settle(t);
  });

  testWidgets('a thumb resting in the dead zone wakes and moves nothing', (
    t,
  ) async {
    await _pumpGame(t, '2-03');
    final r = t.getRect(board);
    final g = await t.startGesture(r.center);
    // The touch itself wakes the board once; let it settle again.
    await pumpFrames(t, const Duration(milliseconds: 300));
    final echo = (t.state(find.byType(GameScreen)) as dynamic).boardForTesting;
    expect(echo.paused as bool, isTrue);
    for (final d in const [
      Offset(3, 0),
      Offset(0, 4),
      Offset(-5, -2),
      Offset(2, 3),
    ]) {
      await g.moveBy(d);
      expect(echo.paused as bool, isTrue);
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(_game(t).state.tick, 0);
    expect(_flow(t).held as List, isEmpty);
    expect(_flow(t).clock.running as bool, isFalse);
    await g.up();
    await settle(t);
  });

  testWidgets('after a lifecycle release the joystick takes a new thumb', (
    t,
  ) async {
    await _pumpGame(t, '2-03');
    final first = await dragJoystick(t, const Offset(60, 0));
    await t.pump(beat);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(beat);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(t);
    final x = _game(t).state.player.x;
    final r = t.getRect(board);
    final second = await t.startGesture(
      Offset(r.center.dx, r.top + r.height * 0.3),
    );
    await second.moveBy(const Offset(-60, 0));
    await t.pump(beat);
    expect(_game(t).state.player.x, lessThan(x));
    // The stale first thumb lifting does not drop the new one.
    await first.up();
    final flow = _flow(t) as FlowController;
    expect(flow.held, [(InputSource.joystick, IntentKind.move, Move.left)]);
    await second.up();
    await settle(t);
  });

  testWidgets('after a lifecycle release a hold button takes a new press', (
    t,
  ) async {
    await _pumpGame(t, '2-03');
    final waitAt = t.getCenter(find.bySemanticsLabel('Wait'));
    final first = await t.startGesture(waitAt);
    await t.pump(beat);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(beat);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(t);
    final flow = _flow(t) as FlowController;
    expect(flow.held, isEmpty);
    final second = await t.startGesture(waitAt);
    await t.pump(beat);
    expect(flow.held, [(InputSource.button, IntentKind.wait, null)]);
    await first.up();
    expect(flow.held, [(InputSource.button, IntentKind.wait, null)]);
    await second.up();
    expect(flow.held, isEmpty);
    await settle(t);
  });

  testWidgets('two thumbs: latest press wins, release reveals previous', (
    t,
  ) async {
    await _pumpGame(t, '2-03');
    final stick = await dragJoystick(t, const Offset(60, 0));
    await t.pump(beat);
    final x = _game(t).state.player.x;
    expect(x, greaterThan(4));

    final wait = await t.startGesture(
      t.getCenter(find.bySemanticsLabel('Wait')),
    );
    final tick = _game(t).state.tick;
    await pumpFrames(t, const Duration(milliseconds: 400));
    expect(_game(t).state.tick, greaterThan(tick));
    expect(_game(t).state.player.x, x);

    await wait.up();
    await pumpFrames(t, const Duration(milliseconds: 250));
    expect(_game(t).state.player.x, greaterThan(x));
    await stick.up();
    await settle(t);
  });

  testWidgets('keys: arrows hold to move, Space waits, Z rewinds', (t) async {
    await _pumpGame(t, '2-03');
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await t.pump(beat);
    await t.pump(beat);
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    final ticks = _game(t).state.tick;
    expect(ticks, inInclusiveRange(2, 3));
    await settle(t);
    expect(_game(t).state.tick, ticks);

    final p = _game(t).state.player;
    await tapKey(t, LogicalKeyboardKey.space);
    expect(_game(t).state.tick, ticks + 1);
    expect(_game(t).state.player, p);

    await tapKey(t, LogicalKeyboardKey.keyZ);
    expect(_game(t).state.tick, ticks);
    await tapKey(t, LogicalKeyboardKey.backspace);
    expect(_game(t).state.tick, ticks - 1);
  });

  testWidgets('keys: WASD move, E makes a new echo, R restarts', (t) async {
    await _pumpGame(t, '2-03');
    final start = _game(t).state.player;
    await tapKey(t, LogicalKeyboardKey.keyA);
    expect(_game(t).state.player, Position(start.x - 1, start.y));
    await tapKey(t, LogicalKeyboardKey.keyD);
    expect(_game(t).state.player, start);

    await tapKey(t, LogicalKeyboardKey.keyE);
    expect(_game(t).state.runIndex, 1);
    expect(find.text('New echo · 1 left'), findsOneWidget);

    await tapKey(t, LogicalKeyboardKey.keyW);
    expect(_game(t).state.tick, 1);
    await tapKey(t, LogicalKeyboardKey.keyR);
    expect(_game(t).state.runIndex, 0);
    expect(_game(t).state.tick, 0);
  });

  testWidgets('lifecycle pause stops the clock and clears intents', (t) async {
    await _pumpGame(t, '2-03');
    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await t.pump(beat);
    expect(_flow(t).clock.running as bool, isTrue);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(beat);
    expect(_flow(t).clock.running as bool, isFalse);
    expect(_flow(t).held as List, isEmpty);
    final tick = _game(t).state.tick;

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpFrames(t, const Duration(milliseconds: 600));
    expect(_game(t).state.tick, tick);
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
    await settle(t);
  });

  testWidgets('labels: New echo counts down, then Give up', (t) async {
    await _pumpGame(t, '2-03');
    expect(find.text('New echo · 2 left'), findsOneWidget);
    expect(find.byIcon(Icons.people_alt_outlined), findsOneWidget);
    expect(find.bySemanticsLabel('Rewind time'), findsOneWidget);
    expect(find.bySemanticsLabel('Wait'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
    for (var run = 0; run < 2; run++) {
      await tapKey(t, LogicalKeyboardKey.space);
      await t.tap(find.textContaining('New echo'));
      await t.pump(beat);
    }
    expect(find.text('Give up'), findsOneWidget);
    expect(find.byIcon(Icons.flag), findsOneWidget);
  });

  testWidgets('no swipe-to-move remains: a tap on the board moves nothing', (
    t,
  ) async {
    // The joystick covers the whole board, so a fling is a short joystick
    // hold; what must not exist is a tap or swipe handler of its own.
    await _pumpGame(t, '1-01');
    final r = t.getRect(board);
    for (final fraction in [0.1, 0.5, 0.9]) {
      await t.tapAt(Offset(r.center.dx, r.top + r.height * fraction));
      await settle(t);
    }
    expect(_game(t).state.tick, 0);
  });

  testWidgets('a cancelled joystick pointer releases the move', (t) async {
    await _pumpGame(t, '2-03');
    final stick = await dragJoystick(t, const Offset(60, 0));
    await t.pump(beat);
    expect(_game(t).state.tick, greaterThan(0));
    await stick.cancel();
    await settle(t);
    expect(_flow(t).held as List, isEmpty);
    expect(_flow(t).clock.running as bool, isFalse);
    final tick = _game(t).state.tick;
    await pumpFrames(t, const Duration(milliseconds: 600));
    expect(_game(t).state.tick, tick);
  });

  testWidgets('a cancelled hold-button pointer releases the wait', (t) async {
    await _pumpGame(t, '2-03');
    final wait = await t.startGesture(
      t.getCenter(find.bySemanticsLabel('Wait')),
    );
    await t.pump(beat);
    expect(_game(t).state.tick, greaterThan(0));
    await wait.cancel();
    await settle(t);
    expect(_flow(t).held as List, isEmpty);
    final tick = _game(t).state.tick;
    await pumpFrames(t, const Duration(milliseconds: 600));
    expect(_game(t).state.tick, tick);
  });

  testWidgets('releasing an arrow key keeps the joystick direction', (t) async {
    await _pumpGame(t, '2-03');
    final stick = await dragJoystick(t, const Offset(60, 0));
    await t.pump(beat);
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    final flow = _flow(t) as FlowController;
    expect(flow.held, [(InputSource.joystick, IntentKind.move, Move.right)]);
    final x = _game(t).state.player.x;
    await pumpFrames(t, const Duration(milliseconds: 450));
    expect(_game(t).state.player.x, greaterThan(x));
    await stick.up();
    await settle(t);
  });

  testWidgets('losing key focus releases key-held intents', (t) async {
    await _pumpGame(t, '2-03');
    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await t.pump(beat);
    expect(_flow(t).held as List, isNotEmpty);
    FocusManager.instance.primaryFocus!.unfocus();
    await t.pump(beat);
    expect(_flow(t).held as List, isEmpty);
    await settle(t);
    final tick = _game(t).state.tick;
    await pumpFrames(t, const Duration(milliseconds: 600));
    expect(_game(t).state.tick, tick);
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
  });

  testWidgets('Ctrl, Cmd or Alt with a key is left to the browser', (t) async {
    await _pumpGame(t, '2-03');
    await tapKey(t, LogicalKeyboardKey.space);
    expect(_game(t).state.tick, 1);
    for (final mod in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.altLeft,
    ]) {
      await t.sendKeyDownEvent(mod);
      for (final key in [
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyE,
        LogicalKeyboardKey.arrowRight,
      ]) {
        expect(await t.sendKeyDownEvent(key), isFalse);
        await t.sendKeyUpEvent(key);
      }
      await t.sendKeyUpEvent(mod);
      await settle(t);
    }
    expect(_game(t).state.tick, 1);
    expect(_game(t).state.runIndex, 0);
  });

  testWidgets('keys still work after tapping a button', (t) async {
    await _pumpGame(t, '2-03');
    for (final label in ['Restart', 'Hint']) {
      await t.tap(find.text(label));
      await t.pump(beat);
      final x = _game(t).state.player.x;
      await tapKey(t, LogicalKeyboardKey.arrowRight);
      expect(_game(t).state.player.x, x + 1, reason: 'after $label');
    }
  });

  testWidgets('hold buttons are at least 48 x 48', (t) async {
    await _pumpGame(t, '2-03');
    for (final label in ['Wait', 'Rewind time']) {
      final size = t.getSize(find.bySemanticsLabel(label));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('the joystick ignores a secondary mouse button', (t) async {
    await _pumpGame(t, '2-03');
    final r = t.getRect(board);
    final mouse = await t.startGesture(
      Offset(r.center.dx, r.top + r.height * 0.8),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.moveBy(const Offset(60, 0));
    await t.pump(beat);
    await t.pump(beat);
    expect(_game(t).state.tick, 0);
    await mouse.up();
  });
}

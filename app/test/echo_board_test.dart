import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_app/game/echo_board.dart';
import 'package:echo_app/game/game_controller.dart';
import 'package:echo_app/screens/game_screen.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';
import 'support/flow_input.dart';

/// Serves the real assets, except level 1-01 becomes a two-move corridor.
class _ShortLevelBundle extends PlatformAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == 'assets/levels/1-01.json') {
      return '{"id": "1-01", "name": "Short", "runLimit": 1, '
          '"grid": ["#####", "#S.E#", "#####"], "bestScore": 2}';
    }
    return super.loadString(key, cache: cache);
  }
}

Future<void> _pumpGame(
  WidgetTester t,
  String levelId, {
  AssetBundle? bundle,
  bool reduceMotion = false,
  void Function(GameController c)? onWon,
}) async {
  SharedPreferences.setMockInitialValues({});
  final progress = (await t.runAsync(ProgressRepository.open))!;
  final services = AppServices(
    levels: LevelRepository(bundle ?? PlatformAssetBundle()),
    progress: progress,
    ads: FakeAdService(),
    audio: const SilentAudioService(),
    story: StoryRepository(PlatformAssetBundle()),
  );
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: GameScreen(services: services, levelId: levelId, onWon: onWon),
      ),
    ),
  );
  await t.pump(beat);
  await t.pump(beat);
}

EchoBoard _board(WidgetTester t) =>
    (t.state(find.byType(GameScreen)) as dynamic).boardForTesting as EchoBoard;

GameController _game(WidgetTester t) =>
    (t.state(find.byType(GameScreen)) as dynamic).controllerForTesting
        as GameController;

/// Presses [key] on a paused board and runs exactly [into] of its beat:
/// the first frame after waking has dt = 0.
Future<void> _pressAndRun(
  WidgetTester t,
  LogicalKeyboardKey key,
  Duration into,
) async {
  expect(_board(t).paused, isTrue, reason: 'start from a settled board');
  await t.sendKeyDownEvent(key);
  await t.pump(Duration.zero);
  await t.pump(into);
}

Future<void> _settleFully(WidgetTester t) async {
  await settle(t);
  await pumpFrames(t, const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the static layer is built once per size, not per beat', (
    t,
  ) async {
    await _pumpGame(t, '1-03');
    expect(_board(t).staticBuilds, 1);
    for (var i = 0; i < 3; i++) {
      await tapKey(t, LogicalKeyboardKey.arrowRight);
    }
    await _settleFully(t);
    expect(_board(t).staticBuilds, 1);

    addTearDown(t.view.reset);
    t.view.physicalSize = const Size(1600, 2400);
    await t.pump(beat);
    await t.pump(beat);
    expect(_board(t).staticBuilds, 2);
  });

  testWidgets('mid-beat, Pip and echoes are half way between tiles', (t) async {
    await _pumpGame(t, '1-03');
    await tapKey(t, LogicalKeyboardKey.arrowRight);
    await t.tap(find.text('New echo · 1 left'));
    await _settleFully(t);

    final board = _board(t);
    final start = board.pipTileForTesting;
    final echo = board.ghostTilesForTesting.single;
    await _pressAndRun(
      t,
      LogicalKeyboardKey.arrowRight,
      const Duration(milliseconds: 100),
    );
    expect(board.pipTileForTesting.dx, closeTo(start.dx + 0.5, 1e-6));
    expect(board.pipTileForTesting.dy, start.dy);
    // The echo replays its first move: right.
    expect(board.ghostTilesForTesting.single.dx, closeTo(echo.dx + 0.5, 1e-6));
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await _settleFully(t);
    expect(board.pipTileForTesting, start + const Offset(1, 0));
  });

  testWidgets('a push nudges Pip without leaving its tile', (t) async {
    await _pumpGame(t, '1-03');
    final board = _board(t);
    final start = board.pipTileForTesting;
    await _pressAndRun(
      t,
      LogicalKeyboardKey.arrowUp,
      const Duration(milliseconds: 60),
    );
    expect(_game(t).state.tick, 1);
    expect(board.pipTileForTesting, start);
    expect(board.nudgeOffsetForTesting.dy, lessThan(0));
    expect(board.nudgeOffsetForTesting.dx, 0);
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await _settleFully(t);
    expect(board.nudgeOffsetForTesting, Offset.zero);
  });

  testWidgets('rewind glides Pip back', (t) async {
    await _pumpGame(t, '1-03');
    await tapKey(t, LogicalKeyboardKey.arrowRight);
    await tapKey(t, LogicalKeyboardKey.arrowRight);
    await _settleFully(t);
    final board = _board(t);
    final at = board.pipTileForTesting;
    // Rewind beats are half length: 50 ms is half way back.
    await _pressAndRun(
      t,
      LogicalKeyboardKey.keyZ,
      const Duration(milliseconds: 50),
    );
    expect(board.pipTileForTesting.dx, closeTo(at.dx - 0.5, 1e-6));
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await _settleFully(t);
  });

  testWidgets('a run change snaps Pip back to the start', (t) async {
    await _pumpGame(t, '1-03');
    final board = _board(t);
    final start = board.pipTileForTesting;
    await tapKey(t, LogicalKeyboardKey.arrowRight);
    await _settleFully(t);
    await t.tap(find.text('New echo · 1 left'));
    await t.pump(Duration.zero);
    await t.pump(const Duration(milliseconds: 16));
    // Pip and the new echo both jump back to the start, no glide.
    expect(board.pipTileForTesting, start);
    expect(board.ghostTilesForTesting.single, start);
    await _settleFully(t);
  });

  testWidgets('the winning beat glides into the exit instead of snapping', (
    t,
  ) async {
    final won = <GameController>[];
    await _pumpGame(t, '1-01', onWon: won.add);
    for (var i = 0; i < 3; i++) {
      await tapKey(t, LogicalKeyboardKey.arrowRight);
    }
    await _settleFully(t);
    final board = _board(t);
    final before = board.pipTileForTesting;
    await _pressAndRun(
      t,
      LogicalKeyboardKey.arrowRight,
      const Duration(milliseconds: 100),
    );
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(_game(t).lastEvent, GameEvent.won);
    expect(board.pipTileForTesting.dx, closeTo(before.dx + 0.5, 1e-6));
    expect(board.paused, isFalse);
    await t.pump(const Duration(milliseconds: 100));
    expect(board.pipTileForTesting, before + const Offset(1, 0));
    await t.pump(const Duration(milliseconds: 500));
    expect(won, hasLength(1));
  });

  testWidgets('echo flicker is off with reduced effects', (t) async {
    await _pumpGame(t, '1-03', reduceMotion: true);
    await tapKey(t, LogicalKeyboardKey.arrowRight);
    await t.tap(find.text('New echo · 1 left'));
    await t.pump(beat);
    final board = _board(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 37));
      expect(board.ghostOpacityForTesting(0), 0.55);
    }
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
    await _settleFully(t);
  });

  testWidgets('restart snaps doors shut instead of sliding', (t) async {
    await _pumpGame(t, '1-03');
    const door = Position(4, 1);
    await tapKey(t, LogicalKeyboardKey.arrowRight); // onto the plate
    await _settleFully(t);
    final board = _board(t);
    expect(board.doorOpenForTesting(door), 1);
    await t.tap(find.text('Restart'));
    await t.pump(Duration.zero);
    expect(board.doorOpenForTesting(door), 0);
    expect(board.winFlashActiveForTesting, isFalse);
    await _settleFully(t);
  });

  testWidgets('a rewind step slides the door instead of snapping', (t) async {
    await _pumpGame(t, '1-03');
    const door = Position(4, 1);
    await tapKey(t, LogicalKeyboardKey.arrowRight);
    await _settleFully(t);
    final board = _board(t);
    await _pressAndRun(
      t,
      LogicalKeyboardKey.keyZ,
      const Duration(milliseconds: 50),
    );
    expect(board.doorOpenForTesting(door), inExclusiveRange(0, 1));
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await _settleFully(t);
    expect(board.doorOpenForTesting(door), 0);
  });

  testWidgets('restart after two moves snaps doors and resets Pip', (t) async {
    await _pumpGame(t, '1-03');
    const door = Position(4, 1);
    final board = _board(t);
    final start = board.pipTileForTesting;
    await tapKey(t, LogicalKeyboardKey.arrowRight); // onto the plate
    await tapKey(t, LogicalKeyboardKey.space); // stay: the door stays open
    await _settleFully(t);
    expect(_game(t).state.tick, 2);
    expect(board.doorOpenForTesting(door), 1);
    await t.tap(find.text('Restart'));
    await t.pump(Duration.zero);
    expect(_game(t).lastEvent, GameEvent.restarted);
    expect(board.doorOpenForTesting(door), 0);
    expect(board.pipTileForTesting, start);
    await _settleFully(t);
  });

  testWidgets('restart mid-glide on the second move drops Pip\'s pose', (
    t,
  ) async {
    await _pumpGame(t, '1-03');
    final board = _board(t);
    await tapKey(t, LogicalKeyboardKey.arrowUp); // a push: one beat
    await _settleFully(t);
    await _pressAndRun(
      t,
      LogicalKeyboardKey.arrowRight,
      const Duration(milliseconds: 100),
    );
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(_game(t).state.tick, 2);
    expect(board.pipLeanForTesting, greaterThan(0));
    await t.tap(find.text('Restart'));
    expect(board.pipLeanForTesting, 0);
    expect(board.pipStretchForTesting, 0);
    await _settleFully(t);
  });

  testWidgets('restart after a two-move win stops the flash', (t) async {
    final won = <GameController>[];
    await _pumpGame(t, '1-01', bundle: _ShortLevelBundle(), onWon: won.add);
    final board = _board(t);
    final start = board.pipTileForTesting;
    await tapKey(t, LogicalKeyboardKey.arrowRight);
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await t.pump(Duration.zero);
    expect(_game(t).lastEvent, GameEvent.won);
    expect(_game(t).state.tick, 2);
    expect(board.winFlashActiveForTesting, isTrue);
    await t.tap(find.text('Restart'));
    await t.pump(Duration.zero);
    expect(board.winFlashActiveForTesting, isFalse);
    expect(board.pipTileForTesting, start);
    await _settleFully(t);
    await t.pump(const Duration(milliseconds: 500));
    expect(won, isEmpty);
  });

  testWidgets('the exit glow is baked once per size, not blurred per frame', (
    t,
  ) async {
    await _pumpGame(t, '1-03');
    expect(_board(t).exitGlowBakesForTesting, 1);
    // Time flows for a while: the exit pulses.
    await holdKey(
      t,
      LogicalKeyboardKey.space,
      const Duration(milliseconds: 1500),
    );
    await _settleFully(t);
    expect(_board(t).exitGlowBakesForTesting, 1);

    addTearDown(t.view.reset);
    t.view.physicalSize = const Size(1600, 2400);
    await t.pump(beat);
    await t.pump(beat);
    expect(_board(t).exitGlowBakesForTesting, 2);
  });

  testWidgets('the battery ring is big enough to read on a phone', (t) async {
    await _pumpGame(t, '1-03');
    final (radius, stroke) = _board(t).batteryRingForTesting;
    expect(radius, closeTo(0.15, 1e-9), reason: 'radius in cells');
    expect(stroke, closeTo(0.058, 1e-3), reason: 'stroke in cells');
  });
}

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

// 1-03: "#Sa*AE#" / "#**####". Sparks in reading order: (3,1), (1,2), (2,2).
const _sparkBelowStart = 1;

final _fly = find.byKey(const Key('spark-fly'));

Future<AppServices> _pumpGame(
  WidgetTester t,
  String levelId, {
  bool reduceMotion = false,
  bool defaultWin = false,
}) async {
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
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: GameScreen(
          services: services,
          levelId: levelId,
          onWon: defaultWin ? null : (_) {},
        ),
      ),
    ),
  );
  await t.pump(beat);
  await t.pump(beat);
  return services;
}

EchoBoard _board(WidgetTester t) =>
    (t.state(find.byType(GameScreen)) as dynamic).boardForTesting as EchoBoard;

GameController _game(WidgetTester t) =>
    (t.state(find.byType(GameScreen)) as dynamic).controllerForTesting
        as GameController;

Future<void> _settleFully(WidgetTester t) async {
  await settle(t);
  await pumpFrames(t, const Duration(milliseconds: 600));
}

Finder _sparks(int n) => find.bySemanticsLabel('Sparks, $n of 3');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the HUD counts sparks; rewind and restart take them back', (
    t,
  ) async {
    await _pumpGame(t, '1-03');
    expect(_sparks(0), findsOneWidget);
    expect(find.text('✦ 0 / 3'), findsOneWidget);
    await tapKey(t, LogicalKeyboardKey.arrowDown);
    expect(_game(t).state.collected, {const Position(1, 2)});
    expect(_sparks(1), findsOneWidget);
    expect(find.text('✦ 1 / 3'), findsOneWidget);
    await tapKey(t, LogicalKeyboardKey.keyZ);
    expect(_game(t).state.collected, isEmpty);
    expect(_sparks(0), findsOneWidget);
    await _settleFully(t);

    await tapKey(t, LogicalKeyboardKey.arrowDown);
    expect(_sparks(1), findsOneWidget);
    await t.tap(find.text('Restart'));
    await t.pump(beat);
    expect(_sparks(0), findsOneWidget);
    await _settleFully(t);
  });

  testWidgets('a collected spark keeps counting in the next run', (t) async {
    await _pumpGame(t, '1-03');
    await tapKey(t, LogicalKeyboardKey.arrowDown);
    await t.tap(find.text('New echo · 1 left'));
    await t.pump(beat);
    expect(_sparks(1), findsOneWidget);
    await _settleFully(t);
  });

  testWidgets('the board hides a collected spark and bursts, then pauses', (
    t,
  ) async {
    await _pumpGame(t, '1-03');
    final board = _board(t);
    // Twinkling sparks never keep a frozen board awake.
    expect(board.paused, isTrue);
    expect(board.sparkVisibleForTesting(_sparkBelowStart), isTrue);
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await t.pump(Duration.zero);
    await t.pump(const Duration(milliseconds: 150));
    expect(board.sparkBurstActiveForTesting, isTrue);
    expect(board.paused, isFalse);
    await _settleFully(t);
    expect(board.sparkBurstActiveForTesting, isFalse);
    expect(board.sparkVisibleForTesting(_sparkBelowStart), isFalse);
    expect(board.paused, isTrue);

    // Rewind brings it back, and the board settles again.
    await tapKey(t, LogicalKeyboardKey.keyZ);
    await _settleFully(t);
    expect(board.sparkVisibleForTesting(_sparkBelowStart), isTrue);
    expect(board.paused, isTrue);
  });

  testWidgets('a star flies to the counter on collect and back on rewind', (
    t,
  ) async {
    await _pumpGame(t, '1-03');
    expect(_fly, findsNothing);
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await t.pump(Duration.zero);
    await t.pump(const Duration(milliseconds: 100));
    expect(_fly, findsOneWidget);
    await pumpFrames(t, const Duration(milliseconds: 500));
    expect(_fly, findsNothing);
    await t.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await t.pump(Duration.zero);
    await t.pump(const Duration(milliseconds: 50));
    expect(_fly, findsOneWidget);
    await pumpFrames(t, const Duration(milliseconds: 400));
    expect(_fly, findsNothing);
    await _settleFully(t);
  });

  testWidgets('restart clears sparks without a fly-back', (t) async {
    await _pumpGame(t, '1-03');
    await tapKey(t, LogicalKeyboardKey.arrowDown);
    await pumpFrames(t, const Duration(milliseconds: 500));
    await t.tap(find.text('Restart'));
    await t.pump(Duration.zero);
    await t.pump(const Duration(milliseconds: 50));
    expect(_fly, findsNothing);
    expect(_board(t).sparkVisibleForTesting(_sparkBelowStart), isTrue);
    await _settleFully(t);
  });

  testWidgets('reduced effects: no burst, the fly is a short fade', (t) async {
    await _pumpGame(t, '1-03', reduceMotion: true);
    final board = _board(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await t.pump(Duration.zero);
    await t.pump(const Duration(milliseconds: 100));
    expect(board.sparkBurstActiveForTesting, isFalse);
    expect(_fly, findsOneWidget);
    await t.pump(const Duration(milliseconds: 200));
    expect(_fly, findsNothing);
    await _settleFully(t);
    expect(board.paused, isTrue);
  });

  testWidgets('a win records the sparks of that play; reopen keeps them', (
    t,
  ) async {
    final services = await _pumpGame(t, '1-03', defaultWin: true);
    // The stored solution: R, New echo, R R R R. It collects spark 0 only.
    await tapKey(t, LogicalKeyboardKey.arrowRight);
    await t.tap(find.text('New echo · 1 left'));
    await t.pump(beat);
    for (var i = 0; i < 4; i++) {
      await tapKey(t, LogicalKeyboardKey.arrowRight);
    }
    await t.pump(const Duration(milliseconds: 500));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(beat);
    expect(find.text('Level complete'), findsOneWidget);
    final p = services.progress.progressOf('1-03');
    expect(p.sparkMask, 0x1);
    expect(p.movesStar, isTrue);
    expect(p.stars, 2);
    final reopened = (await t.runAsync(ProgressRepository.open))!;
    expect(reopened.progressOf('1-03').sparkMask, 0x1);
    expect(reopened.totalSparks, 1);
  });

  testWidgets('losing records nothing', (t) async {
    final services = await _pumpGame(t, '1-01', defaultWin: true);
    await tapKey(t, LogicalKeyboardKey.arrowRight);
    expect(_sparks(1), findsOneWidget);
    await t.tap(find.text('Give up'));
    await t.pump(beat);
    expect(_game(t).state.status, GameStatus.lost);
    await t.pump(const Duration(seconds: 1));
    final p = services.progress.progressOf('1-01');
    expect(p.completed, isFalse);
    expect(p.sparkMask, 0);
    final reopened = (await t.runAsync(ProgressRepository.open))!;
    expect(reopened.totalSparks, 0);
  });
}

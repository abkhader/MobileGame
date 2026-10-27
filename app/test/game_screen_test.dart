import 'dart:convert';

import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_core/echo_core.dart';
import 'package:echo_app/game/battery_bar.dart';
import 'package:echo_app/game/echo_board.dart';
import 'package:echo_app/game/game_controller.dart';
import 'package:echo_app/screens/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';
import 'support/flow_input.dart';

/// Serves invalid JSON for every asset.
class _BrokenBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode('not json')));
}

const _frame = Duration(milliseconds: 200);

// A fresh bundle per test: rootBundle caches each load's future in the
// fake-async zone of the test that first made it, so later tests hang on it.
Future<AppServices> _services(WidgetTester t, {AssetBundle? bundle}) async {
  SharedPreferences.setMockInitialValues({});
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(bundle ?? PlatformAssetBundle()),
    progress: progress,
    ads: FakeAdService(),
    audio: const SilentAudioService(),
    story: StoryRepository(PlatformAssetBundle()),
  );
}

Future<void> _pumpGame(
  WidgetTester t,
  String levelId, {
  AssetBundle? bundle,
  void Function(GameController c)? onWon,
}) async {
  final services = await _services(t, bundle: bundle);
  await t.pumpWidget(
    MaterialApp(
      home: GameScreen(services: services, levelId: levelId, onWon: onWon),
    ),
  );
  await t.pump(_frame);
  await t.pump(_frame);
}

bool _enabled(WidgetTester t, String label) => t
    .widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    )
    .enabled;

Future<void> _stepRight(WidgetTester t) =>
    tapKey(t, LogicalKeyboardKey.arrowRight);

EchoBoard _board(WidgetTester t) =>
    (t.state(find.byType(GameScreen)) as dynamic).boardForTesting as EchoBoard;

bool _waitButtonFound() => find.bySemanticsLabel('Wait').evaluate().isNotEmpty;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HUD starts at run 1 with New echo enabled', (t) async {
    await _pumpGame(t, '1-03');
    expect(find.text('Echo'), findsOneWidget);
    expect(find.bySemanticsLabel('Run 1 of 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Battery, 25 moves left'), findsOneWidget);
    expect(
      find.text(
        'Tap New echo. Pip starts over, and your echo repeats every move.',
      ),
      findsOneWidget,
    );
    expect(find.text('Undo'), findsNothing);
    expect(_waitButtonFound(), isTrue);
    // Ruling: a 0-move echo is allowed while runs remain.
    expect(_enabled(t, 'New echo · 1 left'), isTrue);
    expect(_enabled(t, 'Restart'), isTrue);
    expect(_enabled(t, 'Hint'), isTrue);
  });

  testWidgets('Give up stays disabled at tick 0 on the final run', (t) async {
    await _pumpGame(t, '1-03');
    await t.tap(find.text('New echo · 1 left'));
    await t.pump(_frame);
    expect(find.bySemanticsLabel('Run 2 of 2'), findsOneWidget);
    expect(_enabled(t, 'Give up'), isFalse);
    await _stepRight(t);
    expect(_enabled(t, 'Give up'), isTrue);
  });

  testWidgets('a key tap moves once; New echo stays enabled', (t) async {
    await _pumpGame(t, '1-03');
    await _stepRight(t);
    expect(find.bySemanticsLabel('Battery, 24 moves left'), findsOneWidget);
    expect(find.text('Moves 1'), findsNothing);
    expect(_enabled(t, 'New echo · 1 left'), isTrue);
  });

  testWidgets('three quick key taps all register', (t) async {
    await _pumpGame(t, '1-03');
    await _stepRight(t);
    await _stepRight(t);
    await _stepRight(t);
    expect(find.bySemanticsLabel('Battery, 22 moves left'), findsOneWidget);
  });

  testWidgets('New echo starts the next run', (t) async {
    await _pumpGame(t, '1-03');
    await _stepRight(t);
    await t.tap(find.text('New echo · 1 left'));
    await t.pump(_frame);
    expect(find.bySemanticsLabel('Run 2 of 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Battery, 25 moves left'), findsOneWidget);
  });

  testWidgets('running out of runs shows the lose overlay', (t) async {
    await _pumpGame(t, '1-01');
    await tapKey(t, LogicalKeyboardKey.space);
    expect(find.bySemanticsLabel('Battery, 24 moves left'), findsOneWidget);
    await t.tap(find.text('Give up'));
    await t.pump(_frame);
    expect(find.text('Out of runs'), findsOneWidget);
    await t.tap(find.text('Try again'));
    await t.pump(_frame);
    expect(find.text('Out of runs'), findsNothing);
    expect(find.bySemanticsLabel('Battery, 25 moves left'), findsOneWidget);
  });

  testWidgets('Hint is disabled once the level is lost', (t) async {
    await _pumpGame(t, '1-01');
    await tapKey(t, LogicalKeyboardKey.space);
    await t.tap(find.text('Give up'));
    await t.pump(_frame);
    expect(find.text('Out of runs'), findsOneWidget);
    expect(_enabled(t, 'Hint'), isFalse);
  });

  testWidgets('system back pops to the previous route', (t) async {
    final services = await _services(t);
    final navigator = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('placeholder')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(services: services, levelId: '1-03'),
      ),
    );
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.bySemanticsLabel('Run 1 of 2'), findsOneWidget);
    expect(find.text('placeholder'), findsNothing);
    await t.binding.handlePopRoute();
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('placeholder'), findsOneWidget);
    expect(find.bySemanticsLabel('Run 1 of 2'), findsNothing);
  });

  testWidgets('a broken level shows the error card and pops', (t) async {
    final services = await _services(t, bundle: _BrokenBundle());
    final navigator = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('placeholder')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(services: services, levelId: '1-01'),
      ),
    );
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text("This level couldn't be loaded."), findsOneWidget);
    await t.tap(find.text('Back to levels'));
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('placeholder'), findsOneWidget);
    expect(find.text("This level couldn't be loaded."), findsNothing);
  });

  testWidgets('winning calls onWon once after a short delay', (t) async {
    final won = <GameController>[];
    await _pumpGame(t, '1-01', onWon: won.add);
    for (var i = 0; i < 3; i++) {
      await _stepRight(t);
    }
    // The winning step: one beat, then less than the win delay.
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await t.pump(_frame);
    expect(won, isEmpty);
    await t.pump(const Duration(milliseconds: 500));
    expect(won, hasLength(1));
    expect(won.single.state.tick, 4);
    await t.pump(const Duration(milliseconds: 500));
    expect(won, hasLength(1));
  });

  testWidgets('winning while the menu is open closes it', (t) async {
    await _pumpGame(t, '1-01');
    for (var i = 0; i < 3; i++) {
      await _stepRight(t);
    }
    await t.tap(find.byTooltip('More'));
    await t.pump(_frame);
    await t.pump(_frame);
    expect(find.text('Skip level'), findsOneWidget);
    // The menu barrier blocks the board: make the winning move directly.
    final state = t.state(find.byType(GameScreen)) as dynamic;
    (state.controllerForTesting as GameController).move(Move.right);
    await t.pump(const Duration(milliseconds: 600));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump(_frame);
    await t.pump(_frame);
    expect(find.text('Level complete'), findsOneWidget);
    expect(find.text('Skip level'), findsNothing);
  });

  testWidgets('the battery is a ring: HUD keeps only its label', (t) async {
    await _pumpGame(t, '1-03');
    await _stepRight(t);
    expect(find.byType(BatteryBar), findsNothing);
    expect(find.bySemanticsLabel('Battery, 24 moves left'), findsOneWidget);
  });

  testWidgets('the board pauses when time freezes; a press resumes it', (
    t,
  ) async {
    await _pumpGame(t, '1-03');
    expect(_board(t).paused, isTrue);
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    expect(_board(t).paused, isFalse);
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await settle(t);
    // The glide is done; trail, lean and squash fade within a few frames.
    await pumpFrames(t, const Duration(milliseconds: 600));
    expect(_board(t).paused, isTrue);
    // Holding Wait wakes it even though Pip does not move.
    final wait = await t.startGesture(
      t.getCenter(find.bySemanticsLabel('Wait')),
    );
    await t.pump(const Duration(milliseconds: 50));
    expect(_board(t).paused, isFalse);
    await wait.up();
    await settle(t);
    await pumpFrames(t, const Duration(milliseconds: 600));
    expect(_board(t).paused, isTrue);
  });

  testWidgets('OS reduce motion turns on the board\'s reduceEffects', (
    t,
  ) async {
    final services = await _services(t);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: GameScreen(services: services, levelId: '1-03'),
        ),
      ),
    );
    await t.pump(_frame);
    await t.pump(_frame);
    expect(_board(t).reduceEffects, isTrue);
    await _stepRight(t);
    expect(find.bySemanticsLabel('Battery, 24 moves left'), findsOneWidget);
  });
}

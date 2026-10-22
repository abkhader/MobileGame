import 'dart:convert';

import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_core/echo_core.dart';
import 'package:echo_app/game/game_controller.dart';
import 'package:echo_app/screens/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';

/// Serves invalid JSON for every asset.
class _BrokenBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode('not json')));
}

const _frame = Duration(milliseconds: 200);
final _board = find.byKey(const Key('board'));

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

Future<void> _flingRight(WidgetTester t) =>
    t.fling(_board, const Offset(300, 0), 1000);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HUD starts at run 1 with undo and end run disabled', (t) async {
    await _pumpGame(t, '1-03');
    expect(find.text('Echo'), findsOneWidget);
    expect(find.text('Run 1 / 2'), findsOneWidget);
    expect(find.text('Moves 0'), findsOneWidget);
    expect(
      find.text('Tap End run. Pip rewinds, and your echo replays every move.'),
      findsOneWidget,
    );
    expect(_enabled(t, 'Undo'), isFalse);
    expect(_enabled(t, 'End run'), isFalse);
    expect(_enabled(t, 'Restart'), isTrue);
    expect(_enabled(t, 'Hint'), isTrue);
  });

  testWidgets('a swipe moves and enables undo and end run', (t) async {
    await _pumpGame(t, '1-03');
    await _flingRight(t);
    await t.pump(_frame);
    expect(find.text('Moves 1'), findsOneWidget);
    expect(_enabled(t, 'Undo'), isTrue);
    expect(_enabled(t, 'End run'), isTrue);
  });

  testWidgets('three fast swipes all register', (t) async {
    await _pumpGame(t, '1-03');
    await _flingRight(t);
    await _flingRight(t);
    await _flingRight(t);
    await t.pump(_frame);
    await t.pump(_frame);
    expect(find.text('Moves 3'), findsOneWidget);
  });

  testWidgets('End run starts the next run', (t) async {
    await _pumpGame(t, '1-03');
    await _flingRight(t);
    await t.pump(_frame);
    await t.tap(find.text('End run'));
    await t.pump(_frame);
    expect(find.text('Run 2 / 2'), findsOneWidget);
    expect(find.text('Moves 0'), findsOneWidget);
  });

  testWidgets('running out of runs shows the lose overlay', (t) async {
    await _pumpGame(t, '1-01');
    await t.tap(_board);
    await t.pump(_frame);
    expect(find.text('Moves 1'), findsOneWidget);
    await t.tap(find.text('End run'));
    await t.pump(_frame);
    expect(find.text('Out of runs'), findsOneWidget);
    await t.tap(find.text('Try again'));
    await t.pump(_frame);
    expect(find.text('Out of runs'), findsNothing);
    expect(find.text('Moves 0'), findsOneWidget);
  });

  testWidgets('Hint is disabled once the level is lost', (t) async {
    await _pumpGame(t, '1-01');
    await t.tap(_board);
    await t.pump(_frame);
    await t.tap(find.text('End run'));
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
    expect(find.text('Run 1 / 2'), findsOneWidget);
    expect(find.text('placeholder'), findsNothing);
    await t.binding.handlePopRoute();
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('placeholder'), findsOneWidget);
    expect(find.text('Run 1 / 2'), findsNothing);
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
    for (var i = 0; i < 4; i++) {
      await _flingRight(t);
      await t.pump(_frame);
    }
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
      await _flingRight(t);
      await t.pump(_frame);
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
}

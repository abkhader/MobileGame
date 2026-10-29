import 'dart:async';

import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_app/game/battery_bar.dart';
import 'package:echo_app/game/game_clock.dart';
import 'package:echo_app/screens/city_map_screen.dart';
import 'package:echo_app/screens/game_screen.dart';
import 'package:echo_app/screens/home_screen.dart';
import 'package:echo_app/screens/level_complete_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';
import 'support/flow_input.dart';
import 'support/story_flags.dart';

const _frame = Duration(milliseconds: 200);
final _level1 = find.bySemanticsLabel('Level 1, open');
final _locked = find.bySemanticsLabel(RegExp(r'^Level \d+, locked$'));
final _map = find.text('Lumen City');

Future<AppServices> _services(WidgetTester t) async {
  SharedPreferences.setMockInitialValues(await introsSeenPrefs(t));
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
    ads: FakeAdService(),
    audio: const SilentAudioService(),
    story: StoryRepository(PlatformAssetBundle()),
  );
}

/// The bundled level ids, in order, from a fresh asset bundle.
Future<List<String>> _levelIds(WidgetTester t) async =>
    (await t.runAsync(LevelRepository(PlatformAssetBundle()).levelIds))!;

Future<void> _pumpHome(WidgetTester t, AppServices services) async {
  await t.pumpWidget(MaterialApp(home: HomeScreen(services: services)));
}

/// Makes the test view tall enough to show every district of the map, so
/// locked buildings can be counted across all chapters.
void _showAllLevels(WidgetTester t) {
  t.view.physicalSize = const Size(800, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _tapAndPump(WidgetTester t, Finder f) async {
  await t.tap(f);
  await t.pump(_frame);
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _openMap(WidgetTester t) async {
  await _tapAndPump(t, find.text('Map'));
  // Level ids load from the asset bundle, which needs real async.
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await t.pump(_frame);
}

Future<void> _winLevel1(WidgetTester t) async {
  // Four beats of holding right.
  await holdKey(t, LogicalKeyboardKey.arrowRight, const Duration(seconds: 1));
  await t.pump(const Duration(milliseconds: 500));
  await t.pump(const Duration(milliseconds: 500));
}

/// Delegates to a real repository but holds recordWin on [gate].
class _GatedProgress extends ChangeNotifier implements ProgressRepository {
  _GatedProgress(this._inner);

  final ProgressRepository _inner;
  final gate = Completer<void>();

  @override
  Future<void> recordWin(
    String id, {
    required int score,
    required int best,
    required int sparkMask,
  }) async {
    await gate.future;
    await _inner.recordWin(id, score: score, best: best, sparkMask: sparkMask);
  }

  @override
  int get totalSparks => _inner.totalSparks;

  @override
  void addListener(VoidCallback listener) => _inner.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => _inner.removeListener(listener);
  @override
  LevelProgress progressOf(String id) => _inner.progressOf(id);
  @override
  bool isUnlocked(String id, List<String> orderedIds) =>
      _inner.isUnlocked(id, orderedIds);
  @override
  Future<void> recordSkip(String id) => _inner.recordSkip(id);
  @override
  int get rewindTipsShown => _inner.rewindTipsShown;
  @override
  Future<void> markRewindTipShown() => _inner.markRewindTipShown();
  @override
  bool get musicOn => _inner.musicOn;
  @override
  bool get sfxOn => _inner.sfxOn;
  @override
  Future<void> setMusicOn(bool value) => _inner.setMusicOn(value);
  @override
  Future<void> setSfxOn(bool value) => _inner.setSfxOn(value);
  @override
  bool seenChapterIntro(int chapter) => _inner.seenChapterIntro(chapter);
  @override
  Future<void> markChapterIntroSeen(int chapter) =>
      _inner.markChapterIntroSeen(chapter);
  @override
  String? get endingSeenFor => _inner.endingSeenFor;
  @override
  bool endingSeenOn(String lastLevelId) => _inner.endingSeenOn(lastLevelId);
  @override
  Future<void> markEndingSeen(String lastLevelId) =>
      _inner.markEndingSeen(lastLevelId);
  @override
  MoveSpeed get moveSpeed => _inner.moveSpeed;
  @override
  Future<void> setMoveSpeed(MoveSpeed value) => _inner.setMoveSpeed(value);
  @override
  bool get reduceEffects => _inner.reduceEffects;
  @override
  Future<void> setReduceEffects(bool value) => _inner.setReduceEffects(value);
  @override
  bool get vibration => _inner.vibration;
  @override
  Future<void> setVibration(bool value) => _inner.setVibration(value);
}

/// Waits for the real-async asset loads behind a tap, then pumps a few frames.
/// Never pumpAndSettle: Home's blink repeats forever.
Future<void> _settleLoads(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await t.pump(_frame);
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _completeFirst(
  WidgetTester t,
  AppServices services,
  int count,
) async {
  final ids = await _levelIds(t);
  for (final id in ids.take(count)) {
    await t.runAsync(
      () => services.progress.recordWin(id, score: 1, best: 1, sparkMask: 0x7),
    );
  }
}

String _openedLevel(WidgetTester t) =>
    t.widget<GameScreen>(find.byType(GameScreen)).levelId;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Play on a fresh install opens 1-01', (t) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _tapAndPump(t, find.text('Play'));
    await _settleLoads(t);
    expect(_openedLevel(t), '1-01');
  });

  testWidgets('Play continues at the first unsolved level', (t) async {
    final services = await _services(t);
    await _completeFirst(t, services, 4);
    await _pumpHome(t, services);
    await _tapAndPump(t, find.text('Play'));
    await _settleLoads(t);
    expect(_openedLevel(t), '1-05');
  });

  testWidgets('Play with all levels done opens the map', (t) async {
    final services = await _services(t);
    final ids = await _levelIds(t);
    await _completeFirst(t, services, ids.length);
    await _pumpHome(t, services);
    await _tapAndPump(t, find.text('Play'));
    await _settleLoads(t);
    expect(find.byType(CityMapScreen), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);
  });

  testWidgets('Play, win, then Levels lands on the map, not Home', (t) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _tapAndPump(t, find.text('Play'));
    await _settleLoads(t);
    await _winLevel1(t);
    expect(find.text('Level complete'), findsOneWidget);
    await _tapAndPump(t, find.text('Levels'));
    expect(_map, findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('Map button opens the map', (t) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _openMap(t);
    expect(find.byType(CityMapScreen), findsOneWidget);
    expect(_map, findsOneWidget);
  });

  testWidgets('Home blinks forever without hanging the test', (t) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _settleLoads(t);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Map shows the map with level 1 open, 2 and 3 locked', (t) async {
    _showAllLevels(t);
    final services = await _services(t);
    final ids = await _levelIds(t);
    await _pumpHome(t, services);
    await _openMap(t);
    expect(_map, findsOneWidget);
    expect(find.text('The Outskirts'), findsOneWidget);
    expect(_level1, findsOneWidget);
    // Every level except the first is locked.
    expect(_locked, findsNWidgets(ids.length - 1));
    expect(find.bySemanticsLabel('Level 2, locked'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 3, locked'), findsOneWidget);
  });

  testWidgets('winning level 1 saves progress and shows Level complete', (
    t,
  ) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _openMap(t);
    await _tapAndPump(t, _level1);
    await _winLevel1(t);
    expect(find.text('Level complete'), findsOneWidget);
    expect(services.progress.progressOf('1-01').stars, 3);
    expect(services.completedThisSession, 1);
    expect(find.byIcon(Icons.star), findsNWidgets(3));
    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('In 4 moves or fewer'), findsOneWidget);
    expect(find.text('Score 4 · Best 4'), findsOneWidget);
  });

  testWidgets('Level complete waits for the save to finish', (t) async {
    final real = await _services(t);
    final gated = _GatedProgress(real.progress);
    final services = AppServices(
      levels: real.levels,
      progress: gated,
      ads: real.ads,
      audio: real.audio,
      story: real.story,
    );
    await _pumpHome(t, services);
    await _openMap(t);
    await _tapAndPump(t, _level1);
    await _winLevel1(t);
    expect(find.text('Level complete'), findsNothing);
    expect(services.completedThisSession, 0);
    gated.gate.complete();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Level complete'), findsOneWidget);
    expect(services.completedThisSession, 1);
    final reopened = (await t.runAsync(ProgressRepository.open))!;
    expect(reopened.progressOf('1-01').stars, 3);
  });

  testWidgets('Next opens level 2; the map shows progress', (t) async {
    _showAllLevels(t);
    final services = await _services(t);
    final ids = await _levelIds(t);
    await _pumpHome(t, services);
    await _openMap(t);
    expect(_locked, findsNWidgets(ids.length - 1));
    await _tapAndPump(t, _level1);
    await _winLevel1(t);
    await _tapAndPump(t, find.text('Next'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(_frame);
    expect(find.bySemanticsLabel('Run 1 of 1'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(_map, findsOneWidget);
    // Winning level 1 unlocked level 2: one locked building fewer.
    expect(_locked, findsNWidgets(ids.length - 2));
    expect(find.bySemanticsLabel('Level 1, solved, 3 stars'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 2, open'), findsOneWidget);
  });

  testWidgets('Levels after a Next chain shows the latest progress', (t) async {
    _showAllLevels(t);
    final services = await _services(t);
    final ids = await _levelIds(t);
    await _pumpHome(t, services);
    await _openMap(t);
    await _tapAndPump(t, _level1);
    await _winLevel1(t);
    await _tapAndPump(t, find.text('Next'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(_frame);
    expect(find.bySemanticsLabel('Run 1 of 1'), findsOneWidget);
    // Level 1-02 is also won by four moves right.
    await _winLevel1(t);
    expect(find.text('Level complete'), findsOneWidget);
    await _tapAndPump(t, find.text('Levels'));
    expect(_map, findsOneWidget);
    // Levels 1-3 are unlocked after winning 1 and 2; the rest stay locked.
    expect(_locked, findsNWidgets(ids.length - 3));
    expect(find.bySemanticsLabel('Level 3, open'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 1, solved, 3 stars'), findsOneWidget);
    // Four moves right on 1-02 skips its detour spark: no spark star.
    expect(find.bySemanticsLabel('Level 2, solved, 2 stars'), findsOneWidget);
  });

  testWidgets('a win with the overflow menu open replaces the game route', (
    t,
  ) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _openMap(t);
    await _tapAndPump(t, _level1);
    // Beats at 0, 250, 450 and 650 ms: the win lands at 650 ms.
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await pumpFrames(t, const Duration(milliseconds: 700));
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    // Open the menu before the 400 ms win delay fires.
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pump(_frame);
    expect(find.text('Skip level'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Level complete'), findsOneWidget);
    // The game route itself was replaced, not the menu above it.
    expect(find.byType(GameScreen, skipOffstage: false), findsNothing);
    expect(find.byType(BatteryBar, skipOffstage: false), findsNothing);
  });

  testWidgets('Retry reopens the same level with a full battery', (t) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _openMap(t);
    await _tapAndPump(t, _level1);
    await _winLevel1(t);
    await _tapAndPump(t, find.text('Retry'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(_frame);
    expect(find.bySemanticsLabel('Battery, 25 moves left'), findsOneWidget);
  });

  testWidgets('Levels returns to the map', (t) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _openMap(t);
    await _tapAndPump(t, _level1);
    await _winLevel1(t);
    await _tapAndPump(t, find.text('Levels'));
    expect(_map, findsOneWidget);
  });

  testWidgets('the last level has no Next button', (t) async {
    final services = await _services(t);
    final ids = await _levelIds(t);
    await t.pumpWidget(
      MaterialApp(
        home: LevelCompleteScreen(
          services: services,
          levelId: ids.last,
          score: 5,
          best: 5,
          after: const LevelProgress(completed: true, finished: true),
        ),
      ),
    );
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(_frame);
    expect(find.text('Level complete'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Levels'), findsOneWidget);
  });

  testWidgets('toggling Music off persists', (t) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _tapAndPump(t, find.text('Settings'));
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Sound effects'), findsOneWidget);
    await t.tap(find.text('Music'));
    await t.pump(_frame);
    final reopened = (await t.runAsync(ProgressRepository.open))!;
    expect(reopened.musicOn, isFalse);
  });
}

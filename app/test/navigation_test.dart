import 'dart:async';

import 'package:echo_app/app_services.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/screens/home_screen.dart';
import 'package:echo_app/screens/level_complete_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';

const _frame = Duration(milliseconds: 200);
final _board = find.byKey(const Key('board'));

Future<AppServices> _services(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({});
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
    ads: FakeAdService(),
  );
}

/// The bundled level ids, in order, from a fresh asset bundle.
Future<List<String>> _levelIds(WidgetTester t) async =>
    (await t.runAsync(LevelRepository(PlatformAssetBundle()).levelIds))!;

Future<void> _pumpHome(WidgetTester t, AppServices services) async {
  await t.pumpWidget(MaterialApp(home: HomeScreen(services: services)));
}

/// Makes the test view tall enough for Level Select to build every level
/// tile, so lock icons can be counted across all chapters.
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

Future<void> _openLevelSelect(WidgetTester t) async {
  await _tapAndPump(t, find.text('Play'));
  // Level ids load from the asset bundle, which needs real async.
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await t.pump(_frame);
}

Future<void> _winLevel1(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.fling(_board, const Offset(300, 0), 1000);
    await t.pump(_frame);
  }
  await t.pump(const Duration(milliseconds: 500));
  await t.pump(const Duration(milliseconds: 500));
}

/// Delegates to a real repository but holds recordCompletion on [gate].
class _GatedProgress extends ChangeNotifier implements ProgressRepository {
  _GatedProgress(this._inner);

  final ProgressRepository _inner;
  final gate = Completer<void>();

  @override
  Future<void> recordCompletion(String id, int stars) async {
    await gate.future;
    await _inner.recordCompletion(id, stars);
  }

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
  bool get musicOn => _inner.musicOn;
  @override
  bool get sfxOn => _inner.sfxOn;
  @override
  Future<void> setMusicOn(bool value) => _inner.setMusicOn(value);
  @override
  Future<void> setSfxOn(bool value) => _inner.setSfxOn(value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Play shows Chapter 1 with level 1 unlocked, 2 and 3 locked', (
    t,
  ) async {
    _showAllLevels(t);
    final services = await _services(t);
    final ids = await _levelIds(t);
    await _pumpHome(t, services);
    await _openLevelSelect(t);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    // Every level except the first is locked.
    expect(find.byIcon(Icons.lock), findsNWidgets(ids.length - 1));
    expect(find.text('2'), findsNothing);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('winning level 1 saves progress and shows Level complete', (
    t,
  ) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _openLevelSelect(t);
    await _tapAndPump(t, find.text('1'));
    await _winLevel1(t);
    expect(find.text('Level complete'), findsOneWidget);
    expect(services.progress.progressOf('1-01').stars, 3);
    expect(services.completedThisSession, 1);
    expect(find.byIcon(Icons.star), findsNWidgets(3));
    expect(find.text('Score 4 · Best 4'), findsOneWidget);
  });

  testWidgets('Level complete waits for the save to finish', (t) async {
    final real = await _services(t);
    final gated = _GatedProgress(real.progress);
    final services = AppServices(
      levels: real.levels,
      progress: gated,
      ads: real.ads,
    );
    await _pumpHome(t, services);
    await _openLevelSelect(t);
    await _tapAndPump(t, find.text('1'));
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

  testWidgets('Next opens level 2; Level Select shows progress', (t) async {
    _showAllLevels(t);
    final services = await _services(t);
    final ids = await _levelIds(t);
    await _pumpHome(t, services);
    await _openLevelSelect(t);
    expect(find.byIcon(Icons.lock), findsNWidgets(ids.length - 1));
    await _tapAndPump(t, find.text('1'));
    await _winLevel1(t);
    await _tapAndPump(t, find.text('Next'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(_frame);
    expect(find.text('Run 1 / 1'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Chapter 1'), findsOneWidget);
    // Winning level 1 unlocked level 2: one lock fewer.
    expect(find.byIcon(Icons.lock), findsNWidgets(ids.length - 2));
    expect(find.byIcon(Icons.star), findsNWidgets(3));
  });

  testWidgets('Levels after a Next chain shows the latest progress', (t) async {
    _showAllLevels(t);
    final services = await _services(t);
    final ids = await _levelIds(t);
    await _pumpHome(t, services);
    await _openLevelSelect(t);
    await _tapAndPump(t, find.text('1'));
    await _winLevel1(t);
    await _tapAndPump(t, find.text('Next'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(_frame);
    expect(find.text('Run 1 / 1'), findsOneWidget);
    // Level 1-02 is also won by four moves right.
    await _winLevel1(t);
    expect(find.text('Level complete'), findsOneWidget);
    await _tapAndPump(t, find.text('Levels'));
    expect(find.text('Chapter 1'), findsOneWidget);
    // Levels 1-3 are unlocked after winning 1 and 2; the rest stay locked.
    expect(find.byIcon(Icons.lock), findsNWidgets(ids.length - 3));
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNWidgets(6));
  });

  testWidgets('a win with the overflow menu open replaces the game route', (
    t,
  ) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _openLevelSelect(t);
    await _tapAndPump(t, find.text('1'));
    for (var i = 0; i < 4; i++) {
      await t.fling(_board, const Offset(300, 0), 1000);
      await t.pump(const Duration(milliseconds: 50));
    }
    // Open the menu before the 400 ms win delay fires.
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pump(_frame);
    expect(find.text('Skip level'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Level complete'), findsOneWidget);
    // The game route itself was replaced, not the menu above it.
    expect(find.text('Moves 4', skipOffstage: false), findsNothing);
  });

  testWidgets('Retry reopens the same level at Moves 0', (t) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _openLevelSelect(t);
    await _tapAndPump(t, find.text('1'));
    await _winLevel1(t);
    await _tapAndPump(t, find.text('Retry'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(_frame);
    expect(find.text('Moves 0'), findsOneWidget);
  });

  testWidgets('Levels returns to Level Select', (t) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _openLevelSelect(t);
    await _tapAndPump(t, find.text('1'));
    await _winLevel1(t);
    await _tapAndPump(t, find.text('Levels'));
    expect(find.text('Chapter 1'), findsOneWidget);
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
          stars: 3,
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

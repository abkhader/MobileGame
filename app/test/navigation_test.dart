import 'package:echo_app/app_services.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/screens/home_screen.dart';
import 'package:echo_app/screens/level_complete_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _frame = Duration(milliseconds: 200);
final _board = find.byKey(const Key('board'));

Future<AppServices> _services(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({});
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
  );
}

Future<void> _pumpHome(WidgetTester t, AppServices services) async {
  await t.pumpWidget(MaterialApp(home: HomeScreen(services: services)));
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Play shows Chapter 1 with level 1 unlocked, 2 and 3 locked', (
    t,
  ) async {
    final services = await _services(t);
    await _pumpHome(t, services);
    await _openLevelSelect(t);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNWidgets(2));
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

  testWidgets('Next opens level 2; Level Select shows progress', (t) async {
    final services = await _services(t);
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
    await t.binding.handlePopRoute();
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNWidgets(3));
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
    await t.pumpWidget(
      MaterialApp(
        home: LevelCompleteScreen(
          services: services,
          levelId: '1-03',
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

import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_app/screens/city_map_screen.dart';
import 'package:echo_app/screens/game_screen.dart';
import 'package:echo_app/screens/story_card_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';

const _frame = Duration(milliseconds: 200);
const _skipKey = Key('story-skip');

Future<AppServices> _services(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({});
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
    ads: FakeAdService(),
    audio: const SilentAudioService(),
    story: StoryRepository(PlatformAssetBundle()),
  );
}

/// Lets asset loads (levels, story) finish, then pumps frames.
Future<void> _settle(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await t.pump(_frame);
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _pumpMap(WidgetTester t, AppServices services) async {
  await t.pumpWidget(MaterialApp(home: CityMapScreen(services: services)));
  await _settle(t);
}

/// A view tall enough to show all three districts at once.
void _tallView(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _completeChapter(
  WidgetTester t,
  AppServices services,
  int chapter,
) async {
  final ids = (await t.runAsync(services.levels.levelIds))!;
  await t.runAsync(() async {
    for (final id in ids.where((id) => id.startsWith('$chapter-'))) {
      await services.progress.recordCompletion(id, 3);
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a fresh install opens level 1 and locks level 2', (t) async {
    final services = await _services(t);
    await _pumpMap(t, services);
    expect(find.text('Lumen City'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 1, open'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 2, locked'), findsOneWidget);
    expect(find.text('The Outskirts'), findsOneWidget);
  });

  testWidgets('a completion lights the building with its stars', (t) async {
    final services = await _services(t);
    await _pumpMap(t, services);
    await t.runAsync(() => services.progress.recordCompletion('1-01', 2));
    await t.pump(_frame);
    expect(find.bySemanticsLabel('Level 1, solved, 2 stars'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 2, open'), findsOneWidget);
  });

  testWidgets('a skipped level is solved with 0 stars', (t) async {
    final services = await _services(t);
    await t.runAsync(() => services.progress.recordSkip('1-01'));
    await _pumpMap(t, services);
    expect(find.bySemanticsLabel('Level 1, solved, 0 stars'), findsOneWidget);
  });

  testWidgets('a district opens only after the one before it', (t) async {
    _tallView(t);
    final services = await _services(t);
    await _pumpMap(t, services);
    expect(find.bySemanticsLabel('Level 11, locked'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 21, locked'), findsOneWidget);
    await _completeChapter(t, services, 1);
    await t.pump(_frame);
    expect(find.bySemanticsLabel('Level 11, open'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 21, locked'), findsOneWidget);
  });

  testWidgets('tapping a locked building does nothing', (t) async {
    final services = await _services(t);
    await _pumpMap(t, services);
    await t.tap(find.bySemanticsLabel('Level 2, locked'));
    await _settle(t);
    expect(find.byType(GameScreen), findsNothing);
    expect(find.byType(StoryCardScreen), findsNothing);
    expect(find.text('Lumen City'), findsOneWidget);
  });

  testWidgets('tapping an open building opens its level', (t) async {
    final services = await _services(t);
    await t.runAsync(() => services.progress.markChapterIntroSeen(1));
    await _pumpMap(t, services);
    await t.tap(find.bySemanticsLabel('Level 1, open'));
    await _settle(t);
    expect(t.widget<GameScreen>(find.byType(GameScreen)).levelId, '1-01');
  });

  testWidgets('tapping The Market replays the Market card', (t) async {
    _tallView(t);
    final services = await _services(t);
    await _pumpMap(t, services);
    await t.tap(find.text('The Market'));
    await _settle(t);
    expect(find.byType(StoryCardScreen), findsOneWidget);
    expect(find.text('The Market used to glow all night.'), findsOneWidget);
    await t.tap(find.byKey(_skipKey));
    await _settle(t);
    expect(find.byType(StoryCardScreen), findsNothing);
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('Lumen City'), findsOneWidget);
  });

  testWidgets('The Core replays the ending once it was seen and earned', (
    t,
  ) async {
    _tallView(t);
    final services = await _services(t);
    await _completeChapter(t, services, 3);
    await t.runAsync(services.progress.markEndingSeen);
    await _pumpMap(t, services);
    await t.tap(find.text('The Core'));
    await _settle(t);
    expect(find.text('Thanks for playing.', skipOffstage: false), findsOne);
    expect(find.text('The Core powers the whole city.'), findsNothing);
  });

  testWidgets('The Core shows its card while the ending is unseen', (t) async {
    _tallView(t);
    final services = await _services(t);
    await _completeChapter(t, services, 3);
    await _pumpMap(t, services);
    await t.tap(find.text('The Core'));
    await _settle(t);
    expect(find.text('The Core powers the whole city.'), findsOneWidget);
    expect(find.text('Thanks for playing.', skipOffstage: false), findsNothing);
  });

  testWidgets('The Core shows its card while the chapter is incomplete', (
    t,
  ) async {
    _tallView(t);
    final services = await _services(t);
    await t.runAsync(services.progress.markEndingSeen);
    await _pumpMap(t, services);
    await t.tap(find.text('The Core'));
    await _settle(t);
    expect(find.text('The Core powers the whole city.'), findsOneWidget);
    expect(find.text('Thanks for playing.', skipOffstage: false), findsNothing);
  });

  testWidgets('every building target is at least 44 wide at 320x640', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final services = await _services(t);
    final ids = (await t.runAsync(services.levels.levelIds))!;
    await _pumpMap(t, services);
    expect(t.takeException(), isNull);
    for (final id in ids) {
      final target = find.byKey(ValueKey('building-$id'), skipOffstage: false);
      expect(target, findsOneWidget, reason: id);
      expect(t.getSize(target).width, greaterThanOrEqualTo(44), reason: id);
    }
  });
}

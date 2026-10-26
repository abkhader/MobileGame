import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_app/screens/city_map_screen.dart';
import 'package:echo_app/screens/game_screen.dart';
import 'package:echo_app/screens/home_screen.dart';
import 'package:echo_app/screens/level_complete_screen.dart';
import 'package:echo_app/screens/story_card_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';
import 'support/flow_input.dart';

const _frame = Duration(milliseconds: 200);
const _skipKey = Key('story-skip');
final _level1 = find.bySemanticsLabel('Level 1, open');
final _map = find.text('Lumen City');

/// A fresh platform bundle whose story asset is an empty JSON object.
class _BrokenStoryBundle extends PlatformAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) {
    if (key == StoryRepository.path) return Future.value('{}');
    return super.loadString(key, cache: cache);
  }
}

Future<AppServices> _services(
  WidgetTester t, {
  FakeAdService? ads,
  AssetBundle? storyBundle,
}) async {
  SharedPreferences.setMockInitialValues({});
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
    ads: ads ?? FakeAdService(),
    audio: const SilentAudioService(),
    story: StoryRepository(storyBundle ?? PlatformAssetBundle()),
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

Future<void> _tapAndSettle(WidgetTester t, Finder f) async {
  await t.tap(f);
  await t.pump(_frame);
  await _settle(t);
}

/// Pumps the city map and waits for its buildings.
Future<void> _pumpMap(WidgetTester t, AppServices services) async {
  await t.pumpWidget(MaterialApp(home: CityMapScreen(services: services)));
  await _settle(t);
}

Future<void> _pushLevelComplete(
  WidgetTester t,
  AppServices services,
  String id,
) async {
  t
      .state<NavigatorState>(find.byType(Navigator))
      .push(
        MaterialPageRoute<void>(
          builder: (_) => LevelCompleteScreen(
            services: services,
            levelId: id,
            score: 5,
            best: 5,
            after: const LevelProgress(
              completed: true,
              finished: true,
              sparkMask: 7,
              movesStar: true,
            ),
          ),
        ),
      );
  await t.pump(_frame);
  await _settle(t);
}

Future<void> _completeChapter1(WidgetTester t, AppServices services) async {
  final ids = (await t.runAsync(services.levels.levelIds))!;
  await t.runAsync(() async {
    for (final id in ids.where((id) => id.startsWith('1-'))) {
      await services.progress.recordWin(id, score: 1, best: 1, sparkMask: 0x7);
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first open of 1-01 shows the Outskirts card once', (t) async {
    final services = await _services(t);
    await _pumpMap(t, services);
    await _tapAndSettle(t, _level1);
    expect(find.text('The Outskirts'), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byType(StoryCardScreen));
      await t.pump(_frame);
    }
    await _settle(t);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('The Outskirts'), findsNothing);
    expect(services.progress.seenChapterIntro(1), isTrue);

    await t.binding.handlePopRoute();
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(GameScreen), findsNothing);
    await _tapAndSettle(t, _level1);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('The Outskirts'), findsNothing);
  });

  testWidgets('skip goes straight to the level', (t) async {
    final services = await _services(t);
    await _pumpMap(t, services);
    await _tapAndSettle(t, _level1);
    expect(find.text('The Outskirts'), findsOneWidget);
    await _tapAndSettle(t, find.byKey(_skipKey));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('The Outskirts'), findsNothing);
    expect(services.progress.seenChapterIntro(1), isTrue);
  });

  testWidgets('Retry after a win replays the level with no card', (t) async {
    final services = await _services(t);
    await _pumpMap(t, services);
    await _tapAndSettle(t, _level1);
    await _tapAndSettle(t, find.byKey(_skipKey));
    // Level 1-01 is won by four moves right.
    await holdKey(t, LogicalKeyboardKey.arrowRight, const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Level complete'), findsOneWidget);
    await _tapAndSettle(t, find.text('Retry'));
    expect(find.byType(StoryCardScreen), findsNothing);
    expect(t.widget<GameScreen>(find.byType(GameScreen)).levelId, '1-01');
    expect(find.bySemanticsLabel('Battery, 25 moves left'), findsOneWidget);
  });

  testWidgets(
    'entering chapter 2 via Level Complete Next shows the Market card',
    (t) async {
      final services = await _services(t);
      await _completeChapter1(t, services);
      await t.runAsync(() => services.progress.markChapterIntroSeen(1));
      await _pumpMap(t, services);
      await _pushLevelComplete(t, services, '1-10');
      await _tapAndSettle(t, find.text('Next'));
      expect(find.text('The Market'), findsOneWidget);
      expect(find.byType(LevelCompleteScreen), findsNothing);
      await _tapAndSettle(t, find.byKey(_skipKey));
      expect(t.widget<GameScreen>(find.byType(GameScreen)).levelId, '2-01');
      expect(services.progress.seenChapterIntro(2), isTrue);
    },
  );

  testWidgets('skip on 1-10 shows the Market card', (t) async {
    final ads = FakeAdService();
    final services = await _services(t, ads: ads);
    await t.pumpWidget(
      MaterialApp(
        home: GameScreen(services: services, levelId: '1-10'),
      ),
    );
    await _settle(t);
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    await _tapAndSettle(t, find.text('Skip level'));
    expect(ads.rewardedShown, 1);
    expect(find.text('The Market'), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);
    await _tapAndSettle(t, find.byKey(_skipKey));
    expect(t.widget<GameScreen>(find.byType(GameScreen)).levelId, '2-01');
  });

  testWidgets('broken story opens the level', (t) async {
    final services = await _services(t, storyBundle: _BrokenStoryBundle());
    await _pumpMap(t, services);
    await _tapAndSettle(t, _level1);
    expect(find.byType(StoryCardScreen), findsNothing);
    expect(find.text('The Outskirts'), findsNothing);
    expect(t.widget<GameScreen>(find.byType(GameScreen)).levelId, '1-01');
  });

  testWidgets('ending shows once after first 3-10 win', (t) async {
    final services = await _services(t);
    final ids = (await t.runAsync(services.levels.levelIds))!;
    expect(ids.last, '3-10');
    await _pumpMap(t, services);
    expect(services.progress.endingSeen, isFalse);

    await _pushLevelComplete(t, services, '3-10');
    await _tapAndSettle(t, find.text('Levels'));
    expect(find.text('Thanks for playing.'), findsOneWidget);
    await _tapAndSettle(t, find.byKey(_skipKey));
    expect(find.byType(StoryCardScreen), findsNothing);
    expect(find.byType(LevelCompleteScreen), findsNothing);
    expect(_map, findsOneWidget);
    expect(services.progress.endingSeen, isTrue);

    await _pushLevelComplete(t, services, '3-10');
    await _tapAndSettle(t, find.text('Levels'));
    expect(find.text('Thanks for playing.'), findsNothing);
    expect(find.byType(LevelCompleteScreen), findsNothing);
    expect(_map, findsOneWidget);
  });

  testWidgets('Levels on an earlier level shows no ending', (t) async {
    final services = await _services(t);
    await _pumpMap(t, services);
    await _pushLevelComplete(t, services, '1-01');
    await _tapAndSettle(t, find.text('Levels'));
    expect(find.byType(StoryCardScreen), findsNothing);
    expect(_map, findsOneWidget);
    expect(services.progress.endingSeen, isFalse);
  });

  testWidgets('the card calls onDone exactly once', (t) async {
    var done = 0;
    await t.pumpWidget(
      MaterialApp(
        home: StoryCardScreen(
          title: 'Title',
          lines: const ['One', 'Two'],
          onDone: () => done++,
        ),
      ),
    );
    await t.tap(find.byType(StoryCardScreen));
    await t.pump(_frame);
    expect(done, 0);
    await t.tap(find.byType(StoryCardScreen));
    await t.pump(_frame);
    expect(done, 1);
    await t.tap(find.byType(StoryCardScreen));
    await t.tap(find.byKey(_skipKey));
    await t.pump(_frame);
    expect(done, 1);
  });

  testWidgets('card text wraps at 320 px', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final story = (await t.runAsync(
      StoryRepository(PlatformAssetBundle()).load,
    ))!;
    final chapter = story.chapters[1]!;
    await t.pumpWidget(
      MaterialApp(
        home: StoryCardScreen(
          title: chapter.title,
          lines: chapter.lines,
          onDone: () {},
        ),
      ),
    );
    for (var i = 0; i < chapter.lines.length - 1; i++) {
      await t.tap(find.byType(StoryCardScreen));
      await t.pump(_frame);
    }
    expect(t.takeException(), isNull);
    expect(find.text(chapter.lines.last), findsOneWidget);
    expect(find.byKey(_skipKey), findsOneWidget);
  });

  testWidgets('Play on a fresh install shows the card, then 1-01', (t) async {
    final services = await _services(t);
    await t.pumpWidget(MaterialApp(home: HomeScreen(services: services)));
    await _tapAndSettle(t, find.text('Play'));
    expect(find.text('The Outskirts'), findsOneWidget);
    await _tapAndSettle(t, find.byKey(_skipKey));
    expect(t.widget<GameScreen>(find.byType(GameScreen)).levelId, '1-01');
  });

  testWidgets('two quick taps on Play stack one card', (t) async {
    final services = await _services(t);
    await t.pumpWidget(MaterialApp(home: HomeScreen(services: services)));
    await t.tap(find.text('Play'));
    await t.pump(const Duration(milliseconds: 10));
    await t.tap(find.text('Play'), warnIfMissed: false);
    await t.pump(_frame);
    await _settle(t);
    expect(find.text('The Outskirts'), findsOneWidget);
    expect(find.byType(CityMapScreen, skipOffstage: false), findsOneWidget);
    await _tapAndSettle(t, find.byKey(_skipKey));
    expect(find.byType(GameScreen), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(StoryCardScreen), findsNothing);
    expect(find.byType(GameScreen), findsNothing);
    expect(_map, findsOneWidget);
  });

  testWidgets('Back on the ending card still marks it seen', (t) async {
    final services = await _services(t);
    await _pumpMap(t, services);
    await _pushLevelComplete(t, services, '3-10');
    await _tapAndSettle(t, find.text('Levels'));
    expect(find.text('Thanks for playing.'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(services.progress.endingSeen, isTrue);
  });
}

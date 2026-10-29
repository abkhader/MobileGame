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
  AssetBundle? storyBundle,
}) async {
  SharedPreferences.setMockInitialValues({});
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
    ads: FakeAdService(),
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

Future<void> _pumpMap(WidgetTester t, AppServices services) async {
  await t.pumpWidget(MaterialApp(home: CityMapScreen(services: services)));
  await _settle(t);
}

/// The Power Lines card's first line.
const _powerLinesLine =
    "The Core is awake, but its power can't reach the city.";

/// A view tall enough to show every district at once.
void _tallView(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2600);
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
      await services.progress.recordWin(id, score: 1, best: 1, sparkMask: 0x7);
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
    await t.runAsync(
      () =>
          services.progress.recordWin('1-01', score: 1, best: 1, sparkMask: 0),
    );
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

  testWidgets('The Power Lines replays the ending once seen and earned', (
    t,
  ) async {
    _tallView(t);
    final services = await _services(t);
    await _completeChapter(t, services, 4);
    await t.runAsync(() => services.progress.markEndingSeen('4-10'));
    await _pumpMap(t, services);
    await t.tap(find.text('The Power Lines'));
    await _settle(t);
    expect(find.text('Thanks for playing.', skipOffstage: false), findsOne);
    expect(find.text(_powerLinesLine), findsNothing);
  });

  testWidgets('The Power Lines shows its card while the ending is unseen', (
    t,
  ) async {
    _tallView(t);
    final services = await _services(t);
    await _completeChapter(t, services, 4);
    await _pumpMap(t, services);
    await t.tap(find.text('The Power Lines'));
    await _settle(t);
    expect(find.text(_powerLinesLine), findsOneWidget);
    expect(find.text('Thanks for playing.', skipOffstage: false), findsNothing);
  });

  testWidgets('The Power Lines shows its card while incomplete', (t) async {
    _tallView(t);
    final services = await _services(t);
    await t.runAsync(() => services.progress.markEndingSeen('4-10'));
    await _pumpMap(t, services);
    await t.tap(find.text('The Power Lines'));
    await _settle(t);
    expect(find.text(_powerLinesLine), findsOneWidget);
    expect(find.text('Thanks for playing.', skipOffstage: false), findsNothing);
  });

  testWidgets('The Core is no longer last: it always replays its card', (
    t,
  ) async {
    _tallView(t);
    final services = await _services(t);
    await _completeChapter(t, services, 3);
    await t.runAsync(() => services.progress.markEndingSeen('4-10'));
    await _pumpMap(t, services);
    await t.tap(find.text('The Core'));
    await _settle(t);
    expect(find.text('The Core powers the whole city.'), findsOneWidget);
    expect(find.text('Thanks for playing.', skipOffstage: false), findsNothing);
  });

  testWidgets('one district per bundled chapter, 3 sparks per level', (
    t,
  ) async {
    _tallView(t);
    final services = await _services(t);
    final ids = (await t.runAsync(services.levels.levelIds))!;
    final chapters = {for (final id in ids) id.split('-').first};
    expect(chapters, {'1', '2', '3', '4'});
    await _pumpMap(t, services);
    for (final title in [
      'The Outskirts',
      'The Market',
      'The Core',
      'The Power Lines',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.bySemanticsLabel('Level 31, locked'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 40, locked'), findsOneWidget);
    expect(ids.length * 3, 120);
    expect(find.text('0 / 120'), findsOneWidget);
  });

  for (final size in const [Size(320, 640), Size(360, 800)]) {
    testWidgets('every district fits ${size.width.toInt()} px, no sideways '
        'scroll', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final services = await _services(t);
      final ids = (await t.runAsync(services.levels.levelIds))!;
      await _pumpMap(t, services);
      expect(t.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.horizontal,
        ),
        findsNothing,
      );
      for (final id in ids) {
        final target = find.byKey(ValueKey('building-$id'));
        expect(target, findsOneWidget, reason: id);
        final rect = t.getRect(target);
        expect(rect.width, greaterThanOrEqualTo(28), reason: id);
        expect(rect.height, greaterThanOrEqualTo(88), reason: id);
        expect(rect.left, greaterThanOrEqualTo(0), reason: id);
        expect(rect.right, lessThanOrEqualTo(size.width), reason: id);
      }
    });
  }

  testWidgets('a broken story falls back to chapter titles', (t) async {
    _tallView(t);
    final services = await _services(t, storyBundle: _BrokenStoryBundle());
    await _pumpMap(t, services);
    for (final title in ['Chapter 1', 'Chapter 2', 'Chapter 3', 'Chapter 4']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('The Outskirts'), findsNothing);
  });
}

import 'package:echo_app/ads/ad_service.dart';
import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_app/game/echo_board.dart';
import 'package:echo_app/screens/game_screen.dart';
import 'package:echo_app/screens/home_screen.dart';
import 'package:echo_app/screens/level_complete_screen.dart';
import 'package:flame/game.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';
import 'support/flow_input.dart';
import 'support/story_flags.dart';

const _frame = Duration(milliseconds: 200);
const _noAd = 'No ad available right now, try again later.';

/// Records the arguments it is asked about and always says yes.
class _AlwaysPolicy extends AdPolicy {
  final calls = <({int completed, int number})>[];

  @override
  bool shouldShowInterstitial({
    required int completedThisSession,
    required int levelNumber,
  }) {
    calls.add((completed: completedThisSession, number: levelNumber));
    return true;
  }
}

Future<AppServices> _services(
  WidgetTester t,
  FakeAdService ads, {
  AdPolicy policy = const AdPolicy(),
}) async {
  SharedPreferences.setMockInitialValues(await introsSeenPrefs(t));
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
    ads: ads,
    audio: const SilentAudioService(),
    story: StoryRepository(PlatformAssetBundle()),
    adPolicy: policy,
  );
}

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await t.pump(_frame);
  await t.pump(_frame);
}

Future<void> _pumpGame(WidgetTester t, AppServices s, String id) async {
  await t.pumpWidget(
    MaterialApp(
      home: GameScreen(services: s, levelId: id),
    ),
  );
  await _settle(t);
}

EchoBoard _echoBoard(WidgetTester t) => t
    .widget<GameWidget<EchoBoard>>(
      find.byWidgetPredicate((w) => w is GameWidget),
    )
    .game!;

Future<void> _skip(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.more_vert));
  await t.pump(_frame);
  await t.pump(const Duration(milliseconds: 500));
  await t.tap(find.text('Skip level'));
  await t.pump(_frame);
  await t.pump(_frame);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Hint with a failed ad shows the snackbar and no path', (
    t,
  ) async {
    final ads = FakeAdService()..rewardResult = false;
    await _pumpGame(t, await _services(t, ads), '1-01');
    await t.tap(find.text('Hint'));
    await t.pump(_frame);
    expect(find.text(_noAd), findsOneWidget);
    expect(ads.rewardedShown, 1);
    expect(_echoBoard(t).hintSteps, isNull);
  });

  testWidgets('Hint with a rewarded ad sets the path', (t) async {
    final ads = FakeAdService();
    await _pumpGame(t, await _services(t, ads), '1-01');
    await t.tap(find.text('Hint'));
    await t.pump(_frame);
    expect(_echoBoard(t).hintSteps, isNotNull);
    expect(_echoBoard(t).hintSteps!.length, 4);
    expect(find.text(_noAd), findsNothing);
  });

  testWidgets('Skip level with a failed ad stays put and records nothing', (
    t,
  ) async {
    final ads = FakeAdService()..rewardResult = false;
    final services = await _services(t, ads);
    await _pumpGame(t, services, '1-01');
    await _skip(t);
    expect(find.text(_noAd), findsOneWidget);
    expect(services.progress.progressOf('1-01').completed, isFalse);
    expect(t.widget<GameScreen>(find.byType(GameScreen)).levelId, '1-01');
  });

  testWidgets('Skip level on level 1 opens level 2 with 0 stars', (t) async {
    final ads = FakeAdService();
    final services = await _services(t, ads);
    await _pumpGame(t, services, '1-01');
    await _skip(t);
    await _settle(t);
    expect(t.widget<GameScreen>(find.byType(GameScreen)).levelId, '1-02');
    final p = services.progress.progressOf('1-01');
    expect(p.completed, isTrue);
    expect(p.stars, 0);
  });

  testWidgets('completing level 1 and tapping Next shows no interstitial', (
    t,
  ) async {
    final ads = FakeAdService();
    await _pumpGame(t, await _services(t, ads), '1-01');
    // Level 1-01 is won by holding right for four beats.
    await holdKey(t, LogicalKeyboardKey.arrowRight, const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Level complete'), findsOneWidget);
    await t.tap(find.text('Next'));
    await _settle(t);
    expect(ads.interstitialsShown, 0);
    expect(t.widget<GameScreen>(find.byType(GameScreen)).levelId, '1-02');
  });

  testWidgets('leaving Level Complete consults the policy and shows the ad', (
    t,
  ) async {
    final ads = FakeAdService();
    final policy = _AlwaysPolicy();
    final services = await _services(t, ads, policy: policy)
      ..completedThisSession = 3;
    await t.pumpWidget(
      MaterialApp(
        home: LevelCompleteScreen(
          services: services,
          levelId: '1-02',
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
    await _settle(t);
    await t.tap(find.text('Next'));
    await _settle(t);
    expect(policy.calls, [(completed: 3, number: 2)]);
    expect(ads.interstitialsShown, 1);
  });

  testWidgets('hint path refreshes when the run changes', (t) async {
    final services = await _services(t, FakeAdService());
    await _pumpGame(t, services, '1-03');
    await t.tap(find.text('Hint'));
    await t.pump(_frame);
    expect(_echoBoard(t).hintSteps!.map((e) => e.move), [Move.right]);
    await tapKey(t, LogicalKeyboardKey.arrowRight);
    await t.tap(find.text('New echo · 1 left'));
    await t.pump(_frame);
    expect(find.bySemanticsLabel('Run 2 of 2'), findsOneWidget);
    final steps = _echoBoard(t).hintSteps!;
    expect(steps, hasLength(4));
    expect(steps.last.to, const Position(5, 1));
  });

  testWidgets('hint survives Restart and the mismatch note follows ghosts', (
    t,
  ) async {
    const note =
        'Hints follow the best solution. Restart the level to match them.';
    await _pumpGame(t, await _services(t, FakeAdService()), '1-03');
    await t.tap(find.text('Hint'));
    await t.pump(_frame);
    expect(find.text(note), findsNothing);
    await tapKey(t, LogicalKeyboardKey.space);
    await t.tap(find.text('New echo · 1 left'));
    await t.pump(_frame);
    expect(find.text(note), findsOneWidget);
    await t.tap(find.text('Restart'));
    await t.pump(_frame);
    expect(find.bySemanticsLabel('Run 1 of 2'), findsOneWidget);
    expect(find.text(note), findsNothing);
    expect(_echoBoard(t).hintSteps, isNotNull);
  });

  testWidgets('Skip on the last level returns to the existing map', (t) async {
    final ads = FakeAdService();
    final services = await _services(t, ads);
    final ids = (await t.runAsync(services.levels.levelIds))!;
    final last = ids.last;
    // Unlock the last level by completing every earlier one.
    await t.runAsync(() async {
      for (final id in ids.take(ids.length - 1)) {
        await services.progress.recordWin(
          id,
          score: 1,
          best: 1,
          sparkMask: 0x7,
        );
      }
    });
    await t.pumpWidget(MaterialApp(home: HomeScreen(services: services)));
    await t.tap(find.text('Map'));
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    await _settle(t);
    final n = levelNumber(ids, last);
    final building = find.bySemanticsLabel('Level $n, open');
    // The last building sits below the 800x600 test viewport, outside the
    // semantics tree until it scrolls into view.
    await t.scrollUntilVisible(
      building,
      200,
      // The map's vertical scroll, its only scrollable.
      scrollable: find.byType(Scrollable),
    );
    await t.pump(_frame);
    await t.tap(building);
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    await _settle(t);
    expect(t.widget<GameScreen>(find.byType(GameScreen)).levelId, last);
    await _skip(t);
    await _settle(t);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('Lumen City'), findsOneWidget);
    expect(services.progress.progressOf(last).completed, isTrue);
    // A skipped level is solved with no stars.
    expect(find.bySemanticsLabel('Level $n, solved, 0 stars'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Lumen City'), findsNothing);
    expect(find.text('Play'), findsOneWidget);
  });
}

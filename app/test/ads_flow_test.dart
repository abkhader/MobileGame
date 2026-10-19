import 'package:echo_app/ads/ad_service.dart';
import 'package:echo_app/app_services.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/game/echo_board.dart';
import 'package:echo_app/screens/game_screen.dart';
import 'package:echo_app/screens/level_complete_screen.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';

const _frame = Duration(milliseconds: 200);
const _noAd = 'No ad available right now, try again later.';
final _board = find.byKey(const Key('board'));

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
  SharedPreferences.setMockInitialValues({});
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
    ads: ads,
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
    expect(_echoBoard(t).hintPath, isNull);
  });

  testWidgets('Hint with a rewarded ad sets the path', (t) async {
    final ads = FakeAdService();
    await _pumpGame(t, await _services(t, ads), '1-01');
    await t.tap(find.text('Hint'));
    await t.pump(_frame);
    expect(_echoBoard(t).hintPath, isNotNull);
    expect(_echoBoard(t).hintPath!.length, 5);
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
    for (var i = 0; i < 4; i++) {
      await t.fling(_board, const Offset(300, 0), 1000);
      await t.pump(_frame);
    }
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
          stars: 3,
        ),
      ),
    );
    await _settle(t);
    await t.tap(find.text('Next'));
    await _settle(t);
    expect(policy.calls, [(completed: 3, number: 2)]);
    expect(ads.interstitialsShown, 1);
  });
}

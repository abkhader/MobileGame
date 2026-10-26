import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_app/screens/level_complete_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';

const _frame = Duration(milliseconds: 200);

LevelProgress _p({bool moves = false, int sparks = 0, bool finished = true}) =>
    LevelProgress(
      completed: true,
      finished: finished,
      sparkMask: sparks,
      movesStar: moves,
    );

Future<AppServices> _services(WidgetTester t, {bool reduce = false}) async {
  SharedPreferences.setMockInitialValues({});
  final progress = (await t.runAsync(ProgressRepository.open))!;
  if (reduce) await t.runAsync(() => progress.setReduceEffects(true));
  return AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
    ads: FakeAdService(),
    audio: const SilentAudioService(),
    story: StoryRepository(PlatformAssetBundle()),
  );
}

Future<void> _pump(
  WidgetTester t, {
  required LevelProgress before,
  required LevelProgress after,
  int best = 16,
  bool reduce = false,
}) async {
  final services = await _services(t, reduce: reduce);
  await t.pumpWidget(
    MaterialApp(
      home: LevelCompleteScreen(
        services: services,
        levelId: '1-02',
        score: 20,
        best: best,
        before: before,
        after: after,
      ),
    ),
  );
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await t.pump(_frame);
}

Finder _fly(int i) => find.byKey(ValueKey('goal-fly-$i'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('newlyEarnedGoals compares goal by goal', () {
    expect(newlyEarnedGoals(const LevelProgress(), _p(sparks: 7)), [
      true,
      true,
      false,
    ]);
    expect(newlyEarnedGoals(_p(sparks: 7), _p(sparks: 7, moves: true)), [
      false,
      false,
      true,
    ]);
    expect(newlyEarnedGoals(_p(sparks: 7), _p(sparks: 7)), [
      false,
      false,
      false,
    ]);
  });

  testWidgets('first win with one spark: Finished flies in, sparks not yet', (
    t,
  ) async {
    final sem = t.ensureSemantics();
    await _pump(t, before: const LevelProgress(), after: _p(sparks: 1));
    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('All 3 sparks (1/3)'), findsOneWidget);
    expect(find.text('In 16 moves or fewer'), findsOneWidget);
    expect(find.bySemanticsLabel('Finished, earned'), findsOneWidget);
    expect(find.bySemanticsLabel('All 3 sparks, 1 of 3'), findsOneWidget);
    expect(
      find.bySemanticsLabel('In 16 moves or fewer, not yet'),
      findsOneWidget,
    );
    expect(_fly(0), findsOneWidget);
    expect(_fly(1), findsNothing);
    expect(_fly(2), findsNothing);
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byIcon(Icons.star_border), findsNWidgets(2));
    expect(find.text('Score 20 · Best 16'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    sem.dispose();
  });

  testWidgets('a later win with all sparks drops the count', (t) async {
    await _pump(t, before: _p(sparks: 1), after: _p(sparks: 7, moves: true));
    expect(find.text('All 3 sparks'), findsOneWidget);
    expect(find.textContaining('(3/3)'), findsNothing);
    expect(_fly(0), findsNothing);
    expect(_fly(1), findsOneWidget);
    expect(_fly(2), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNWidgets(3));
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('stars already earned appear lit without animating', (t) async {
    final state = _p(sparks: 7, moves: true);
    await _pump(t, before: state, after: state);
    for (var i = 0; i < 3; i++) {
      expect(_fly(i), findsNothing);
    }
    expect(find.byIcon(Icons.star), findsNWidgets(3));
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('the fly-in scales and fades; reduced effects only fades', (
    t,
  ) async {
    await _pump(t, before: const LevelProgress(), after: _p());
    expect(
      find.descendant(of: _fly(0), matching: find.byType(ScaleTransition)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _fly(0), matching: find.byType(FadeTransition)),
      findsOneWidget,
    );
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('reduced effects fade the new star in with no scale', (t) async {
    await _pump(t, before: const LevelProgress(), after: _p(), reduce: true);
    expect(_fly(0), findsOneWidget);
    expect(
      find.descendant(of: _fly(0), matching: find.byType(ScaleTransition)),
      findsNothing,
    );
    expect(
      find.descendant(of: _fly(0), matching: find.byType(FadeTransition)),
      findsOneWidget,
    );
    await t.pump(const Duration(seconds: 1));
  });
}

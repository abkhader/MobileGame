import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/art/skyline.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_app/screens/city_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';

const _frame = Duration(milliseconds: 200);

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

/// Saves [n] sparks over the first levels (3 each, the rest on the last).
Future<void> _saveSparks(WidgetTester t, AppServices s, int n) async {
  final ids = (await t.runAsync(s.levels.levelIds))!;
  await t.runAsync(() async {
    var left = n;
    for (final id in ids) {
      if (left <= 0) break;
      final k = left >= 3 ? 3 : left;
      await s.progress.recordWin(
        id,
        score: 99,
        best: 1,
        sparkMask: (1 << k) - 1,
      );
      left -= k;
    }
  });
}

Future<void> _pumpMap(WidgetTester t, AppServices s) async {
  await t.pumpWidget(MaterialApp(home: CityMapScreen(services: s)));
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await t.pump(_frame);
  await t.pump(const Duration(milliseconds: 500));
}

String _badge(String name, int at, bool reached) =>
    '$name, $at sparks, ${reached ? 'reached' : 'locked'}, coming soon';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('header total counts every saved spark out of 3 per level', (
    t,
  ) async {
    final sem = t.ensureSemantics();
    final s = await _services(t);
    await _saveSparks(t, s, 14);
    await _pumpMap(t, s);
    expect(s.progress.totalSparks, 14);
    // Derived from the bundled levels, not hard-coded.
    final of = (await t.runAsync(s.levels.levelIds))!.length * 3;
    expect(
      find.bySemanticsLabel('Sparks collected, 14 of $of'),
      findsOneWidget,
    );
    expect(find.text('14 / $of'), findsOneWidget);
    // Drawn, never the glyph.
    expect(find.textContaining('✦'), findsNothing);
    sem.dispose();
  });

  for (final (sparks, dash, burst, swap, freeze) in [
    (14, false, false, false, false),
    (15, true, false, false, false),
    (35, true, true, false, false),
    (54, true, true, false, false),
    (55, true, true, true, false),
    (74, true, true, true, false),
    (75, true, true, true, true),
  ]) {
    testWidgets('badge states at $sparks sparks', (t) async {
      final sem = t.ensureSemantics();
      final s = await _services(t);
      await _saveSparks(t, s, sparks);
      await _pumpMap(t, s);
      expect(find.bySemanticsLabel(_badge('Dash', 15, dash)), findsOneWidget);
      expect(
        find.bySemanticsLabel(_badge('Light burst', 35, burst)),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(_badge('Swap', 55, swap)), findsOneWidget);
      expect(
        find.bySemanticsLabel(_badge('Freeze', 75, freeze)),
        findsOneWidget,
      );
      expect(find.text('Coming soon'), findsNWidgets(4));
      sem.dispose();
    });
  }

  testWidgets('tapping a badge explains its threshold', (t) async {
    final sem = t.ensureSemantics();
    final s = await _services(t);
    await _pumpMap(t, s);
    await t.tap(find.byKey(const ValueKey('badge-Swap')));
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    expect(
      find.bySemanticsLabel(
        'Swap unlocks at 55 sparks. Collect sparks to power Pip.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Collect sparks to power Pip.'), findsOneWidget);
    sem.dispose();
  });

  testWidgets('building windows follow the kept stars', (t) async {
    final sem = t.ensureSemantics();
    final s = await _services(t);
    await t.runAsync(() async {
      // Finished + all sparks, too slow: 2 stars.
      await s.progress.recordWin('1-01', score: 9, best: 5, sparkMask: 7);
      // Finished + moves, no sparks: 2 stars.
      await s.progress.recordWin('1-02', score: 5, best: 5, sparkMask: 0);
      // Everything: 3 stars.
      await s.progress.recordWin('1-03', score: 5, best: 5, sparkMask: 7);
      // Finished only: 1 star.
      await s.progress.recordWin('1-04', score: 9, best: 5, sparkMask: 1);
      await s.progress.recordSkip('1-05');
    });
    await _pumpMap(t, s);
    expect(find.bySemanticsLabel('Level 1, solved, 2 stars'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 2, solved, 2 stars'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 3, solved, 3 stars'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 4, solved, 1 stars'), findsOneWidget);
    expect(find.bySemanticsLabel('Level 5, solved, 0 stars'), findsOneWidget);
    sem.dispose();
  });

  test('spark lights: one per collected spark, deterministic, in bounds', () {
    const size = Size(300, 148);
    final buildings = [
      const Building(state: BuildingState.solved, stars: 3, sparkMask: 7),
      const Building(state: BuildingState.solved, stars: 1, sparkMask: 1),
      const Building(state: BuildingState.solved, stars: 2, sparkMask: 5),
      const Building(state: BuildingState.open),
      const Building(state: BuildingState.locked),
    ];
    final lights = skylineSparkLights(size, buildings, seed: 2);
    expect(lights.length, 3 + 1 + 2);
    expect(skylineSparkLights(size, buildings, seed: 2), lights);
    for (final p in lights) {
      expect(p.dx, inInclusiveRange(0, size.width));
      expect(p.dy, inInclusiveRange(0, size.height));
    }
    expect(skylineSparkLights(size, const [], seed: 2), isEmpty);
    // More progress, more lights; the same spark keeps its place.
    final more = skylineSparkLights(size, [
      const Building(state: BuildingState.solved, sparkMask: 3),
    ]);
    final fewer = skylineSparkLights(size, [
      const Building(state: BuildingState.solved, sparkMask: 1),
    ]);
    expect(more.first, fewer.first);
  });

  test('the map skyline repaints when only a spark mask changes', () {
    const a = [Building(state: BuildingState.solved, stars: 1, sparkMask: 1)];
    const b = [Building(state: BuildingState.solved, stars: 1, sparkMask: 3)];
    final old = skylinePainterForTest(a, 0);
    expect(skylinePainterForTest(b, 0).shouldRepaint(old), isTrue);
    expect(skylinePainterForTest(a, 0).shouldRepaint(old), isFalse);
  });

  test('buildingsFor carries the saved spark mask', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await ProgressRepository.open();
    await p.recordWin('1-01', score: 9, best: 5, sparkMask: 5);
    final b = buildingsFor(['1-01', '1-02'], p);
    expect(b[0].sparkMask, 5);
    expect(b[1].sparkMask, 0);
  });
}

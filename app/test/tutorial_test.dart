import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_app/screens/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';
import 'support/flow_input.dart';
import 'support/story_flags.dart';

const _frame = Duration(milliseconds: 200);
final _thumb = find.byKey(const Key('thumb-hint'));

Future<AppServices> _services(WidgetTester t) async {
  SharedPreferences.setMockInitialValues(introsSeenPrefs());
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
    ads: FakeAdService(),
    audio: const SilentAudioService(),
    story: StoryRepository(PlatformAssetBundle()),
  );
}

Future<void> _pumpGame(
  WidgetTester t,
  String id, {
  bool reduceMotion = false,
}) async {
  final services = await _services(t);
  await t.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        home: GameScreen(services: services, levelId: id),
      ),
    ),
  );
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await t.pump(_frame);
  await t.pump(_frame);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the tutorial tips are the exact strings', () async {
    final repo = LevelRepository(PlatformAssetBundle());
    expect((await repo.load('1-01')).tip, 'Drag anywhere to move Pip.');
    expect(
      (await repo.load('1-02')).tip,
      'Plates open doors, but only while something stands on them.',
    );
    expect(
      (await repo.load('1-03')).tip,
      'Tap New echo. Pip starts over, and your echo repeats every move.',
    );
    expect(
      (await repo.load('1-04')).tip,
      'Hold ⏳ to let time pass while Pip stays still.',
    );
  });

  testWidgets('the thumb hint shows on 1-01 until the first beat', (t) async {
    await _pumpGame(t, '1-01');
    expect(_thumb, findsOneWidget);
    await tapKey(t, LogicalKeyboardKey.arrowRight);
    expect(_thumb, findsNothing);
  });

  testWidgets('the thumb hint stays gone after rewinding to the start', (
    t,
  ) async {
    await _pumpGame(t, '1-01');
    await tapKey(t, LogicalKeyboardKey.arrowRight);
    await tapKey(t, LogicalKeyboardKey.backspace);
    expect(_thumb, findsNothing);
  });

  testWidgets('no thumb hint under reduce motion or on other levels', (
    t,
  ) async {
    await _pumpGame(t, '1-01', reduceMotion: true);
    expect(_thumb, findsNothing);
    await t.pumpWidget(const SizedBox());
    await _pumpGame(t, '1-02');
    expect(_thumb, findsNothing);
  });
}

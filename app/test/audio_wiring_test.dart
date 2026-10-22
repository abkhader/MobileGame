import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_app/screens/game_screen.dart';
import 'package:echo_app/screens/home_screen.dart';
import 'package:echo_app/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';
import 'support/story_flags.dart';
import 'support/fake_audio_service.dart';

const _frame = Duration(milliseconds: 200);
final _board = find.byKey(const Key('board'));

Future<AppServices> _services(
  WidgetTester t,
  AudioService audio, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
    ads: FakeAdService(),
    audio: audio,
    story: StoryRepository(PlatformAssetBundle()),
  );
}

Future<void> _pumpGame(WidgetTester t, AppServices s) async {
  await t.pumpWidget(
    MaterialApp(
      home: GameScreen(services: s, levelId: '1-01', onWon: (_) {}),
    ),
  );
  await t.pump(_frame);
  await t.pump(_frame);
}

Future<void> _swipe(WidgetTester t) async {
  await t.fling(_board, const Offset(300, 0), 1000);
  await t.pump(_frame);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a swipe on 1-01 plays move', (t) async {
    final audio = FakeAudioService();
    await _pumpGame(t, await _services(t, audio));
    await _swipe(t);
    expect(audio.played, [Sfx.move]);
  });

  testWidgets('winning 1-01 plays win', (t) async {
    final audio = FakeAudioService();
    await _pumpGame(t, await _services(t, audio));
    for (var i = 0; i < 4; i++) {
      await _swipe(t);
    }
    expect(audio.played.last, Sfx.win);
    expect(audio.played, contains(Sfx.win));
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('with sfxOn false a swipe plays nothing', (t) async {
    final audio = FakeAudioService();
    await _pumpGame(
      t,
      await _services(
        t,
        audio,
        prefs: {ProgressRepository.storageKey: '{"sfxOn":false}'},
      ),
    );
    await _swipe(t);
    expect(audio.played, isEmpty);
  });

  testWidgets('the Music switch stops and starts music', (t) async {
    final audio = FakeAudioService();
    final services = await _services(t, audio);
    await t.pumpWidget(MaterialApp(home: SettingsScreen(services: services)));
    final music = find.widgetWithText(SwitchListTile, 'Music');
    await t.tap(music);
    await t.pump(_frame);
    expect(audio.stopMusicCalls, 1);
    await t.tap(music);
    await t.pump(_frame);
    expect(audio.startMusicCalls, 1);
  });

  testWidgets('Home does not start music when musicOn is false', (t) async {
    final audio = FakeAudioService();
    final services = await _services(
      t,
      audio,
      prefs: {ProgressRepository.storageKey: '{"musicOn":false}'},
    );
    await t.pumpWidget(MaterialApp(home: HomeScreen(services: services)));
    await t.pump(_frame);
    await t.tap(find.text('Play'));
    await t.pump(const Duration(milliseconds: 500));
    expect(audio.startMusicCalls, 0);
  });

  testWidgets('opening a level retries startMusic when music is on', (t) async {
    final audio = FakeAudioService();
    await _pumpGame(t, await _services(t, audio));
    expect(audio.startMusicCalls, 1);
  });

  testWidgets('with sfxOn false plate, door and win stay silent too', (
    t,
  ) async {
    final audio = FakeAudioService();
    final services = await _services(
      t,
      audio,
      prefs: {ProgressRepository.storageKey: '{"sfxOn":false}'},
    );
    await t.pumpWidget(
      MaterialApp(
        home: GameScreen(services: services, levelId: '1-02', onWon: (_) {}),
      ),
    );
    await t.pump(_frame);
    await t.pump(_frame);
    for (var i = 0; i < 4; i++) {
      await _swipe(t);
    }
    expect(audio.played, isEmpty);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('a failing audio backend does not break Home', (t) async {
    final audio = FakeAudioService(throws: true);
    final services = await _services(t, audio, prefs: introsSeenPrefs());
    await t.pumpWidget(MaterialApp(home: HomeScreen(services: services)));
    await t.pump(_frame);
    expect(audio.startMusicCalls, 1);
    await t.tap(find.text('Play'));
    await t.pump(_frame);
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(_frame);
    await t.pump(const Duration(milliseconds: 500));
    // Home start, the Play tap, and the opened level's own retry.
    expect(audio.startMusicCalls, 3);
    expect(t.widget<GameScreen>(find.byType(GameScreen)).levelId, '1-01');
    expect(t.takeException(), isNull);
  });

  testWidgets('a failing audio backend does not break the Game screen', (
    t,
  ) async {
    final audio = FakeAudioService(throws: true);
    await _pumpGame(t, await _services(t, audio));
    await _swipe(t);
    expect(find.text('Moves 1'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

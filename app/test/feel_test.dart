import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_app/game/haptics.dart';
import 'package:echo_app/screens/game_screen.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';
import 'support/fake_audio_service.dart';
import 'support/flow_input.dart';

const _frame = Duration(milliseconds: 200);
final _tint = find.byKey(const Key('frozen-tint'));
final _shimmer = find.byKey(const Key('rewind-shimmer'));

Future<AppServices> _services(
  WidgetTester t,
  AudioService audio, {
  Map<String, Object?> settings = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    ProgressRepository.storageKey: [
      '{',
      [for (final e in settings.entries) '"${e.key}":${e.value}'].join(','),
      '}',
    ].join(),
  });
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
    ads: FakeAdService(),
    audio: audio,
    story: StoryRepository(PlatformAssetBundle()),
  );
}

Future<GameScreen> _pumpGame(
  WidgetTester t,
  AppServices s, {
  bool disableAnimations = false,
}) async {
  final screen = GameScreen(services: s, levelId: '1-01', onWon: (_) {});
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: screen,
      ),
    ),
  );
  await t.pump(_frame);
  await t.pump(_frame);
  return screen;
}

double _tintOpacity(WidgetTester t) => t
    .widget<AnimatedOpacity>(
      find.ancestor(of: _tint, matching: find.byType(AnimatedOpacity)),
    )
    .opacity;

LogicalKeyboardKey _keyFor(Move m) => switch (m) {
  Move.up => LogicalKeyboardKey.arrowUp,
  Move.down => LogicalKeyboardKey.arrowDown,
  Move.left => LogicalKeyboardKey.arrowLeft,
  _ => LogicalKeyboardKey.arrowRight,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => Haptics.testHook = null);

  group('frozen tint', () {
    testWidgets('shows at start, hides while a move is held', (t) async {
      await _pumpGame(t, await _services(t, FakeAudioService()));
      expect(_tint, findsOneWidget);
      expect(_tintOpacity(t), greaterThan(0));
      await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await t.pump(const Duration(milliseconds: 50));
      expect(_tintOpacity(t), 0);
      await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await settle(t);
      expect(_tintOpacity(t), greaterThan(0));
    });

    testWidgets('never takes pointer input', (t) async {
      await _pumpGame(t, await _services(t, FakeAudioService()));
      expect(
        find.ancestor(of: _tint, matching: find.byType(IgnorePointer)),
        findsWidgets,
      );
    });

    testWidgets('fades in over 250 ms and out over 150 ms', (t) async {
      await _pumpGame(t, await _services(t, FakeAudioService()));
      final fade = t.widget<AnimatedOpacity>(
        find.ancestor(of: _tint, matching: find.byType(AnimatedOpacity)),
      );
      expect(fade.duration, const Duration(milliseconds: 250));
      await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await t.pump(const Duration(milliseconds: 50));
      final out = t.widget<AnimatedOpacity>(
        find.ancestor(of: _tint, matching: find.byType(AnimatedOpacity)),
      );
      expect(out.duration, const Duration(milliseconds: 150));
      await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await settle(t);
    });

    testWidgets('the Reduce effects setting removes it', (t) async {
      await _pumpGame(
        t,
        await _services(
          t,
          FakeAudioService(),
          settings: {'reduceEffects': true},
        ),
      );
      expect(_tint, findsNothing);
    });

    testWidgets('OS reduce motion removes it', (t) async {
      await _pumpGame(
        t,
        await _services(t, FakeAudioService()),
        disableAnimations: true,
      );
      expect(_tint, findsNothing);
    });
  });

  group('audio', () {
    testWidgets('frozen is reported at start and after a release', (t) async {
      final audio = FakeAudioService();
      await _pumpGame(t, await _services(t, audio));
      expect(audio.frozenCalls, [true]);
      await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await t.pump(const Duration(milliseconds: 50));
      expect(audio.frozenCalls, [true, false]);
      await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await settle(t);
      expect(audio.frozenCalls, [true, false, true]);
    });

    testWidgets('rewind is reported only while the rewind key is held', (
      t,
    ) async {
      final audio = FakeAudioService();
      await _pumpGame(t, await _services(t, audio));
      await tapKey(t, LogicalKeyboardKey.arrowRight);
      expect(audio.rewindingCalls, isEmpty);
      await t.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await t.pump(const Duration(milliseconds: 20));
      expect(audio.rewindingCalls, [true]);
      expect(_shimmer, findsOneWidget);
      await t.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await settle(t);
      expect(audio.rewindingCalls, [true, false]);
      expect(_shimmer, findsNothing);
    });

    testWidgets('a failing audio service never breaks the game', (t) async {
      await _pumpGame(t, await _services(t, FakeAudioService(throws: true)));
      await tapKey(t, LogicalKeyboardKey.arrowRight);
      await t.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await t.pump(const Duration(milliseconds: 20));
      await t.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await settle(t);
      expect(t.takeException(), isNull);
    });

    testWidgets('a push plays the bump sound', (t) async {
      final audio = FakeAudioService();
      final screen = await _pumpGame(t, await _services(t, audio));
      final game = t.state<State<GameScreen>>(find.byWidget(screen));
      final c = (game as dynamic).controllerForTesting as dynamic;
      final blocked = [
        Move.up,
        Move.down,
        Move.left,
        Move.right,
      ].firstWhere((m) => c.isBlocked(m) as bool);
      await tapKey(t, _keyFor(blocked));
      expect(audio.played, contains(Sfx.bump));
    });
  });

  group('rewind shimmer', () {
    testWidgets('is off with reduce effects', (t) async {
      final audio = FakeAudioService();
      await _pumpGame(
        t,
        await _services(t, audio, settings: {'reduceEffects': true}),
      );
      await tapKey(t, LogicalKeyboardKey.arrowRight);
      await t.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await t.pump(const Duration(milliseconds: 20));
      expect(_shimmer, findsNothing);
      await t.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await settle(t);
    });
  });

  group('haptics', () {
    Future<List<HapticKind>> run(
      WidgetTester t, {
      Map<String, Object?> settings = const {},
      required Future<void> Function() body,
    }) async {
      final seen = <HapticKind>[];
      Haptics.testHook = seen.add;
      await _pumpGame(
        t,
        await _services(t, FakeAudioService(), settings: settings),
      );
      await body();
      return seen;
    }

    Future<void> pushOnce(WidgetTester t) async {
      final state = t.state<State<GameScreen>>(find.byType(GameScreen));
      final c = (state as dynamic).controllerForTesting as dynamic;
      final blocked = [
        Move.up,
        Move.down,
        Move.left,
        Move.right,
      ].firstWhere((m) => c.isBlocked(m) as bool);
      await tapKey(t, _keyFor(blocked));
    }

    testWidgets('a push gives one light impact', (t) async {
      final seen = await run(t, body: () => pushOnce(t));
      expect(seen, [HapticKind.light]);
    });

    testWidgets('vibration off keeps it silent', (t) async {
      final seen = await run(
        t,
        settings: {'vibration': false},
        body: () => pushOnce(t),
      );
      expect(seen, isEmpty);
    });

    testWidgets('a plain step gives none', (t) async {
      final seen = await run(
        t,
        body: () => tapKey(t, LogicalKeyboardKey.arrowRight),
      );
      expect(seen, isEmpty);
    });

    testWidgets('winning gives a heavy impact', (t) async {
      final seen = await run(
        t,
        body: () async {
          for (var i = 0; i < 4; i++) {
            await tapKey(t, LogicalKeyboardKey.arrowRight);
          }
          await t.pump(const Duration(seconds: 1));
        },
      );
      expect(seen, contains(HapticKind.heavy));
    });

    testWidgets('restart is silent', (t) async {
      final seen = await run(
        t,
        body: () async {
          await t.sendKeyDownEvent(LogicalKeyboardKey.keyR);
          await t.sendKeyUpEvent(LogicalKeyboardKey.keyR);
          await settle(t);
        },
      );
      expect(seen, isEmpty);
    });
  });
}

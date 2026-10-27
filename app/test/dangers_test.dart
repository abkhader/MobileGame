import 'dart:convert';
import 'dart:io';

import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_app/game/echo_board.dart';
import 'package:echo_app/game/game_controller.dart';
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

/// Serves hand-built danger levels as `assets/levels/<id>.json`; every other
/// asset comes from the real bundle.
class _LevelBundle extends CachingAssetBundle {
  _LevelBundle(this.levels);

  final Map<String, Map<String, Object?>> levels;
  final _real = PlatformAssetBundle();

  @override
  Future<ByteData> load(String key) async {
    for (final e in levels.entries) {
      if (key == '${LevelRepository.dir}${e.key}.json') {
        final bytes = utf8.encode(jsonEncode({'id': e.key, ...e.value}));
        return ByteData.sublistView(Uint8List.fromList(bytes));
      }
    }
    return _real.load(key);
  }
}

Map<String, Object?> _lvl(List<String> grid, {int runLimit = 2}) => {
  'name': 'Danger',
  'runLimit': runLimit,
  'grid': grid,
};

final _levels = {
  // Stepping right lands on a laser on its beat.
  't-laser': _lvl(['S1.E']),
  't-laser-last': _lvl(['S1.E'], runLimit: 1),
  // A Shade next to the start: waiting one beat gets Pip caught.
  't-shade': _lvl(['Sx.E']),
  // Run 0 crosses the crack late; in run 1 Pip breaks it first, the echo
  // falls. A Shade far away on the bottom row creeps along all the while.
  't-crack': _lvl(['S~..E.', '#####.', 'x.....']),
  // A Shade at the end of a corridor that chases Pip.
  't-chase': _lvl(['S.....x', '######E']),
};

const _zapped = 'Zapped! Pip rewinds.';
const _rewindTip = 'Echo created. It will repeat every move you just made.';

Future<AppServices> _services(
  WidgetTester t,
  AudioService audio, {
  Map<String, Object?> settings = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    if (settings.isNotEmpty)
      ProgressRepository.storageKey: jsonEncode(settings),
  });
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(_LevelBundle(_levels)),
    progress: progress,
    ads: FakeAdService(),
    audio: audio,
    story: StoryRepository(PlatformAssetBundle()),
  );
}

Future<void> _pumpGame(
  WidgetTester t,
  String id, {
  AudioService? audio,
  Map<String, Object?> settings = const {},
}) async {
  final services = await _services(
    t,
    audio ?? FakeAudioService(),
    settings: settings,
  );
  await t.pumpWidget(
    MaterialApp(
      home: GameScreen(services: services, levelId: id, onWon: (_) {}),
    ),
  );
  await t.pump(const Duration(milliseconds: 200));
  await t.pump(const Duration(milliseconds: 200));
}

dynamic _screen(WidgetTester t) => t.state(find.byType(GameScreen)) as dynamic;

GameController _game(WidgetTester t) =>
    _screen(t).controllerForTesting as GameController;

EchoBoard _board(WidgetTester t) => _screen(t).boardForTesting as EchoBoard;

Future<void> _keys(WidgetTester t, String moves) async {
  for (final c in moves.split('')) {
    await tapKey(t, switch (c) {
      'R' => LogicalKeyboardKey.arrowRight,
      'L' => LogicalKeyboardKey.arrowLeft,
      'U' => LogicalKeyboardKey.arrowUp,
      'D' => LogicalKeyboardKey.arrowDown,
      'E' => LogicalKeyboardKey.keyE,
      _ => LogicalKeyboardKey.space,
    });
  }
}

double _opacityOf(WidgetTester t, String text) => t
    .widget<AnimatedOpacity>(
      find.ancestor(
        of: find.text(text),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => Haptics.testHook = null);

  testWidgets('a laser hit zaps, rewinds Pip and shows the banner', (t) async {
    final audio = FakeAudioService();
    final haptics = <HapticKind>[];
    Haptics.testHook = haptics.add;
    await _pumpGame(t, 't-laser', audio: audio);
    await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
    final game = _game(t);
    expect(game.lastEvent, GameEvent.hit);
    expect(game.state.runIndex, 1);
    expect(game.state.player, const Position(0, 0));
    expect(audio.played, [Sfx.zap]);
    expect(haptics, [HapticKind.heavy]);
    expect(find.text(_zapped), findsOneWidget);
    expect(_opacityOf(t, _zapped), 1);
    expect(
      find.ancestor(
        of: find.text(_zapped),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
    // Not the rewind tip: Pip did not choose this echo.
    expect(find.text(_rewindTip), findsNothing);
    expect(find.text('New echo · 0 left'), findsNothing);
    expect(find.text('Give up'), findsOneWidget);
    // The flash and sparks play where Pip was hit, then settle.
    expect(_board(t).hitBurstActiveForTesting, isTrue);
    // The clock stopped: the next run does not walk on its own.
    await pumpFrames(t, const Duration(milliseconds: 600));
    expect(game.state.tick, 0);
    expect(_board(t).hitBurstActiveForTesting, isFalse);
    // The banner goes after about 2 s.
    await t.pump(const Duration(milliseconds: 1600));
    await t.pump(const Duration(milliseconds: 400));
    expect(_opacityOf(t, _zapped), 0);
  });

  testWidgets('a hit on the last run shows the lost card, no banner', (
    t,
  ) async {
    final audio = FakeAudioService();
    await _pumpGame(t, 't-laser-last', audio: audio);
    await _keys(t, 'R');
    expect(_game(t).state.status, GameStatus.lost);
    expect(find.text('Out of runs'), findsOneWidget);
    expect(find.text(_zapped), findsNothing);
    expect(audio.played, [Sfx.zap]);
  });

  testWidgets('a Shade catch plays the whoomp, not the zap', (t) async {
    final audio = FakeAudioService();
    await _pumpGame(t, 't-shade', audio: audio);
    await _keys(t, 'W');
    expect(_game(t).lastEvent, GameEvent.hit);
    expect(audio.played, [Sfx.shade]);
    expect(find.text(_zapped), findsOneWidget);
  });

  testWidgets('cracked floor crumbles into a hole as Pip leaves it', (t) async {
    final audio = FakeAudioService();
    await _pumpGame(t, 't-crack', audio: audio);
    const crack = Position(1, 0);
    await _keys(t, 'R');
    expect(_board(t).holeDrawnForTesting(crack), isFalse);
    await _keys(t, 'R');
    expect(_game(t).state.holes, {crack});
    expect(audio.played, [Sfx.move, Sfx.move, Sfx.crumble]);
    await pumpFrames(t, const Duration(milliseconds: 500));
    expect(_board(t).holeDrawnForTesting(crack), isTrue);
    expect(_board(t).dustActiveForTesting(crack), isFalse);
  });

  testWidgets('an echo that falls fizzles out, then is gone', (t) async {
    final audio = FakeAudioService();
    await _pumpGame(t, 't-crack', audio: audio);
    await _keys(t, 'WWRRERR');
    expect(_game(t).state.runIndex, 1);
    expect(_board(t).ghostDrawnForTesting(0), isTrue);
    audio.played.clear();
    // One beat, checked while it plays.
    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
    expect(_game(t).state.ghostAlive, [false]);
    expect(audio.played, [Sfx.move, Sfx.echoZap]);
    expect(_board(t).ghostFizzlingForTesting(0), isTrue);
    expect(_board(t).ghostDrawnForTesting(0), isTrue);
    await pumpFrames(t, const Duration(milliseconds: 500));
    expect(_board(t).ghostFizzlingForTesting(0), isFalse);
    expect(_board(t).ghostDrawnForTesting(0), isFalse);
    // No banner for an echo.
    expect(find.text(_zapped), findsNothing);
  });

  testWidgets('rewinding across an echo hit restores echo, floor and Shade', (
    t,
  ) async {
    await _pumpGame(t, 't-crack');
    await _keys(t, 'WWRRER');
    final game = _game(t);
    final atTick1 = game.state;
    await _keys(t, 'RW');
    expect(game.state.ghostAlive, [false]);
    expect(game.state.holes, isNotEmpty);
    expect(game.state.shades, isNot(atTick1.shades));

    // Two rewind beats back to tick 1.
    await tapKey(t, LogicalKeyboardKey.keyZ);
    await tapKey(t, LogicalKeyboardKey.keyZ);
    expect(game.state.tick, 1);
    expect(game.state.player, atTick1.player);
    expect(game.state.ghostAlive, [true]);
    expect(game.state.holes, isEmpty);
    expect(game.state.shades, atTick1.shades);
    await pumpFrames(t, const Duration(milliseconds: 500));
    final board = _board(t);
    expect(board.ghostDrawnForTesting(0), isTrue);
    expect(board.ghostFizzlingForTesting(0), isFalse);
    expect(board.holeDrawnForTesting(const Position(1, 0)), isFalse);
    final shade = atTick1.shades.single;
    expect(
      board.shadeTilesForTesting.single,
      Offset(shade.x.toDouble(), shade.y.toDouble()),
    );
  });

  testWidgets('Shades glide between beats and look toward their next step', (
    t,
  ) async {
    await _pumpGame(t, 't-chase');
    final board = _board(t);
    expect(board.shadeTilesForTesting.single, const Offset(6, 0));
    expect(board.shadeLookForTesting.single, const Offset(-1, 0));
    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
    // Half way through the first beat the Shade is between tiles.
    final x = board.shadeTilesForTesting.single.dx;
    expect(x, greaterThan(5));
    expect(x, lessThan(6));
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
    await settle(t);
    expect(board.shadeTilesForTesting.single, const Offset(5, 0));
  });

  testWidgets('Shades wobble only while time flows, never with reduce '
      'effects', (t) async {
    await _pumpGame(t, 't-chase');
    final board = _board(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await pumpFrames(t, const Duration(milliseconds: 150));
    expect(board.shadeWobbleForTesting, isNot(0));
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
    await settle(t);
    final frozen = board.shadeWobbleForTesting;
    await pumpFrames(t, const Duration(milliseconds: 300));
    expect(board.shadeWobbleForTesting, frozen);

    await t.pumpWidget(const SizedBox());
    await _pumpGame(t, 't-chase', settings: {'reduceEffects': true});
    final reduced = _board(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await pumpFrames(t, const Duration(milliseconds: 150));
    expect(reduced.shadeWobbleForTesting, 0);
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
    await settle(t);
  });

  testWidgets('the engine pauses while frozen with Shades on the board', (
    t,
  ) async {
    await _pumpGame(t, 't-chase');
    await _keys(t, 'W');
    await pumpFrames(t, const Duration(milliseconds: 1500));
    expect(_board(t).paused, isTrue);
  });

  testWidgets('a laser warns once on the beat before it fires', (t) async {
    final audio = FakeAudioService();
    await _pumpGame(t, 't-laser', audio: audio);
    // Beat 1 fires on tick 1: its warning glows from the start, silently.
    expect(_board(t).laserGlowForTesting(const Position(1, 0)), greaterThan(0));
    expect(audio.played, isEmpty);
    await _keys(t, 'W'); // tick 1: firing
    expect(audio.played, [Sfx.move]);
    expect(_board(t).laserGlowForTesting(const Position(1, 0)), 1);
    await _keys(t, 'W'); // tick 2: dark
    expect(_board(t).laserGlowForTesting(const Position(1, 0)), 0);
    await _keys(t, 'W'); // tick 3: warning
    expect(audio.played, [Sfx.move, Sfx.move, Sfx.move, Sfx.laserWarn]);
  });

  testWidgets('dangers never rebuild the static layer during play', (t) async {
    await _pumpGame(t, 't-crack');
    final board = _board(t);
    expect(board.staticBuilds, 1);
    await _keys(t, 'WWRRERRW');
    await pumpFrames(t, const Duration(milliseconds: 500));
    expect(board.staticBuilds, 1);
  });

  test('the danger sounds exist and are licensed', () {
    final license = File('assets/audio/LICENSE.txt').readAsStringSync();
    for (final name in ['zap', 'crumble', 'shade', 'laser_warn']) {
      expect(File('assets/audio/$name.wav').existsSync(), isTrue, reason: name);
      expect(license, contains('$name.wav'));
    }
  });
}

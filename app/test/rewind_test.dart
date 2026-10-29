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
import 'support/banner_finder.dart';
import 'support/flow_input.dart';

const _frame = Duration(milliseconds: 200);
const _tip = 'Echo created. It will repeat every move you just made.';
final _pulse = find.byKey(const Key('new-echo-pulse'));

Future<AppServices> _services(WidgetTester t) async {
  final progress = (await t.runAsync(ProgressRepository.open))!;
  return AppServices(
    levels: LevelRepository(PlatformAssetBundle()),
    progress: progress,
    ads: FakeAdService(),
    audio: const SilentAudioService(),
    story: StoryRepository(PlatformAssetBundle()),
  );
}

Future<void> _pumpGame(WidgetTester t, String levelId) async {
  await t.pumpWidget(
    MaterialApp(
      home: GameScreen(services: await _services(t), levelId: levelId),
    ),
  );
  await t.pump(_frame);
  await t.pump(_frame);
}

/// One wait beat, then the New echo button with the given label.
Future<void> _rewind(WidgetTester t, String label) async {
  await tapKey(t, LogicalKeyboardKey.space);
  await t.tap(find.text(label));
  await t.pump(_frame);
}

/// Lets the banner's timer run out and its fade finish.
Future<void> _letBannerGo(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(seconds: 1));
  }
}

double _bannerOpacity(WidgetTester t) => t
    .widget<AnimatedOpacity>(
      find.ancestor(
        of: find.text(_tip),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

bool _enabled(WidgetTester t, String label) => t
    .widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    )
    .enabled;

int _runIndex(WidgetTester t) =>
    ((t.state(find.byType(GameScreen)) as dynamic).controllerForTesting)
            .state
            .runIndex
        as int;

int _tick(WidgetTester t) =>
    ((t.state(find.byType(GameScreen)) as dynamic).controllerForTesting)
            .state
            .tick
        as int;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('label counts the rewinds left, then turns into Give up', (
    t,
  ) async {
    await _pumpGame(t, '2-03');
    expect(find.text('New echo · 2 left'), findsOneWidget);
    expect(find.byIcon(Icons.people_alt_outlined), findsOneWidget);
    await _rewind(t, 'New echo · 2 left');
    expect(find.text('New echo · 1 left'), findsOneWidget);
    await _rewind(t, 'New echo · 1 left');
    expect(find.text('Give up'), findsOneWidget);
    expect(find.text('New echo · 0 left'), findsNothing);
    expect(find.byIcon(Icons.flag), findsOneWidget);
    expect(find.byIcon(Icons.people_alt_outlined), findsNothing);
  });

  testWidgets('a one-run level always says Give up', (t) async {
    await _pumpGame(t, '1-01');
    expect(find.text('Give up'), findsOneWidget);
    expect(find.byIcon(Icons.flag), findsOneWidget);
  });

  testWidgets('run dots are labelled for screen readers', (t) async {
    await _pumpGame(t, '2-03');
    expect(find.bySemanticsLabel('Run 1 of 3'), findsOneWidget);
    await _rewind(t, 'New echo · 2 left');
    expect(find.bySemanticsLabel('Run 2 of 3'), findsOneWidget);
    expect(find.text('Run 2 / 3'), findsNothing);
  });

  testWidgets('the echo tip shows after the first two rewinds ever only', (
    t,
  ) async {
    await _pumpGame(t, '2-03');
    expect(find.text(_tip), findsNothing);
    await _rewind(t, 'New echo · 2 left');
    expect(find.text(_tip), findsOneWidget);
    expect(_bannerOpacity(t), 1);
    await _letBannerGo(t);
    expect(_bannerOpacity(t), 0);
    await _rewind(t, 'New echo · 1 left');
    expect(_bannerOpacity(t), 1);
    await _letBannerGo(t);

    // A new session reads the count back: the third rewind stays quiet.
    await t.pumpWidget(const SizedBox());
    await _pumpGame(t, '2-03');
    await _rewind(t, 'New echo · 2 left');
    expect(find.text(_tip), findsNothing);
  });

  testWidgets('level 1-03 pulses the button until the first rewind', (t) async {
    await _pumpGame(t, '1-03');
    expect(_pulse, findsOneWidget);
    double scale() => t
        .widget<ScaleTransition>(
          find.descendant(of: _pulse, matching: find.byType(ScaleTransition)),
        )
        .scale
        .value;
    // New echo works at tick 0, but the nudge waits for a first move.
    final still = scale();
    await t.pump(const Duration(milliseconds: 600));
    expect(scale(), still);
    await tapKey(t, LogicalKeyboardKey.space);
    final before = scale();
    await t.pump(const Duration(milliseconds: 600));
    expect(scale(), isNot(before));
    await t.tap(find.text('New echo · 1 left'));
    await t.pump(_frame);
    expect(_pulse, findsNothing);
  });

  testWidgets('1-03 keeps New echo off until the first move', (t) async {
    // The tip says "Tap New echo": a 0-move echo would waste 1-03's only
    // spare run and leave the level unwinnable.
    await _pumpGame(t, '1-03');
    expect(_enabled(t, 'New echo · 1 left'), isFalse);
    await t.tap(find.text('New echo · 1 left'));
    await t.pump(_frame);
    await tapKey(t, LogicalKeyboardKey.keyE);
    expect(_runIndex(t), 0);
    await tapKey(t, LogicalKeyboardKey.space);
    expect(_enabled(t, 'New echo · 1 left'), isTrue);
    // Rewinding back to tick 0 turns it off again.
    await tapKey(t, LogicalKeyboardKey.keyZ);
    expect(_tick(t), 0);
    expect(_enabled(t, 'New echo · 1 left'), isFalse);
  });

  testWidgets('New echo works at tick 0 on a non-tutorial 2-run level', (
    t,
  ) async {
    await _pumpGame(t, '1-06');
    expect(_enabled(t, 'New echo · 1 left'), isTrue);
  });

  testWidgets('no pulse once a rewind is on record, or on other levels', (
    t,
  ) async {
    await _pumpGame(t, '2-03');
    expect(_pulse, findsNothing);
    await _rewind(t, 'New echo · 2 left');
    await t.pumpWidget(const SizedBox());
    await _pumpGame(t, '1-03');
    expect(_pulse, findsNothing);
  });

  testWidgets('the tip is a top banner, not a snack bar', (t) async {
    await _pumpGame(t, '2-03');
    await _rewind(t, 'New echo · 2 left');
    expect(find.byType(SnackBar), findsNothing);
    expect(bannerIgnoresPointer(t, _tip), isTrue);
    final boardTop = t.getTopLeft(board).dy;
    expect(t.getTopLeft(find.text(_tip)).dy - boardTop, lessThan(60));
  });

  testWidgets('the banner hides itself after about 3.5 seconds', (t) async {
    await _pumpGame(t, '2-03');
    await _rewind(t, 'New echo · 2 left');
    await t.pump(const Duration(milliseconds: 3000));
    expect(_bannerOpacity(t), 1);
    await t.pump(const Duration(milliseconds: 700));
    await t.pump(const Duration(milliseconds: 500));
    expect(_bannerOpacity(t), 0);
  });

  testWidgets('the joystick still moves Pip while the banner shows', (t) async {
    await _pumpGame(t, '2-03');
    await _rewind(t, 'New echo · 2 left');
    expect(_bannerOpacity(t), 1);
    expect(_tick(t), 0);
    final stick = await dragJoystick(t, const Offset(60, 0));
    await t.pump(_frame);
    await stick.up();
    await settle(t);
    expect(_tick(t), greaterThan(0));
  });

  testWidgets('leaving the screen cancels the banner timer', (t) async {
    await _pumpGame(t, '2-03');
    await _rewind(t, 'New echo · 2 left');
    await t.pumpWidget(const SizedBox());
    // A pending Timer would fail the test at teardown.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('reduce motion keeps the 1-03 pulse still', (t) async {
    final services = await _services(t);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: GameScreen(services: services, levelId: '1-03'),
        ),
      ),
    );
    await t.pump(_frame);
    await t.pump(_frame);
    await tapKey(t, LogicalKeyboardKey.space);
    await t.pump(const Duration(milliseconds: 600));
    expect(_pulse, findsNothing);
  });
}

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

const _frame = Duration(milliseconds: 200);
const _tip = 'Echo created. It will repeat every move you just made.';
final _board = find.byKey(const Key('board'));
final _pulse = find.byKey(const Key('rewind-pulse'));

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

/// One wait move, then the rewind button with the given label.
Future<void> _rewind(WidgetTester t, String label) async {
  await t.tap(_board);
  await t.pump(_frame);
  await t.tap(find.text(label));
  await t.pump(_frame);
}

/// Lets the snack bar's timer run out and its exit animation finish.
Future<void> _letSnackBarGo(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(seconds: 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('label counts the rewinds left, then turns into Give up', (
    t,
  ) async {
    await _pumpGame(t, '2-03');
    expect(find.text('Rewind · 2 left'), findsOneWidget);
    expect(find.byIcon(Icons.fast_rewind), findsOneWidget);
    await _rewind(t, 'Rewind · 2 left');
    expect(find.text('Rewind · 1 left'), findsOneWidget);
    await _rewind(t, 'Rewind · 1 left');
    expect(find.text('Give up'), findsOneWidget);
    expect(find.text('Rewind · 0 left'), findsNothing);
    expect(find.byIcon(Icons.flag), findsOneWidget);
    expect(find.byIcon(Icons.fast_rewind), findsNothing);
  });

  testWidgets('a one-run level always says Give up', (t) async {
    await _pumpGame(t, '1-01');
    expect(find.text('Give up'), findsOneWidget);
    expect(find.byIcon(Icons.flag), findsOneWidget);
  });

  testWidgets('run dots are labelled for screen readers', (t) async {
    await _pumpGame(t, '2-03');
    expect(find.bySemanticsLabel('Run 1 of 3'), findsOneWidget);
    await _rewind(t, 'Rewind · 2 left');
    expect(find.bySemanticsLabel('Run 2 of 3'), findsOneWidget);
    expect(find.text('Run 2 / 3'), findsNothing);
  });

  testWidgets('the echo tip shows after the first two rewinds ever only', (
    t,
  ) async {
    await _pumpGame(t, '2-03');
    expect(find.text(_tip), findsNothing);
    await _rewind(t, 'Rewind · 2 left');
    expect(find.text(_tip), findsOneWidget);
    await _letSnackBarGo(t);
    expect(find.text(_tip), findsNothing);
    await _rewind(t, 'Rewind · 1 left');
    expect(find.text(_tip), findsOneWidget);
    await _letSnackBarGo(t);

    // A new session reads the count back: the third rewind stays quiet.
    await t.pumpWidget(const SizedBox());
    await _pumpGame(t, '2-03');
    await _rewind(t, 'Rewind · 2 left');
    expect(find.text(_tip), findsNothing);
  });

  testWidgets('level 1-03 pulses the button until the first rewind', (t) async {
    await _pumpGame(t, '1-03');
    expect(_pulse, findsOneWidget);
    await t.tap(_board);
    await t.pump(_frame);
    double scale() => t
        .widget<ScaleTransition>(
          find.descendant(of: _pulse, matching: find.byType(ScaleTransition)),
        )
        .scale
        .value;
    final before = scale();
    await t.pump(const Duration(milliseconds: 600));
    expect(scale(), isNot(before));
    await t.tap(find.text('Rewind · 1 left'));
    await t.pump(_frame);
    expect(_pulse, findsNothing);
  });

  testWidgets('no pulse once a rewind is on record, or on other levels', (
    t,
  ) async {
    await _pumpGame(t, '2-03');
    expect(_pulse, findsNothing);
    await _rewind(t, 'Rewind · 2 left');
    await t.pumpWidget(const SizedBox());
    await _pumpGame(t, '1-03');
    expect(_pulse, findsNothing);
  });
}

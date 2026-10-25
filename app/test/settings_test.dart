import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:echo_app/game/flow_controller.dart';
import 'package:echo_app/game/game_clock.dart';
import 'package:echo_app/game/game_controller.dart';
import 'package:echo_app/screens/settings_screen.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Fast persists and a new FlowController beats at 140 ms', (
    t,
  ) async {
    final services = await _services(t);
    await t.pumpWidget(MaterialApp(home: SettingsScreen(services: services)));
    expect(find.text('Movement speed'), findsOneWidget);
    await t.tap(find.text('Fast'));
    await t.pump();
    expect(services.progress.moveSpeed, MoveSpeed.fast);
    final reopened = (await t.runAsync(ProgressRepository.open))!;
    expect(reopened.moveSpeed, MoveSpeed.fast);

    final level = LevelLoader.fromMap({
      'id': 't',
      'name': 't',
      'runLimit': 2,
      'grid': ['S...E'],
    });
    final game = GameController(level);
    final flow = FlowController(game: game, speed: () => reopened.moveSpeed);
    flow.press(IntentKind.move, Move.right);
    expect(game.state.tick, 1);
    flow.advance(0.139);
    expect(game.state.tick, 1);
    flow.advance(0.002);
    expect(game.state.tick, 2);
    flow.dispose();
    game.dispose();
  });

  testWidgets('the speed control shows the saved choice', (t) async {
    final services = await _services(t);
    await services.progress.setMoveSpeed(MoveSpeed.slow);
    await t.pumpWidget(MaterialApp(home: SettingsScreen(services: services)));
    final control = t.widget<SegmentedButton<MoveSpeed>>(
      find.byType(SegmentedButton<MoveSpeed>),
    );
    expect(control.selected, {MoveSpeed.slow});
  });

  testWidgets('Reduce effects and Vibration switches persist', (t) async {
    final services = await _services(t);
    await t.pumpWidget(MaterialApp(home: SettingsScreen(services: services)));
    await t.tap(find.widgetWithText(SwitchListTile, 'Reduce effects'));
    await t.pump();
    await t.tap(find.widgetWithText(SwitchListTile, 'Vibration'));
    await t.pump();
    expect(services.progress.reduceEffects, isTrue);
    expect(services.progress.vibration, isFalse);
    final reopened = (await t.runAsync(ProgressRepository.open))!;
    expect(reopened.reduceEffects, isTrue);
    expect(reopened.vibration, isFalse);
  });
}

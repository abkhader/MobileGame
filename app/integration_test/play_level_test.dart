import 'package:echo_app/app.dart';
import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_ad_service.dart';
import '../test/support/story_flags.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plays level 1 to completion', (tester) async {
    SharedPreferences.setMockInitialValues(introsSeenPrefs());
    final progress = await ProgressRepository.open();
    await tester.pumpWidget(
      EchoApp(
        services: AppServices(
          levels: LevelRepository(PlatformAssetBundle()),
          progress: progress,
          ads: FakeAdService(),
          audio: const SilentAudioService(),
          story: StoryRepository(PlatformAssetBundle()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Play'));
    await tester.pump(const Duration(milliseconds: 500));
    // Play opens the first unfinished level directly; wait for the board.
    for (var i = 0; i < 50; i++) {
      if (find.byKey(const Key('board')).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 500));

    // Hold the joystick right in the lower board area: 1-01 is four steps
    // right. A touch device is the real target, so drag rather than keys.
    final board = tester.getRect(find.byKey(const Key('board')));
    final thumb = await tester.startGesture(
      Offset(board.center.dx, board.top + board.height * 0.8),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await thumb.moveBy(const Offset(60, 0));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await thumb.up();

    for (var i = 0; i < 50; i++) {
      if (find.text('Level complete').evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Level complete'), findsOneWidget);
  });
}

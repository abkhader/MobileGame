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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plays level 1 to completion', (tester) async {
    SharedPreferences.setMockInitialValues({});
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
    await tester.tap(find.text('1'));
    await tester.pump(const Duration(milliseconds: 500));

    for (var i = 0; i < 4; i++) {
      await tester.fling(
        find.byKey(const Key('board')),
        const Offset(200, 0),
        1000,
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    for (var i = 0; i < 50; i++) {
      if (find.text('Level complete').evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Level complete'), findsOneWidget);
  });
}

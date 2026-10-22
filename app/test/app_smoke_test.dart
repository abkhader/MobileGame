import 'package:echo_app/app.dart';
import 'package:echo_app/app_services.dart';
import 'package:echo_app/audio/audio_service.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_ad_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app starts on Home with Play and Settings', (t) async {
    SharedPreferences.setMockInitialValues({});
    final progress = (await t.runAsync(ProgressRepository.open))!;
    await t.pumpWidget(
      EchoApp(
        services: AppServices(
          levels: LevelRepository(rootBundle),
          progress: progress,
          ads: FakeAdService(),
          audio: const SilentAudioService(),
          story: StoryRepository(rootBundle),
        ),
      ),
    );
    expect(find.text('Echo'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}

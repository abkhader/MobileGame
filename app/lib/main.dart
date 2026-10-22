import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ads/ad_service_factory.dart';
import 'app.dart';
import 'app_services.dart';
import 'audio/flame_audio_service.dart';
import 'data/level_repository.dart';
import 'data/progress_repository.dart';
import 'data/story_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final progress = await ProgressRepository.open();
  final ads = createAdService();
  unawaited(ads.initialize());
  runApp(
    EchoApp(
      services: AppServices(
        levels: LevelRepository(rootBundle),
        progress: progress,
        ads: ads,
        audio: FlameAudioService(),
        story: StoryRepository(rootBundle),
      ),
    ),
  );
}

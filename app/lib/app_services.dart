import 'ads/ad_service.dart';
import 'audio/audio_service.dart';
import 'data/level_repository.dart';
import 'data/progress_repository.dart';
import 'data/story_repository.dart';

class AppServices {
  AppServices({
    required this.levels,
    required this.progress,
    required this.ads,
    required this.audio,
    required this.story,
    this.adPolicy = const AdPolicy(),
  });

  final LevelRepository levels;
  final ProgressRepository progress;
  final AdService ads;
  final AudioService audio;
  final StoryRepository story;
  final AdPolicy adPolicy;
  int completedThisSession = 0;
}

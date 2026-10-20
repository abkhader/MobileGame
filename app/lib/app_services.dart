import 'ads/ad_service.dart';
import 'audio/audio_service.dart';
import 'data/level_repository.dart';
import 'data/progress_repository.dart';

class AppServices {
  AppServices({
    required this.levels,
    required this.progress,
    required this.ads,
    required this.audio,
    this.adPolicy = const AdPolicy(),
  });

  final LevelRepository levels;
  final ProgressRepository progress;
  final AdService ads;
  final AudioService audio;
  final AdPolicy adPolicy;
  int completedThisSession = 0;
}

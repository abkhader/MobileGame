import 'ads/ad_service.dart';
import 'data/level_repository.dart';
import 'data/progress_repository.dart';

class AppServices {
  AppServices({
    required this.levels,
    required this.progress,
    required this.ads,
    this.adPolicy = const AdPolicy(),
  });

  final LevelRepository levels;
  final ProgressRepository progress;
  final AdService ads;
  final AdPolicy adPolicy;
  int completedThisSession = 0;
}

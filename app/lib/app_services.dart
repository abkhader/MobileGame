import 'data/level_repository.dart';
import 'data/progress_repository.dart';

class AppServices {
  AppServices({required this.levels, required this.progress});

  final LevelRepository levels;
  final ProgressRepository progress;
  int completedThisSession = 0;
}

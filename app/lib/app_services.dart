import 'data/level_repository.dart';

class AppServices {
  AppServices({required this.levels});

  final LevelRepository levels;
  int completedThisSession = 0;
}

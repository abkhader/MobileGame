import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'app_services.dart';
import 'data/level_repository.dart';
import 'data/progress_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final progress = await ProgressRepository.open();
  runApp(
    EchoApp(
      services: AppServices(
        levels: LevelRepository(rootBundle),
        progress: progress,
      ),
    ),
  );
}

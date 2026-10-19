import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'app_services.dart';
import 'data/level_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(EchoApp(services: AppServices(levels: LevelRepository(rootBundle))));
}

import 'package:echo_app/app.dart';
import 'package:echo_app/app_services.dart';
import 'package:echo_app/data/level_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app starts on Home with Play and Settings', (t) async {
    await t.pumpWidget(
      EchoApp(services: AppServices(levels: LevelRepository(rootBundle))),
    );
    expect(find.text('Echo'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}

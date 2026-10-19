import 'package:flutter/material.dart';

import 'app_services.dart';
import 'screens/home_screen.dart';

class EchoApp extends StatelessWidget {
  const EchoApp({required this.services, super.key});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Echo',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070B14),
        useMaterial3: true,
      ),
      home: HomeScreen(services: services),
    );
  }
}

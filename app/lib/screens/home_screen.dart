import 'package:flutter/material.dart';

import '../app_services.dart';
import 'level_select_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.services, super.key});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Echo', style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LevelSelectScreen(services: services),
                ),
              ),
              child: const Text('Play'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(services: services),
                ),
              ),
              child: const Text('Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

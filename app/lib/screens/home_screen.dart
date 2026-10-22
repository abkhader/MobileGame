import 'dart:async';

import 'package:flutter/material.dart';

import '../app_services.dart';
import 'city_map_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.services, super.key});

  final AppServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    _startMusic();
  }

  /// A failure (such as a browser blocking autoplay) is ignored; the Play
  /// button tries again after the first tap.
  void _startMusic() {
    if (!services.progress.musicOn) return;
    unawaited(services.audio.startMusic().catchError((_) {}));
  }

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
              onPressed: () {
                _startMusic();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CityMapScreen(services: services),
                  ),
                );
              },
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

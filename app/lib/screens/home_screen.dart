import 'package:flutter/material.dart';

import '../app_services.dart';

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
            FilledButton(onPressed: () {}, child: const Text('Play')),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () {}, child: const Text('Settings')),
          ],
        ),
      ),
    );
  }
}

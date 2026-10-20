import 'dart:async';

import 'package:flutter/material.dart';

import '../app_services.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.services, super.key});

  final AppServices services;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final progress = services.progress;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Music'),
            value: progress.musicOn,
            onChanged: (v) async {
              await progress.setMusicOn(v);
              unawaited(
                (v ? services.audio.startMusic() : services.audio.stopMusic())
                    .catchError((_) {}),
              );
              if (mounted) setState(() {});
            },
          ),
          SwitchListTile(
            title: const Text('Sound effects'),
            value: progress.sfxOn,
            onChanged: (v) async {
              await progress.setSfxOn(v);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

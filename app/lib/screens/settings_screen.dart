import 'dart:async';

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../game/game_clock.dart';

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
          ListTile(
            title: const Text('Movement speed'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<MoveSpeed>(
                segments: const [
                  ButtonSegment(value: MoveSpeed.slow, label: Text('Slow')),
                  ButtonSegment(value: MoveSpeed.normal, label: Text('Normal')),
                  ButtonSegment(value: MoveSpeed.fast, label: Text('Fast')),
                ],
                selected: {progress.moveSpeed},
                showSelectedIcon: false,
                onSelectionChanged: (s) async {
                  await progress.setMoveSpeed(s.first);
                  if (mounted) setState(() {});
                },
              ),
            ),
          ),
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
          SwitchListTile(
            title: const Text('Reduce effects'),
            subtitle: const Text('No trails, shimmer, tilt or tint.'),
            value: progress.reduceEffects,
            onChanged: (v) async {
              await progress.setReduceEffects(v);
              if (mounted) setState(() {});
            },
          ),
          SwitchListTile(
            title: const Text('Vibration'),
            value: progress.vibration,
            onChanged: (v) async {
              await progress.setVibration(v);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

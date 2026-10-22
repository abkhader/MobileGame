import 'dart:async';

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../art/pip.dart';
import '../art/skyline.dart';
import '../game/palette.dart' as palette;
import 'city_map_screen.dart';
import 'open_level.dart';
import 'settings_screen.dart';

/// How long Pip's eye stays shut, and how often it blinks.
const _blinkEvery = Duration(seconds: 4);
const _blinkFor = Duration(milliseconds: 150);
final _blinkStart = 1 - _blinkFor.inMilliseconds / _blinkEvery.inMilliseconds;

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.services, super.key});

  final AppServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: _blinkEvery,
  );
  final ValueNotifier<bool> _eyeOpen = ValueNotifier(true);
  List<String>? _ids;

  AppServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    _blink.addListener(_onBlinkTick);
    _blink.repeat();
    _startMusic();
    unawaited(_loadIds());
  }

  /// Flips [_eyeOpen] only when the eye changes state, so Pip repaints twice
  /// per cycle instead of every frame.
  void _onBlinkTick() {
    _eyeOpen.value = _blink.value < _blinkStart;
  }

  @override
  void dispose() {
    _blink.dispose();
    _eyeOpen.dispose();
    super.dispose();
  }

  Future<void> _loadIds() async {
    try {
      final ids = await services.levels.levelIds();
      if (mounted) setState(() => _ids = ids);
    } catch (_) {
      // Without ids the skyline is simply left out.
    }
  }

  /// A failure (such as a browser blocking autoplay) is ignored; the Play
  /// button tries again after the first tap.
  void _startMusic() {
    if (!services.progress.musicOn) return;
    unawaited(services.audio.startMusic().catchError((_) {}));
  }

  void _openMap() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CityMapScreen(services: services),
      ),
    );
  }

  /// Opens the first level that is unlocked and not yet solved, or the map
  /// when there is none.
  Future<void> _play() async {
    _startMusic();
    final ids = _ids ?? await services.levels.levelIds();
    if (!mounted) return;
    final progress = services.progress;
    String? next;
    for (final id in ids) {
      if (!progress.progressOf(id).completed && progress.isUnlocked(id, ids)) {
        next = id;
        break;
      }
    }
    if (next == null) {
      _openMap();
    } else {
      await openLevel(context, services, next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = _ids;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          if (ids != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 200,
              child: RepaintBoundary(
                child: ListenableBuilder(
                  listenable: services.progress,
                  builder: (context, _) => CustomPaint(
                    painter: _SkylinePainter(
                      buildingsFor(ids, services.progress),
                    ),
                  ),
                ),
              ),
            ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Echo', style: Theme.of(context).textTheme.displayLarge),
                const SizedBox(height: 16),
                RepaintBoundary(
                  child: CustomPaint(
                    size: const Size(120, 120),
                    painter: _PipPainter(_eyeOpen),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: _play, child: const Text('Play')),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _openMap, child: const Text('Map')),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsScreen(services: services),
                    ),
                  ),
                  child: const Text('Settings'),
                ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkylinePainter extends CustomPainter {
  _SkylinePainter(this.buildings);

  final List<Building> buildings;

  @override
  void paint(Canvas canvas, Size size) => paintSkyline(canvas, size, buildings);

  @override
  bool shouldRepaint(_SkylinePainter old) {
    if (old.buildings.length != buildings.length) return true;
    for (var i = 0; i < buildings.length; i++) {
      if (old.buildings[i].state != buildings[i].state ||
          old.buildings[i].stars != buildings[i].stars) {
        return true;
      }
    }
    return false;
  }
}

/// Pip with an eye that shuts for [_blinkFor] at the end of every
/// [_blinkEvery]; repaints only when [eyeOpen] flips.
class _PipPainter extends CustomPainter {
  _PipPainter(this.eyeOpen) : super(repaint: eyeOpen);

  final ValueNotifier<bool> eyeOpen;

  @override
  void paint(Canvas canvas, Size size) {
    paintPip(
      canvas,
      size.center(Offset.zero),
      size.shortestSide * 0.38,
      palette.player,
      eyeOpen: eyeOpen.value ? 1.0 : 0.0,
    );
  }

  @override
  bool shouldRepaint(_PipPainter old) => old.eyeOpen != eyeOpen;
}

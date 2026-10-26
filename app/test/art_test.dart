import 'dart:ui' as ui;

import 'package:echo_app/art/pip.dart';
import 'package:echo_app/art/skyline.dart';
import 'package:echo_app/data/progress_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ids = ['1-01', '1-02', '1-03', '1-04', '1-05'];

/// Counts the lit window panes the skyline draws; ignores everything else.
class _PaneCounter implements Canvas {
  int panes = 0;

  @override
  void drawRect(Rect rect, Paint paint) {
    if (paint.color.toARGB32() == skylineWindowLight.toARGB32() &&
        paint.maskFilter == null) {
      panes++;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Records every Paint a drawing uses; draws nothing.
class _PaintSpy implements Canvas {
  final List<Paint> paints = [];
  int images = 0;

  @override
  void drawCircle(Offset c, double radius, Paint paint) => paints.add(paint);

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => paints.add(paint);

  @override
  void drawOval(Rect rect, Paint paint) => paints.add(paint);

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    images++;
    paints.add(paint);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

int _litPanes(Building b, {bool allLit = false, int seed = 0}) {
  final canvas = _PaneCounter();
  paintSkyline(canvas, const Size(48, 148), [b], allLit: allLit, seed: seed);
  return canvas.panes;
}

/// Records [paint] into a picture and turns it into an image, so any bad
/// geometry fails here rather than on a device.
Future<void> _draw(Size size, void Function(Canvas canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  image.dispose();
  picture.dispose();
}

/// The raw RGBA bytes of what [paint] draws.
Future<List<int>> _pixels(Size size, void Function(Canvas canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  final data = await image.toByteData();
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('buildingsFor maps progress to building states', () async {
    final progress = await ProgressRepository.open();
    await progress.recordWin('1-01', score: 1, best: 1, sparkMask: 0x7);
    await progress.recordSkip('1-02');
    final buildings = buildingsFor(_ids, progress);
    expect(
      [for (final b in buildings) (b.state, b.stars)],
      [
        (BuildingState.solved, 3),
        // A skipped level is solved: lit, with no windows.
        (BuildingState.solved, 0),
        (BuildingState.open, 0),
        (BuildingState.locked, 0),
        (BuildingState.locked, 0),
      ],
    );
  });

  test('paintSkyline draws 0 and 30 buildings, lit or not', () async {
    const size = Size(480, 160);
    final thirty = [
      for (var i = 0; i < 30; i++)
        Building(state: BuildingState.values[i % 3], stars: i % 4),
    ];
    for (final buildings in [const <Building>[], thirty]) {
      for (final lit in [false, true]) {
        await _draw(size, (c) => paintSkyline(c, size, buildings, allLit: lit));
      }
    }
  });

  test('paintPip draws at large and tiny sizes', () async {
    const size = Size(120, 120);
    await _draw(size, (c) {
      paintPip(c, const Offset(60, 60), 40, Colors.white);
      paintPip(c, const Offset(10, 10), 4, Colors.cyan, eyeOpen: 0);
      paintPip(c, const Offset(90, 90), 12, Colors.white, opacity: 0.4);
    });
  });

  test('paintPip draws with lean, stretch and lookDir', () async {
    const size = Size(120, 120);
    await _draw(size, (c) {
      paintPip(
        c,
        const Offset(60, 60),
        40,
        Colors.white,
        lean: 0.14,
        stretch: 0.08,
        lookDir: const Offset(1, 0),
      );
      paintPip(
        c,
        const Offset(20, 20),
        12,
        Colors.cyan,
        lean: -0.14,
        stretch: -0.1,
        lookDir: const Offset(0, -1),
      );
    });
  });

  test('paintPip defaults keep the old pixels; a pose changes them', () async {
    const size = Size(96, 96);
    const center = Offset(48, 48);
    final plain = await _pixels(
      size,
      (c) => paintPip(c, center, 30, Colors.white),
    );
    final zeros = await _pixels(
      size,
      (c) => paintPip(
        c,
        center,
        30,
        Colors.white,
        lean: 0,
        stretch: 0,
        lookDir: Offset.zero,
      ),
    );
    final posed = await _pixels(
      size,
      (c) => paintPip(c, center, 30, Colors.white, lean: 0.14, stretch: 0.08),
    );
    expect(zeros, plain);
    expect(posed, isNot(plain));
  });

  test('a flickering Pip does not build a shader per frame', () async {
    const size = Size(64, 64);
    await _draw(size, (c) {
      paintPip(c, const Offset(32, 32), 20, Colors.cyan, opacity: 0.55);
    });
    final before = pipShaderBuilds;
    await _draw(size, (c) {
      // 120 frames of flicker and a 300 ms shimmer's worth of opacities.
      for (var i = 0; i < 120; i++) {
        final flicker = 0.55 * (0.92 + 0.08 * (i % 17) / 17);
        paintPip(c, const Offset(32, 32), 20, Colors.cyan, opacity: flicker);
        paintPip(c, const Offset(32, 32), 20, Colors.cyan, opacity: i / 119);
      }
    });
    // At most one shader per 1/32 opacity step, never one per frame.
    expect(pipShaderBuilds - before, lessThanOrEqualTo(33));
  });

  test('a solved building lights one window per star', () {
    for (var seed = 0; seed < 4; seed++) {
      for (var k = 0; k <= 3; k++) {
        final b = Building(state: BuildingState.solved, stars: k);
        expect(_litPanes(b, seed: seed), k, reason: 'seed $seed, $k stars');
      }
      expect(
        _litPanes(const Building(state: BuildingState.open), seed: seed),
        0,
      );
      expect(
        _litPanes(const Building(state: BuildingState.locked), seed: seed),
        0,
      );
      // The ending lights more than three.
      expect(
        _litPanes(const Building(state: BuildingState.locked), allLit: true),
        greaterThan(3),
      );
    }
  });

  group('baked glows', () {
    setUp(clearPipGlowCache);

    test('paintPip draws no live blur: halo and spark are baked images', () {
      final spy = _PaintSpy();
      paintPip(spy, const Offset(40, 40), 30, Colors.white);
      paintPip(spy, const Offset(40, 40), 30, Colors.cyan, opacity: 0.4);
      expect(spy.paints.where((p) => p.maskFilter != null), isEmpty);
      expect(spy.images, 4, reason: 'a halo and a spark glow per Pip');
    });

    test('flicker and shimmer reuse the baked glows', () async {
      const size = Size(64, 64);
      final before = pipGlowBakes;
      await _draw(size, (c) {
        for (var i = 0; i < 120; i++) {
          final flicker = 0.55 * (0.92 + 0.08 * (i % 17) / 17);
          paintPip(c, const Offset(32, 32), 20, Colors.cyan, opacity: flicker);
          paintPip(c, const Offset(32, 32), 20, Colors.cyan, opacity: i / 119);
        }
      });
      // One halo and one spark glow for the colour.
      expect(pipGlowBakes - before, 2);
    });

    test('the glow cache is bounded and keyed by radius', () {
      final spy = _PaintSpy();
      for (var i = 0; i < 200; i++) {
        paintPip(spy, Offset.zero, 20, Color(0xFF000000 + i * 997));
      }
      expect(pipGlowCacheSize, lessThanOrEqualTo(pipGlowCacheLimit));
      clearPipGlowCache();
      paintPip(spy, Offset.zero, 20, Colors.white);
      final atTwenty = pipGlowCacheSize;
      expect(atTwenty, 2);
      // The board and a HUD icon can share a frame: two radii stay cached.
      paintPip(spy, Offset.zero, 30, Colors.white);
      expect(pipGlowCacheSize, 4);
      final bakes = pipGlowBakes;
      paintPip(spy, Offset.zero, 20, Colors.white);
      paintPip(spy, Offset.zero, 30, Colors.white);
      expect(pipGlowBakes, bakes);
      // A third radius (a resize) drops the oldest.
      paintPip(spy, Offset.zero, 40, Colors.white);
      expect(pipGlowCacheSize, 4);
      paintPip(spy, Offset.zero, 20, Colors.white);
      expect(pipGlowBakes, bakes + 4);
    });

    test('the baked halo looks like the live blur it replaces', () async {
      const size = Size(96, 96);
      const center = Offset(48, 48);
      const r = 30.0;
      final baked = await _pixels(size, (c) {
        c.drawColor(Colors.black, BlendMode.src);
        paintPip(c, center, r, Colors.cyan);
      });
      final live = await _pixels(size, (c) {
        c.drawColor(Colors.black, BlendMode.src);
        c.drawCircle(
          center,
          r * 1.35,
          Paint()
            ..color = Colors.cyan.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, r * 0.45),
        );
      });
      // Compare a ring outside the body, where only the halo shows; the
      // antenna sits in the upper half, so only the lower half counts.
      var worst = 0;
      for (var y = 48; y < 96; y++) {
        for (var x = 0; x < 96; x++) {
          final d = (Offset(x + 0.5, y + 0.5) - center).distance;
          if (d < r * 1.1 || d > 47) continue;
          final o = (y * 96 + x) * 4;
          for (var k = 0; k < 3; k++) {
            final diff = (baked[o + k] - live[o + k]).abs();
            if (diff > worst) worst = diff;
          }
        }
      }
      expect(worst, lessThanOrEqualTo(3));
    });
  });
}

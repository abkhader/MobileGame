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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('buildingsFor maps progress to building states', () async {
    final progress = await ProgressRepository.open();
    await progress.recordCompletion('1-01', 3);
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
}

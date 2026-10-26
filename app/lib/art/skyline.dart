import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';

import '../data/progress_repository.dart';
import '../game/palette.dart' as palette;

enum BuildingState { locked, open, solved }

/// One level as a building on the skyline.
class Building {
  const Building({required this.state, this.stars = 0, this.sparkMask = 0});

  final BuildingState state;

  /// Bit i set: spark i of this level is remembered; each lights one dot in
  /// the sky above the building.
  final int sparkMask;

  /// 0–3; only used when [state] is [BuildingState.solved].
  final int stars;
}

/// The buildings for [ids], in order. A completed level (a skipped one
/// included, with 0 stars) is solved; an unlocked one is open.
List<Building> buildingsFor(List<String> ids, ProgressRepository progress) => [
  for (final id in ids) _buildingFor(id, ids, progress),
];

Building _buildingFor(String id, List<String> ids, ProgressRepository p) {
  final level = p.progressOf(id);
  if (level.completed) {
    return Building(
      state: BuildingState.solved,
      stars: level.stars,
      sparkMask: level.sparkMask,
    );
  }
  return Building(
    state: p.isUnlocked(id, ids) ? BuildingState.open : BuildingState.locked,
  );
}

const _accents = [
  Color(0xFF00E5FF), // cyan
  Color(0xFFFF2BD6), // magenta
  Color(0xFFFFB300), // amber
  palette.doorClosed, // purple
  palette.platePressed, // neon green
];

/// The pane colour of a lit window; tests count panes drawn in it.
@visibleForTesting
const skylineWindowLight = Color(0xFFFFE7A3);
const _windowLight = skylineWindowLight;
// Locked buildings are dark silhouettes with a faint rim, a clear step
// above the far layer, which sits just above the panel colour.
const _lockedFill = Color(0xFF162036);
const _lockedRim = Color(0xFF24345A);
const _farFill = Color(0xFF0C1324);
const _openFill = Color(0xFF0A1120);

/// Draws [buildings] left to right across [size], one equal slot each, on a
/// ground line at the bottom. Heights, widths and roofs are seeded by index
/// and [seed] (one per district, so each has its own silhouette),
/// so the skyline is the same every frame.
///
/// Locked buildings are near-invisible silhouettes, open ones a dim neon
/// outline, solved ones lit with one glowing window per star. [allLit]
/// lights every building and every window (the ending).
void paintSkyline(
  Canvas canvas,
  Size size,
  List<Building> buildings, {
  bool allLit = false,
  int seed = 0,
}) {
  if (size.isEmpty) return;
  _paintFarLayer(canvas, size, buildings.length, allLit, seed);
  final n = buildings.length;
  if (n > 0) {
    final slot = size.width / n;
    for (var i = 0; i < n; i++) {
      _paintBuilding(canvas, size, i, slot, buildings[i], allLit, seed);
    }
  }
  if (!allLit) _paintSparkLights(canvas, size, buildings, seed);
  _paintGround(canvas, size, allLit);
}

/// Where the spark lights go: one point per remembered spark, above its
/// building and fixed by building index, spark index and [seed]. The skyline
/// is static: its CustomPainter repaints only when a building's state, stars
/// or sparks change, never per frame. Tests read this to count the lights.
@visibleForTesting
List<Offset> skylineSparkLights(
  Size size,
  List<Building> buildings, {
  int seed = 0,
}) {
  final lights = <Offset>[];
  final n = buildings.length;
  if (size.isEmpty || n == 0) return lights;
  final slot = size.width / n;
  for (var i = 0; i < n; i++) {
    final b = buildings[i];
    if (b.state != BuildingState.solved) continue;
    final body = _bodyRect(size, i, slot, seed);
    for (var k = 0; k < 3; k++) {
      if (b.sparkMask & (1 << k) == 0) continue;
      final x =
          body.left +
          body.width * (0.2 + 0.3 * k + 0.1 * _noise(i * 3 + k, 21, seed));
      final y = math.max(3.0, body.top - 5 - 9 * _noise(i * 3 + k, 22, seed));
      lights.add(Offset(x, y));
    }
  }
  return lights;
}

void _paintSparkLights(Canvas canvas, Size size, List<Building> b, int seed) {
  final lights = skylineSparkLights(size, b, seed: seed);
  if (lights.isEmpty) return;
  final glow = Paint()
    ..color = palette.spark.withValues(alpha: 0.55)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  final core = Paint()..color = palette.sparkCore;
  for (final p in lights) {
    canvas
      ..drawCircle(p, 3.2, glow)
      ..drawCircle(p, 1.3, core);
  }
}

Rect _bodyRect(Size size, int i, double slot, int seed) {
  final w = math.max(2.0, slot * (0.56 + 0.32 * _noise(i, 1, seed)));
  final h = size.height * (0.4 + 0.44 * _noise(i, 2, seed));
  return Rect.fromLTWH(i * slot + (slot - w) / 2, size.height - h, w, h);
}

/// A deterministic value in [0, 1] for index [i] and channel [salt].
double _noise(int i, int salt, [int seed = 0]) {
  i += seed * 1009;
  var x = (i + 1) * 73856093 ^ (salt + 7) * 19349663;
  x = (x ^ (x >> 13)) * 1274126177;
  x ^= x >> 16;
  return (x & 0xffff) / 0xffff;
}

/// Low background blocks give the skyline depth.
void _paintFarLayer(Canvas canvas, Size size, int n, bool allLit, int seed) {
  final count = math.max(6, n * 2);
  final step = size.width / count;
  final fill = Paint()..color = _farFill;
  final dot = Paint()..color = _windowLight.withValues(alpha: 0.25);
  for (var j = 0; j < count; j++) {
    final w = step * (0.9 + 0.5 * _noise(j, 11, seed));
    final h = size.height * (0.22 + 0.3 * _noise(j, 12, seed));
    final rect = Rect.fromLTWH(j * step - w * 0.2, size.height - h, w, h);
    canvas.drawRect(rect, fill);
    if (allLit && rect.width > 6) {
      for (var y = rect.top + 5; y < rect.bottom - 4; y += 7) {
        if (_noise(j, y.round(), seed) > 0.55) {
          canvas.drawRect(Rect.fromLTWH(rect.center.dx - 1, y, 2, 2), dot);
        }
      }
    }
  }
}

void _paintGround(Canvas canvas, Size size, bool allLit) {
  final y = size.height - 0.75;
  final color = allLit ? _accents[0] : palette.doorClosed;
  canvas.drawLine(
    Offset(0, y),
    Offset(size.width, y),
    Paint()
      ..color = color.withValues(alpha: allLit ? 0.5 : 0.3)
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
  );
  canvas.drawLine(
    Offset(0, y),
    Offset(size.width, y),
    Paint()
      ..color = color.withValues(alpha: allLit ? 0.9 : 0.55)
      ..strokeWidth = 1.5,
  );
}

void _paintBuilding(
  Canvas canvas,
  Size size,
  int i,
  double slot,
  Building b,
  bool allLit,
  int seed,
) {
  final ground = size.height;
  final body = _bodyRect(size, i, slot, seed);
  final w = body.width;
  final h = body.height;
  final roof = (_noise(i, 3, seed) * 3).floor();
  final accent = _accents[(i + seed * 2) % _accents.length];

  var shape = Path()..addRect(body);
  if (roof == 1) {
    // A stepped top, merged so its outline has no seam.
    final step = Rect.fromLTWH(
      body.left + w * 0.22,
      body.top - h * 0.1,
      w * 0.56,
      h * 0.1 + 1,
    );
    shape = Path.combine(PathOperation.union, shape, Path()..addRect(step));
  }
  final antennaBase = Offset(body.left + w * 0.7, body.top);
  final antennaTip = antennaBase - Offset(0, h * 0.16);

  final state = allLit ? BuildingState.solved : b.state;
  switch (state) {
    case BuildingState.locked:
      canvas.drawPath(shape, Paint()..color = _lockedFill);
      canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _lockedRim
          ..strokeWidth = 1,
      );
      if (roof == 2) {
        canvas.drawLine(
          antennaBase,
          antennaTip,
          Paint()
            ..color = _lockedRim
            ..strokeWidth = 1.5,
        );
      }
    case BuildingState.open:
      canvas.drawPath(shape, Paint()..color = _openFill);
      canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = accent.withValues(alpha: 0.18)
          ..strokeWidth = 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = accent.withValues(alpha: 0.5)
          ..strokeWidth = 1.2,
      );
      if (roof == 2) _antenna(canvas, antennaBase, antennaTip, accent, 0.5);
      // A lit doorway invites Pip in.
      final door = Rect.fromLTWH(
        body.center.dx - w * 0.1,
        ground - math.min(h * 0.14, 12),
        w * 0.2,
        math.min(h * 0.14, 12),
      );
      canvas.drawRect(door, Paint()..color = accent.withValues(alpha: 0.45));
    case BuildingState.solved:
      canvas.drawPath(
        shape,
        Paint()
          ..color = accent.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawPath(
        shape,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(_openFill, accent, 0.32)!,
              Color.lerp(_openFill, accent, 0.1)!,
            ],
          ).createShader(body),
      );
      canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = accent.withValues(alpha: 0.95)
          ..strokeWidth = 1.5,
      );
      if (roof == 2) _antenna(canvas, antennaBase, antennaTip, accent, 1);
      final lit = allLit ? null : b.stars.clamp(0, 3);
      _paintWindows(canvas, body, accent, lit);
  }
}

void _antenna(Canvas canvas, Offset base, Offset tip, Color c, double a) {
  canvas.drawLine(
    base,
    tip,
    Paint()
      ..color = c.withValues(alpha: 0.8 * a)
      ..strokeWidth = 1.2,
  );
  canvas.drawCircle(
    tip,
    3,
    Paint()
      ..color = c.withValues(alpha: 0.6 * a)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
  );
  canvas.drawCircle(tip, 1.4, Paint()..color = c.withValues(alpha: a));
}

/// A grid of window slots, top to bottom. The first [lit] glow; a null
/// [lit] lights them all.
void _paintWindows(Canvas canvas, Rect body, Color accent, int? lit) {
  final cols = body.width >= 22 ? 2 : 1;
  final ww = math.min(body.width * (cols == 2 ? 0.2 : 0.36), 9.0);
  final wh = ww * 1.2;
  final gapY = wh * 0.9;
  final top = body.top + math.max(6, body.height * 0.1);
  var rows = ((body.bottom - top - wh) / (wh + gapY)).floor();
  // Always room for three star windows.
  rows = math.max(rows, (3 / cols).ceil());
  final colGap = body.width / (cols + 1);
  final unlit = Paint()..color = accent.withValues(alpha: 0.12);
  final glow = Paint()
    ..color = _windowLight.withValues(alpha: 0.55)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, ww * 0.6);
  final pane = Paint()..color = _windowLight;
  var k = 0;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final center = Offset(
        body.left + colGap * (c + 1),
        top + wh / 2 + r * (wh + gapY),
      );
      final rect = Rect.fromCenter(center: center, width: ww, height: wh);
      if (lit == null || k < lit) {
        canvas.drawRect(rect.inflate(ww * 0.35), glow);
        canvas.drawRect(rect, pane);
      } else {
        canvas.drawRect(rect, unlit);
      }
      k++;
    }
  }
}

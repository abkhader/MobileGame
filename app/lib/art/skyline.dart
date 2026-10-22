import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../data/progress_repository.dart';
import '../game/palette.dart' as palette;

enum BuildingState { locked, open, solved }

/// One level as a building on the skyline.
class Building {
  const Building({required this.state, this.stars = 0});

  final BuildingState state;

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
    return Building(state: BuildingState.solved, stars: level.stars);
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
const _windowLight = Color(0xFFFFE7A3);
const _lockedFill = Color(0xFF0C1322);
const _farFill = Color(0xFF0A101D);
const _openFill = Color(0xFF0A1120);

/// Draws [buildings] left to right across [size], one equal slot each, on a
/// ground line at the bottom. Heights, widths and roofs are seeded by index,
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
}) {
  if (size.isEmpty) return;
  _paintFarLayer(canvas, size, buildings.length, allLit);
  final n = buildings.length;
  if (n > 0) {
    final slot = size.width / n;
    for (var i = 0; i < n; i++) {
      _paintBuilding(canvas, size, i, slot, buildings[i], allLit);
    }
  }
  _paintGround(canvas, size, allLit);
}

/// A deterministic value in [0, 1] for index [i] and channel [salt].
double _noise(int i, int salt) {
  var x = (i + 1) * 73856093 ^ (salt + 7) * 19349663;
  x = (x ^ (x >> 13)) * 1274126177;
  x ^= x >> 16;
  return (x & 0xffff) / 0xffff;
}

/// Low background blocks give the skyline depth.
void _paintFarLayer(Canvas canvas, Size size, int n, bool allLit) {
  final count = math.max(6, n * 2);
  final step = size.width / count;
  final fill = Paint()..color = _farFill;
  final dot = Paint()..color = _windowLight.withValues(alpha: 0.25);
  for (var j = 0; j < count; j++) {
    final w = step * (0.9 + 0.5 * _noise(j, 11));
    final h = size.height * (0.22 + 0.3 * _noise(j, 12));
    final rect = Rect.fromLTWH(j * step - w * 0.2, size.height - h, w, h);
    canvas.drawRect(rect, fill);
    if (allLit && rect.width > 6) {
      for (var y = rect.top + 5; y < rect.bottom - 4; y += 7) {
        if (_noise(j, y.round()) > 0.55) {
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
) {
  final ground = size.height;
  final w = math.max(2.0, slot * (0.56 + 0.32 * _noise(i, 1)));
  final h = size.height * (0.4 + 0.44 * _noise(i, 2));
  final left = i * slot + (slot - w) / 2;
  final body = Rect.fromLTWH(left, ground - h, w, h);
  final roof = (_noise(i, 3) * 3).floor();
  final accent = _accents[i % _accents.length];

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
      if (roof == 2) {
        canvas.drawLine(
          antennaBase,
          antennaTip,
          Paint()
            ..color = _lockedFill
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

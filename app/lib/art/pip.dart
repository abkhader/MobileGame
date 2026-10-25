import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../game/palette.dart' as palette;

// Shared drawing state: Pip is painted every frame, several times, so the
// Paints, blur filters and body gradient are reused instead of rebuilt.
final _haloPaint = Paint();
final _antennaPaint = Paint()..strokeCap = StrokeCap.round;
final _sparkGlowPaint = Paint();
final _sparkPaint = Paint();
final _bodyPaint = Paint();
final _eyePaint = Paint();
final _eyeLinePaint = Paint()..strokeCap = StrokeCap.round;
final _catchPaint = Paint();
final _glossPaint = Paint();

final Map<double, MaskFilter> _blurs = {};
MaskFilter _blur(double sigma) {
  if (_blurs.length > 16) _blurs.clear();
  return _blurs[sigma] ??= MaskFilter.blur(BlurStyle.normal, sigma);
}

// Body gradients in local space (Pip centred on the origin), keyed by colour
// and opacity. Opacity is rounded to 1/32 for the cache, so a flickering or
// shimmering echo reuses a few shaders instead of making one per frame.
// Reset when the radius changes.
const _alphaSteps = 32;
final Map<int, Shader> _bodyShaders = {};
double _shaderRadius = -1;

/// How many body shaders were built; for tests.
@visibleForTesting
int pipShaderBuilds = 0;

Shader _bodyShader(Color color, double r, double opacity) {
  if (r != _shaderRadius || _bodyShaders.length > 48) {
    _bodyShaders.clear();
    _shaderRadius = r;
  }
  final step = (opacity * _alphaSteps).round();
  final key = color.toARGB32() * (_alphaSteps + 1) + step;
  final cached = _bodyShaders[key];
  if (cached != null) return cached;
  pipShaderBuilds++;
  final a = step / _alphaSteps;
  return _bodyShaders[key] = RadialGradient(
    center: const Alignment(-0.3, -0.35),
    radius: 1.1,
    colors: [
      Color.lerp(color, const Color(0xFFFFFFFF), 0.6)!.withValues(
        alpha: Color.lerp(color, const Color(0xFFFFFFFF), 0.6)!.a * a,
      ),
      color.withValues(alpha: color.a * a),
      Color.lerp(
        color,
        palette.background,
        0.35,
      )!.withValues(alpha: Color.lerp(color, palette.background, 0.35)!.a * a),
    ],
    stops: const [0, 0.65, 1],
  ).createShader(Rect.fromCircle(center: Offset.zero, radius: r));
}

/// Paints Pip, the spark-bot: a glowing round body with one big eye and,
/// when large enough to read, a tiny antenna with a spark on top.
///
/// [eyeOpen] runs from 0 (closed, drawn as a lid line) to 1 (wide open);
/// [opacity] fades the whole bot.
///
/// Pose: [lookDir] shifts the eye toward a direction (length up to 1);
/// [lean] tilts the bot by that many radians (positive leans right);
/// [stretch] scales it along [lookDir] (vertical when zero) by 1 + stretch,
/// keeping its area, so negative values squash. The defaults draw the
/// resting bot.
void paintPip(
  Canvas canvas,
  Offset center,
  double radius,
  Color color, {
  double eyeOpen = 1.0,
  double opacity = 1.0,
  Offset lookDir = Offset.zero,
  double lean = 0,
  double stretch = 0,
}) {
  if (radius <= 0 || opacity <= 0) return;
  final r = radius;
  final a = opacity.clamp(0.0, 1.0);
  final eye = eyeOpen.clamp(0.0, 1.0);
  // Details that turn to mush below this size are left out.
  final detailed = r >= 8;

  canvas.save();
  canvas.translate(center.dx, center.dy);
  if (lean != 0) canvas.rotate(lean);
  if (stretch != 0) {
    // Scale along the travel axis: rotate onto it, scale, rotate back.
    final axis = lookDir == Offset.zero
        ? math.pi / 2
        : math.atan2(lookDir.dy, lookDir.dx);
    final along = (1 + stretch).clamp(0.5, 1.5);
    canvas
      ..rotate(axis)
      ..scale(along, 1 / along)
      ..rotate(-axis);
  }

  // Soft halo.
  canvas.drawCircle(
    Offset.zero,
    r * 1.35,
    _haloPaint
      ..color = _fade(color, a, 0.35)
      ..maskFilter = _blur(r * 0.45),
  );

  // Antenna, behind the body so it grows out of the top.
  if (detailed) {
    final base = Offset(r * 0.18, -r * 0.92);
    final tip = Offset(r * 0.42, -r * 1.48);
    canvas.drawLine(
      base,
      tip,
      _antennaPaint
        ..color = _fade(color, a, 0.85)
        ..strokeWidth = r * 0.09,
    );
    final spark = palette.ghostColors[2];
    canvas.drawCircle(
      tip,
      r * 0.26,
      _sparkGlowPaint
        ..color = _fade(spark, a, 0.6)
        ..maskFilter = _blur(r * 0.12),
    );
    canvas.drawCircle(tip, r * 0.12, _sparkPaint..color = _fade(spark, a));
  }

  // Body: bright core fading to the outer colour.
  canvas.drawCircle(
    Offset.zero,
    r,
    _bodyPaint..shader = _bodyShader(color, r, a),
  );

  // Eye: one big dark lens, slightly above centre.
  final look = lookDir.distance > 1 ? lookDir / lookDir.distance : lookDir;
  final eyeCenter = Offset(look.dx * r * 0.14, -r * 0.08 + look.dy * r * 0.1);
  final eyeW = r * 0.95;
  final eyeH = r * 0.95 * eye;
  final ink = palette.background;
  if (eye < 0.12) {
    canvas.drawLine(
      eyeCenter - Offset(eyeW / 2, 0),
      eyeCenter + Offset(eyeW / 2, 0),
      _eyeLinePaint
        ..color = _fade(ink, a)
        ..strokeWidth = math.max(1, r * 0.12),
    );
  } else {
    canvas.drawOval(
      Rect.fromCenter(center: eyeCenter, width: eyeW, height: eyeH),
      _eyePaint..color = _fade(ink, a),
    );
    // A catch-light makes the eye read as alive, even when tiny.
    canvas.drawCircle(
      eyeCenter + Offset(eyeW * 0.18, -eyeH * 0.18),
      math.max(0.8, r * 0.13 * math.min(1, eye * 1.5)),
      _catchPaint..color = _fade(const Color(0xFFFFFFFF), a, 0.95),
    );
  }

  // Glossy highlight on the upper left of the body.
  if (detailed) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.52, -r * 0.5),
        width: r * 0.32,
        height: r * 0.2,
      ),
      _glossPaint..color = _fade(const Color(0xFFFFFFFF), a, 0.55),
    );
  }

  canvas.restore();
}

/// [c] at [alpha] of its own opacity, times the bot's opacity [a].
Color _fade(Color c, double a, [double alpha = 1]) =>
    c.withValues(alpha: c.a * alpha * a);

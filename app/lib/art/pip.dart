import 'dart:math' as math;

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
// and opacity. Only a handful are live at once; reset when the radius changes.
final Map<(int, double), Shader> _bodyShaders = {};
double _shaderRadius = -1;
Shader _bodyShader(Color color, double r, double a) {
  if (r != _shaderRadius || _bodyShaders.length > 16) {
    _bodyShaders.clear();
    _shaderRadius = r;
  }
  return _bodyShaders[(color.toARGB32(), a)] ??= RadialGradient(
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
void paintPip(
  Canvas canvas,
  Offset center,
  double radius,
  Color color, {
  double eyeOpen = 1.0,
  double opacity = 1.0,
}) {
  if (radius <= 0 || opacity <= 0) return;
  final r = radius;
  final a = opacity.clamp(0.0, 1.0);
  final eye = eyeOpen.clamp(0.0, 1.0);
  // Details that turn to mush below this size are left out.
  final detailed = r >= 8;

  Color fade(Color c, [double alpha = 1]) =>
      c.withValues(alpha: c.a * alpha * a);

  canvas.save();
  canvas.translate(center.dx, center.dy);

  // Soft halo.
  canvas.drawCircle(
    Offset.zero,
    r * 1.35,
    _haloPaint
      ..color = fade(color, 0.35)
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
        ..color = fade(color, 0.85)
        ..strokeWidth = r * 0.09,
    );
    final spark = palette.ghostColors[2];
    canvas.drawCircle(
      tip,
      r * 0.26,
      _sparkGlowPaint
        ..color = fade(spark, 0.6)
        ..maskFilter = _blur(r * 0.12),
    );
    canvas.drawCircle(tip, r * 0.12, _sparkPaint..color = fade(spark));
  }

  // Body: bright core fading to the outer colour.
  canvas.drawCircle(
    Offset.zero,
    r,
    _bodyPaint..shader = _bodyShader(color, r, a),
  );

  // Eye: one big dark lens, slightly above centre.
  final eyeCenter = Offset(0, -r * 0.08);
  final eyeW = r * 0.95;
  final eyeH = r * 0.95 * eye;
  final ink = palette.background;
  if (eye < 0.12) {
    canvas.drawLine(
      eyeCenter - Offset(eyeW / 2, 0),
      eyeCenter + Offset(eyeW / 2, 0),
      _eyeLinePaint
        ..color = fade(ink)
        ..strokeWidth = math.max(1, r * 0.12),
    );
  } else {
    canvas.drawOval(
      Rect.fromCenter(center: eyeCenter, width: eyeW, height: eyeH),
      _eyePaint..color = fade(ink),
    );
    // A catch-light makes the eye read as alive, even when tiny.
    canvas.drawCircle(
      eyeCenter + Offset(eyeW * 0.18, -eyeH * 0.18),
      math.max(0.8, r * 0.13 * math.min(1, eye * 1.5)),
      _catchPaint..color = fade(const Color(0xFFFFFFFF), 0.95),
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
      _glossPaint..color = fade(const Color(0xFFFFFFFF), 0.55),
    );
  }

  canvas.restore();
}

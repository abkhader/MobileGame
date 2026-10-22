import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../game/palette.dart' as palette;

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

  // Soft halo.
  canvas.drawCircle(
    center,
    r * 1.35,
    Paint()
      ..color = fade(color, 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.45),
  );

  // Antenna, behind the body so it grows out of the top.
  if (detailed) {
    final base = center + Offset(r * 0.18, -r * 0.92);
    final tip = center + Offset(r * 0.42, -r * 1.48);
    canvas.drawLine(
      base,
      tip,
      Paint()
        ..color = fade(color, 0.85)
        ..strokeWidth = r * 0.09
        ..strokeCap = StrokeCap.round,
    );
    final spark = palette.ghostColors[2];
    canvas.drawCircle(
      tip,
      r * 0.26,
      Paint()
        ..color = fade(spark, 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12),
    );
    canvas.drawCircle(tip, r * 0.12, Paint()..color = fade(spark));
  }

  // Body: bright core fading to the outer colour.
  final bodyRect = Rect.fromCircle(center: center, radius: r);
  canvas.drawCircle(
    center,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.35),
        radius: 1.1,
        colors: [
          fade(Color.lerp(color, const Color(0xFFFFFFFF), 0.6)!),
          fade(color),
          fade(Color.lerp(color, palette.background, 0.35)!),
        ],
        stops: const [0, 0.65, 1],
      ).createShader(bodyRect),
  );

  // Eye: one big dark lens, slightly above centre.
  final eyeCenter = center + Offset(0, -r * 0.08);
  final eyeW = r * 0.95;
  final eyeH = r * 0.95 * eye;
  final ink = palette.background;
  if (eye < 0.12) {
    canvas.drawLine(
      eyeCenter - Offset(eyeW / 2, 0),
      eyeCenter + Offset(eyeW / 2, 0),
      Paint()
        ..color = fade(ink)
        ..strokeWidth = math.max(1, r * 0.12)
        ..strokeCap = StrokeCap.round,
    );
  } else {
    canvas.drawOval(
      Rect.fromCenter(center: eyeCenter, width: eyeW, height: eyeH),
      Paint()..color = fade(ink),
    );
    // A catch-light makes the eye read as alive, even when tiny.
    canvas.drawCircle(
      eyeCenter + Offset(eyeW * 0.18, -eyeH * 0.18),
      math.max(0.8, r * 0.13 * math.min(1, eye * 1.5)),
      Paint()..color = fade(const Color(0xFFFFFFFF), 0.95),
    );
  }

  // Glossy highlight on the upper left of the body.
  if (detailed) {
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(-r * 0.52, -r * 0.5),
        width: r * 0.32,
        height: r * 0.2,
      ),
      Paint()..color = fade(const Color(0xFFFFFFFF), 0.55),
    );
  }
}

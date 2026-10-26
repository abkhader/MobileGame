import 'package:flutter/widgets.dart';

import '../game/palette.dart' as palette;
import 'spark_star.dart';

/// The spark counter's star, drawn from the same path as the board's sparks.
/// Used wherever a spark is shown as an icon, so no screen relies on the
/// "✦" glyph's font fallback.
class SparkIconPainter extends CustomPainter {
  const SparkIconPainter({this.color = palette.spark});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(size.shortestSide / 2)
      ..drawPath(unitSparkStar, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(SparkIconPainter old) => old.color != color;
}

/// A square spark icon of [size] logical pixels; decorative (the caller
/// labels it in words).
class SparkIcon extends StatelessWidget {
  const SparkIcon({this.size = 14, this.color = palette.spark, super.key});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: SparkIconPainter(color: color),
  );
}

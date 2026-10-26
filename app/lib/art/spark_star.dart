import 'dart:math' as math;
import 'dart:ui';

/// A four-point star of radius 1 around the origin, built once; scale it
/// when drawing so nothing is allocated per frame.
final Path unitSparkStar = _fourPointStar(1, 0.32);

/// Tips at [outer], waist at [inner].
Path _fourPointStar(double outer, double inner) {
  final path = Path();
  for (var k = 0; k < 8; k++) {
    final a = -math.pi / 2 + k * math.pi / 4;
    final d = k.isEven ? outer : inner;
    final x = d * math.cos(a);
    final y = d * math.sin(a);
    if (k == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  return path..close();
}

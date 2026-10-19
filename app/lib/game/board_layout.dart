import 'dart:math' as math;
import 'dart:ui';

import 'package:echo_core/echo_core.dart';

/// Places a [columns] x [rows] grid centred on a canvas, with the largest
/// square cells that fit inside [padding] on every side.
class BoardLayout {
  BoardLayout({
    required this.canvas,
    required this.columns,
    required this.rows,
    this.padding = 16,
  });

  final Size canvas;
  final int columns;
  final int rows;
  final double padding;

  double get cellSize => math.min(
    (canvas.width - 2 * padding) / columns,
    (canvas.height - 2 * padding) / rows,
  );

  Offset get origin => Offset(
    (canvas.width - cellSize * columns) / 2,
    (canvas.height - cellSize * rows) / 2,
  );

  Rect rectOf(Position p) => Rect.fromLTWH(
    origin.dx + p.x * cellSize,
    origin.dy + p.y * cellSize,
    cellSize,
    cellSize,
  );

  Offset centerOf(Position p) => rectOf(p).center;
}

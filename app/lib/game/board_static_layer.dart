import 'dart:math' as math;
import 'dart:ui';

import 'package:echo_core/echo_core.dart';

import 'board_layout.dart';
import 'palette.dart' as palette;

/// The parts of the board that never move: floor, grid, walls and exit
/// frames, recorded once into an image at the screen's pixel density, plus
/// the per-tile geometry the animated layer reuses every frame.
///
/// Rebuilt only when the board's size or pixel density really changes;
/// Flame reports a resize on every widget rebuild, even at the same size.
class BoardStaticLayer {
  BoardStaticLayer(this.level);

  final Level level;

  BoardLayout? _layout;
  Image? _image;
  double _w = -1;
  double _h = -1;
  double _dpr = -1;
  Rect _src = Rect.zero;
  Rect _dst = Rect.zero;

  int _builds = 0;

  /// How many times the image was recorded.
  int get builds => _builds;

  final _blitPaint = Paint()..filterQuality = FilterQuality.low;

  // Geometry cached per layout.
  final List<Rect> exitRects = [];
  final List<Position> platePositions = [];
  final List<RRect> plateRects = [];
  final List<Offset> plateCenters = [];
  final List<Position> doorPositions = [];

  /// The full door bar, drawn in the open colour.
  final List<Rect> doorRects = [];

  /// Top-left and bottom-left of each door bar; the closed halves grow from
  /// these by [doorHalfDown] and [doorHalfUp] scaled vertically.
  final List<Offset> doorTops = [];
  final List<Offset> doorBottoms = [];
  Rect doorHalfDown = Rect.zero;
  Rect doorHalfUp = Rect.zero;

  /// The battery ring's bounds, centred on the origin.
  Rect ringRect = Rect.zero;

  BoardLayout? get layout => _layout;

  /// The whole board, in logical px.
  Rect get bounds => _dst;

  /// Makes sure the layer matches a [w] x [h] board at [dpr]. Returns the
  /// layout, or null while the board is too small to draw.
  BoardLayout? ensure(double w, double h, double dpr) {
    if (w == _w && h == _h && dpr == _dpr) return _layout;
    _w = w;
    _h = h;
    _dpr = dpr;
    final layout = BoardLayout(
      canvas: Size(w, h),
      columns: level.width,
      rows: level.height,
    );
    if (layout.cellSize <= 0) {
      _layout = null;
      _disposeImage();
      return null;
    }
    _layout = layout;
    _cacheGeometry(layout);
    _record(layout, w, h, dpr);
    return layout;
  }

  void draw(Canvas canvas) {
    final image = _image;
    if (image != null) canvas.drawImageRect(image, _src, _dst, _blitPaint);
  }

  void dispose() {
    _disposeImage();
    _w = _h = _dpr = -1;
    _layout = null;
  }

  void _disposeImage() {
    _image?.dispose();
    _image = null;
  }

  void _cacheGeometry(BoardLayout layout) {
    final cell = layout.cellSize;
    exitRects.clear();
    platePositions.clear();
    plateRects.clear();
    plateCenters.clear();
    doorPositions.clear();
    doorRects.clear();
    doorTops.clear();
    doorBottoms.clear();
    final doorW = cell * 0.3;
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        final p = Position(x, y);
        final rect = layout.rectOf(p);
        switch (level.tileAt(p).kind) {
          case TileKind.exit:
            exitRects.add(rect.deflate(cell * 0.15));
          case TileKind.plate:
            platePositions.add(p);
            plateRects.add(
              RRect.fromRectAndRadius(
                rect.deflate(cell * 0.18),
                Radius.circular(cell * 0.12),
              ),
            );
            plateCenters.add(rect.center);
          case TileKind.door:
            doorPositions.add(p);
            final bar = Rect.fromCenter(
              center: rect.center,
              width: doorW,
              height: cell,
            );
            doorRects.add(bar);
            doorTops.add(bar.topLeft);
            doorBottoms.add(bar.bottomLeft);
          case TileKind.wall || TileKind.floor || TileKind.start:
            break;
        }
      }
    }
    doorHalfDown = Rect.fromLTWH(0, 0, doorW, cell / 2);
    doorHalfUp = Rect.fromLTWH(0, -cell / 2, doorW, cell / 2);
    ringRect = Rect.fromCircle(center: Offset.zero, radius: cell * 0.15);
  }

  void _record(BoardLayout layout, double w, double h, double dpr) {
    final pw = math.max(1, (w * dpr).ceil());
    final ph = math.max(1, (h * dpr).ceil());
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    final cell = layout.cellSize;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = palette.background,
    );
    final grid = Paint()
      ..color = palette.gridLine
      ..strokeWidth = 1;
    final o = layout.origin;
    final right = o.dx + cell * level.width;
    final bottom = o.dy + cell * level.height;
    for (var x = 0; x <= level.width; x++) {
      final dx = o.dx + x * cell;
      canvas.drawLine(Offset(dx, o.dy), Offset(dx, bottom), grid);
    }
    for (var y = 0; y <= level.height; y++) {
      final dy = o.dy + y * cell;
      canvas.drawLine(Offset(o.dx, dy), Offset(right, dy), grid);
    }
    final wall = Paint()..color = palette.wall;
    final exit = Paint()
      ..color = palette.exit
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.06;
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        final p = Position(x, y);
        switch (level.tileAt(p).kind) {
          case TileKind.wall:
            canvas.drawRect(layout.rectOf(p), wall);
          case TileKind.exit:
            canvas.drawRect(layout.rectOf(p).deflate(cell * 0.15), exit);
          case TileKind.plate ||
              TileKind.door ||
              TileKind.floor ||
              TileKind.start:
            break;
        }
      }
    }
    final picture = recorder.endRecording();
    _disposeImage();
    _image = picture.toImageSync(pw, ph);
    picture.dispose();
    _builds++;
    _src = Rect.fromLTWH(0, 0, pw.toDouble(), ph.toDouble());
    _dst = Rect.fromLTWH(0, 0, pw / dpr, ph / dpr);
  }
}

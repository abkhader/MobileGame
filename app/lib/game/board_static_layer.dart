import 'dart:math' as math;
import 'dart:ui';

import 'package:echo_core/echo_core.dart';

import 'board_layout.dart';
import 'palette.dart' as palette;

/// The parts of the board that never move: floor, grid, walls, exit
/// frames, laser emitters with their beat numbers and the cracked-floor
/// base, recorded once into an image at the screen's pixel density, plus
/// the per-tile geometry the animated layer reuses every frame. Holes,
/// beams and Shades change during play, so they are drawn live.
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

  /// Each spark's tile centre, in `level.sparks` order. Sparks change during
  /// play, so they are drawn live, never into the image.
  final List<Offset> sparkCenters = [];

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

  /// Laser tiles in reading order, each beat and the beam's two ends (just
  /// inside the emitters).
  final List<Position> laserPositions = [];
  final List<int> laserBeats = [];
  final List<Offset> beamStarts = [];
  final List<Offset> beamEnds = [];

  /// Cracked tiles in reading order and the hole each one leaves.
  final List<Position> crackedPositions = [];
  final List<RRect> holeRects = [];

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
    laserPositions.clear();
    laserBeats.clear();
    beamStarts.clear();
    beamEnds.clear();
    crackedPositions.clear();
    holeRects.clear();
    sparkCenters
      ..clear()
      ..addAll([for (final p in level.sparks) layout.centerOf(p)]);
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
    for (final p in _readingOrder(level.lasers.keys)) {
      final (a, b) = _emitterCentres(layout, p);
      final inset = (b - a) / (b - a).distance * (cell * 0.08);
      laserPositions.add(p);
      laserBeats.add(level.lasers[p]!);
      beamStarts.add(a + inset);
      beamEnds.add(b - inset);
    }
    for (final p in _readingOrder(level.cracked)) {
      crackedPositions.add(p);
      holeRects.add(
        RRect.fromRectAndRadius(
          layout.rectOf(p).deflate(cell * 0.1),
          Radius.circular(cell * 0.14),
        ),
      );
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
    _recordCracks(canvas, layout);
    _recordEmitters(canvas, layout);
    final picture = recorder.endRecording();
    _disposeImage();
    _image = picture.toImageSync(pw, ph);
    picture.dispose();
    _builds++;
    _src = Rect.fromLTWH(0, 0, pw.toDouble(), ph.toDouble());
    _dst = Rect.fromLTWH(0, 0, pw / dpr, ph / dpr);
  }

  static List<Position> _readingOrder(Iterable<Position> ps) =>
      ps.toList()..sort((a, b) => a.y != b.y ? a.y - b.y : a.x - b.x);

  bool _vertical(Position p) => laserBeamVertical(level, p);

  /// The emitters sit on the tile's two edges the beam spans, so each
  /// post straddles the wall face it is mounted on.
  (Offset, Offset) _emitterCentres(BoardLayout layout, Position p) {
    final r = layout.rectOf(p);
    return _vertical(p)
        ? (Offset(r.center.dx, r.top), Offset(r.center.dx, r.bottom))
        : (Offset(r.left, r.center.dy), Offset(r.right, r.center.dy));
  }

  /// Cracked tiles: a slightly lighter slab with a few cracks.
  void _recordCracks(Canvas canvas, BoardLayout layout) {
    if (level.cracked.isEmpty) return;
    final cell = layout.cellSize;
    final slab = Paint()..color = palette.cracked;
    final line = Paint()
      ..color = palette.crack
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, cell * 0.035)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final rr in holeRects) {
      canvas.drawRRect(rr, slab);
      final r = rr.outerRect;
      Offset at(double fx, double fy) =>
          Offset(r.left + r.width * fx, r.top + r.height * fy);
      final path = Path()
        ..moveTo(at(0.12, 0.3).dx, at(0.12, 0.3).dy)
        ..lineTo(at(0.38, 0.42).dx, at(0.38, 0.42).dy)
        ..lineTo(at(0.5, 0.2).dx, at(0.5, 0.2).dy)
        ..moveTo(at(0.38, 0.42).dx, at(0.38, 0.42).dy)
        ..lineTo(at(0.55, 0.62).dx, at(0.55, 0.62).dy)
        ..lineTo(at(0.86, 0.55).dx, at(0.86, 0.55).dy)
        ..moveTo(at(0.55, 0.62).dx, at(0.55, 0.62).dy)
        ..lineTo(at(0.45, 0.88).dx, at(0.45, 0.88).dy);
      canvas.drawPath(path, line);
    }
  }

  /// Two dark posts per laser, the beat number on the first.
  void _recordEmitters(Canvas canvas, BoardLayout layout) {
    if (level.lasers.isEmpty) return;
    final cell = layout.cellSize;
    final post = Paint()..color = palette.laserEmitter;
    final tip = Paint()..color = palette.laser;
    final size = cell * 0.16;
    for (var i = 0; i < laserPositions.length; i++) {
      final (a, b) = _emitterCentres(layout, laserPositions[i]);
      for (final c in [a, b]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: size, height: size),
            Radius.circular(size * 0.25),
          ),
          post,
        );
        canvas.drawCircle(c, size * 0.18, tip);
      }
      final builder =
          ParagraphBuilder(
              ParagraphStyle(
                textAlign: TextAlign.center,
                fontSize: math.max(8, cell * 0.2),
                fontWeight: FontWeight.w700,
              ),
            )
            ..pushStyle(TextStyle(color: palette.laserBeat))
            ..addText('${laserBeats[i]}');
      final paragraph = builder.build()
        ..layout(ParagraphConstraints(width: cell * 0.4));
      final r = layout.rectOf(laserPositions[i]);
      canvas.drawParagraph(
        paragraph,
        Offset(r.right - cell * 0.42, r.top + cell * 0.04),
      );
      paragraph.dispose();
    }
  }
}

/// Whether the laser at [p] draws its beam up and down (else left to
/// right). A beam is a gate across the path, its emitters on the walls:
///
/// * walls (or the board's edge) above and below, as in a horizontal
///   corridor: up and down, across the walkway;
/// * walls left and right, as in a vertical corridor: left to right;
/// * otherwise (open floor, a half-open tile, or walled on all four sides)
///   the beam crosses the axis with more walls next to it, hanging from a
///   lone wall above or below; on a tie (open floor) it runs left to right.
bool laserBeamVertical(Level level, Position p) {
  int wall(int dx, int dy) {
    final q = Position(p.x + dx, p.y + dy);
    return !level.inBounds(q) || level.tileAt(q).kind == TileKind.wall ? 1 : 0;
  }

  final ends = wall(0, -1) + wall(0, 1);
  final sides = wall(-1, 0) + wall(1, 0);
  if (ends == 2 && sides < 2) return true;
  if (sides == 2 && ends < 2) return false;
  return ends > sides;
}

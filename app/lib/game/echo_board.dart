import 'dart:math' as math;
import 'dart:ui';

import 'package:echo_core/echo_core.dart';
import 'package:flame/game.dart';

import '../art/pip.dart';
import 'board_effects.dart';
import 'board_layout.dart';
import 'flow_controller.dart';
import 'game_controller.dart';
import 'palette.dart' as palette;

/// Draws the level, echoes and Pip, gliding between beats.
///
/// Its game loop drives [flow] and runs only while time flows or a short
/// effect plays out; when time is frozen and everything has settled the
/// engine pauses, so a still board costs no frames. Any input or game change
/// wakes it.
class EchoBoard extends FlameGame {
  EchoBoard(this.flow, {bool reduceEffects = false})
    : _reduceEffects = reduceEffects,
      _pip = PipMotion(reduceEffects: reduceEffects);

  final FlowController flow;

  GameController get controller => flow.game;

  List<Position>? _hintPath;

  /// Cells to mark as a suggested route; null hides it.
  List<Position>? get hintPath => _hintPath;
  set hintPath(List<Position>? value) {
    _hintPath = value;
    wake();
  }

  bool _reduceEffects;

  /// No trails, shimmer, lean or squash. Motion and gliding stay.
  bool get reduceEffects => _reduceEffects;
  set reduceEffects(bool value) {
    if (value == _reduceEffects) return;
    _reduceEffects = value;
    _pip.reduceEffects = value;
    for (final t in _ghostTrails) {
      t.clear();
    }
    wake();
  }

  static const _batteryLowFraction = 0.2;
  static const _batteryFlashPeriod = 0.5;

  // Paints are reused every frame: render allocates no paints or paths.
  final _staticImagePaint = Paint()..filterQuality = FilterQuality.medium;
  final _exitGlowPaint = Paint()..style = PaintingStyle.stroke;
  final _platePaint = Paint();
  final _ripplePaint = Paint()..style = PaintingStyle.stroke;
  final _doorPaint = Paint();
  final _hintPaint = Paint()..color = palette.player.withValues(alpha: 0.4);
  final _trailPaint = Paint()..strokeCap = StrokeCap.round;
  final _shimmerPaint = Paint()..style = PaintingStyle.stroke;
  final _ringTrackPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final _flashPaint = Paint();

  // Effects.
  final PipMotion _pip;
  final _nudge = BumpNudge();
  final _bob = IdleBob();
  final _exitPulse = ExitPulse();
  final _winFlash = WinFlash();
  final Map<Position, DoorSlide> _doors = {};
  final Map<Position, PlateRipple> _ripples = {};
  final List<TrailBuffer> _ghostTrails = [];
  final List<Shimmer> _shimmers = [];
  Set<Position> _pressed = const {};
  double _flicker = 0;
  double _batteryPhase = 0;
  bool _wasFrozen = true;
  int _run = 0;

  // Interpolated positions in tiles, refreshed before each update and draw.
  Offset _pipTile = Offset.zero;
  final List<Offset> _ghostTiles = [];
  double _ticksUsed = 0;

  // Layout and the cached static layer (floor, walls, grid, exit frame).
  BoardLayout? _layout;
  Image? _static;
  Rect _staticSrc = Rect.zero;
  Rect _staticDst = Rect.zero;
  final List<Rect> _exitRects = [];
  final List<RRect> _plateRects = [];
  final List<Position> _platePositions = [];
  final List<Position> _doorPositions = [];

  /// Starts the engine again if it was paused. Safe to call often.
  void wake() {
    if (paused) resumeEngine();
  }

  @override
  void onMount() {
    super.onMount();
    _resetWorld();
    controller.addListener(_onGameChanged);
    flow.addListener(_onBeat);
    flow.bumps.addListener(_onBump);
  }

  @override
  void onRemove() {
    controller.removeListener(_onGameChanged);
    flow.removeListener(_onBeat);
    flow.bumps.removeListener(_onBump);
    _static?.dispose();
    _static = null;
    super.onRemove();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _invalidateLayout();
  }

  // --- Reacting to the game ---------------------------------------------

  void _resetWorld() {
    final state = controller.state;
    _run = state.runIndex;
    _doors.clear();
    for (final p in _doorPositionsOf(controller.level)) {
      _doors[p] = DoorSlide(open: state.openDoors.contains(p));
    }
    _ripples.clear();
    _pressed = _pressedPlates(state);
    _ghostTrails.clear();
    _shimmers.clear();
    for (var i = 0; i < state.ghostPositions.length; i++) {
      _ghostTrails.add(TrailBuffer());
      _shimmers.add(Shimmer());
    }
    _pip.reset();
    _winFlash.stop();
  }

  void _onGameChanged() {
    final state = controller.state;
    for (final entry in _doors.entries) {
      entry.value.target = state.openDoors.contains(entry.key);
    }
    final pressed = _pressedPlates(state);
    for (final p in pressed) {
      if (!_pressed.contains(p)) {
        (_ripples[p] ??= PlateRipple()).start();
      }
    }
    _pressed = pressed;

    final count = state.ghostPositions.length;
    if (state.runIndex != _run || count != _ghostTrails.length) {
      final before = state.runIndex > _run ? _ghostTrails.length : count;
      _run = state.runIndex;
      _ghostTrails
        ..clear()
        ..addAll([for (var i = 0; i < count; i++) TrailBuffer()]);
      _shimmers
        ..clear()
        ..addAll([for (var i = 0; i < count; i++) Shimmer()]);
      // Echoes new to this run shimmer in.
      if (!_reduceEffects) {
        for (var i = before; i < count; i++) {
          _shimmers[i].start();
        }
      }
      _pip.reset();
    }
    if (controller.lastEvent == GameEvent.won) _winFlash.start();
    wake();
  }

  /// Each beat: Pip's direction drives the lean, stretch and squash.
  void _onBeat() {
    final from = _sameRunFrom;
    final to = controller.state.player;
    var dir = Offset.zero;
    if (from != null && from.player != to) {
      dir = Offset(
        (to.x - from.player.x).sign.toDouble(),
        (to.y - from.player.y).sign.toDouble(),
      );
    }
    _pip.onBeat(dir);
    wake();
  }

  void _onBump() {
    final dir = switch (flow.bumpDir.value) {
      Move.up => const Offset(0, -1),
      Move.down => const Offset(0, 1),
      Move.left => const Offset(-1, 0),
      Move.right => const Offset(1, 0),
      Move.wait || null => Offset.zero,
    };
    _nudge.start(dir);
    wake();
  }

  GameState? get _sameRunFrom {
    final from = flow.from;
    if (from == null || from.runIndex != controller.state.runIndex) {
      return null;
    }
    return from;
  }

  Set<Position> _pressedPlates(GameState state) {
    final level = controller.level;
    return {
      for (final p in [state.player, ...state.ghostPositions])
        if (level.tileAt(p).kind == TileKind.plate) p,
    };
  }

  // --- Loop ---------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);
    flow.advance(dt);
    _syncPositions();

    final frozen = flow.frozen;
    if (frozen && !_wasFrozen) _pip.onStop();
    _wasFrozen = frozen;

    _pip.update(dt, _pipTile);
    _nudge.update(dt);
    _winFlash.update(dt);
    for (final d in _doors.values) {
      d.update(dt);
    }
    for (final r in _ripples.values) {
      r.update(dt);
    }
    for (var i = 0; i < _ghostTrails.length && i < _ghostTiles.length; i++) {
      final trail = _ghostTrails[i];
      final at = _ghostTiles[i];
      if (_reduceEffects) {
        trail.clear();
      } else if (trail.points.isNotEmpty && trail.points.last == at) {
        // Standing still (or frozen): the trail fades behind it.
        trail.shrink(dt * 3);
      } else {
        trail.add(at);
      }
      _shimmers[i].update(dt);
    }
    if (!frozen) {
      // Frozen means frozen mid-pose: these only run while time flows.
      _bob.update(dt);
      _exitPulse.update(dt);
      _flicker += dt;
      _batteryPhase = (_batteryPhase + dt) % _batteryFlashPeriod;
    }

    if (frozen && !_busy) pauseEngine();
  }

  /// A short effect is still playing out.
  bool get _busy {
    if (_pip.busy || _nudge.active || _winFlash.active) return true;
    for (final d in _doors.values) {
      if (d.active) return true;
    }
    for (final r in _ripples.values) {
      if (r.active) return true;
    }
    for (final s in _shimmers) {
      if (s.active) return true;
    }
    for (final t in _ghostTrails) {
      if (!t.isEmpty) return true;
    }
    return false;
  }

  void _syncPositions() {
    final state = controller.state;
    final from = _sameRunFrom;
    final t = flow.beatProgress;
    _pipTile = _tileLerp(from?.player ?? state.player, state.player, t);
    final ghosts = state.ghostPositions;
    final fromGhosts = from?.ghostPositions;
    final matched = fromGhosts != null && fromGhosts.length == ghosts.length;
    _ghostTiles.clear();
    for (var i = 0; i < ghosts.length; i++) {
      _ghostTiles.add(
        _tileLerp(matched ? fromGhosts[i] : ghosts[i], ghosts[i], t),
      );
    }
    final fromTick = from?.tick ?? state.tick;
    _ticksUsed = fromTick + (state.tick - fromTick) * t;
  }

  static Offset _tileLerp(Position a, Position b, double t) =>
      Offset(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);

  // --- Static layer -------------------------------------------------------

  void _invalidateLayout() {
    _layout = null;
    _static?.dispose();
    _static = null;
  }

  BoardLayout? _ensureLayout() {
    final cached = _layout;
    if (cached != null) return cached;
    final level = controller.level;
    final layout = BoardLayout(
      canvas: Size(size.x, size.y),
      columns: level.width,
      rows: level.height,
    );
    if (layout.cellSize <= 0) return null;
    _layout = layout;
    final cell = layout.cellSize;

    _exitRects.clear();
    _plateRects.clear();
    _platePositions.clear();
    _doorPositions.clear();
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        final p = Position(x, y);
        final rect = layout.rectOf(p);
        switch (level.tileAt(p).kind) {
          case TileKind.exit:
            _exitRects.add(rect.deflate(cell * 0.15));
          case TileKind.plate:
            _platePositions.add(p);
            _plateRects.add(
              RRect.fromRectAndRadius(
                rect.deflate(cell * 0.18),
                Radius.circular(cell * 0.12),
              ),
            );
          case TileKind.door:
            _doorPositions.add(p);
          case TileKind.wall || TileKind.floor || TileKind.start:
            break;
        }
      }
    }
    _exitGlowPaint
      ..strokeWidth = cell * 0.08
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.08);
    _ripplePaint.strokeWidth = math.max(1, cell * 0.04);
    _trailPaint.strokeWidth = cell * 0.22;
    _shimmerPaint.strokeWidth = math.max(1, cell * 0.05);
    _ringTrackPaint
      ..strokeWidth = math.max(1.5, cell * 0.035)
      ..color = palette.gridLine;
    _ringPaint.strokeWidth = math.max(1.5, cell * 0.035);

    _recordStatic(layout, level);
    return layout;
  }

  /// Floor, grid, walls and exit frames: drawn once into an image at the
  /// screen's pixel density, then blitted every frame.
  void _recordStatic(BoardLayout layout, Level level) {
    final w = size.x;
    final h = size.y;
    final dpr =
        PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
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
    _static?.dispose();
    _static = picture.toImageSync(pw, ph);
    picture.dispose();
    _staticSrc = Rect.fromLTWH(0, 0, pw.toDouble(), ph.toDouble());
    _staticDst = Rect.fromLTWH(0, 0, pw / dpr, ph / dpr);
  }

  static Iterable<Position> _doorPositionsOf(Level level) sync* {
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        final p = Position(x, y);
        if (level.tileAt(p).kind == TileKind.door) yield p;
      }
    }
  }

  // --- Drawing ------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final layout = _ensureLayout();
    final image = _static;
    if (layout == null || image == null) return;
    _syncPositions();
    final cell = layout.cellSize;
    final fx = !_reduceEffects;

    canvas.drawImageRect(image, _staticSrc, _staticDst, _staticImagePaint);

    // Exit glow pulses over the cached frame.
    final pulse = _exitPulse.value;
    _exitGlowPaint.color = palette.exit.withValues(alpha: 0.15 + 0.4 * pulse);
    for (final r in _exitRects) {
      canvas.drawRect(r, _exitGlowPaint);
    }

    // Plates, with a ripple when pressed.
    for (var i = 0; i < _plateRects.length; i++) {
      final p = _platePositions[i];
      final rrect = _plateRects[i];
      _platePaint.color = _pressed.contains(p)
          ? palette.platePressed
          : palette.plateIdle;
      canvas.drawRRect(rrect, _platePaint);
      final ripple = _ripples[p];
      if (ripple != null && ripple.active) {
        final k = ripple.progress;
        _ripplePaint.color = palette.platePressed.withValues(
          alpha: 0.8 * (1 - k),
        );
        canvas.drawCircle(rrect.center, cell * (0.25 + 0.4 * k), _ripplePaint);
      }
    }

    // Doors slide: the closed bar shrinks toward its ends as it opens.
    for (final p in _doorPositions) {
      final open = _doors[p]?.value ?? 0;
      final rect = layout.rectOf(p);
      final w = cell * 0.3;
      _doorPaint.color = palette.doorOpen;
      canvas.drawRect(
        Rect.fromCenter(center: rect.center, width: w, height: cell),
        _doorPaint,
      );
      if (open < 1) {
        final half = cell / 2 * (1 - open);
        _doorPaint.color = palette.doorClosed;
        final left = rect.center.dx - w / 2;
        canvas
          ..drawRect(Rect.fromLTWH(left, rect.top, w, half), _doorPaint)
          ..drawRect(
            Rect.fromLTWH(left, rect.bottom - half, w, half),
            _doorPaint,
          );
      }
    }

    final hint = _hintPath;
    if (hint != null) {
      for (final p in hint) {
        canvas.drawCircle(layout.centerOf(p), cell * 0.08, _hintPaint);
      }
    }

    // Echoes: trail, translucent flickering body, shimmer on arrival.
    for (var i = 0; i < _ghostTiles.length; i++) {
      final color = palette.ghostColors[i % palette.ghostColors.length];
      if (fx && i < _ghostTrails.length) {
        _drawTrail(canvas, layout, _ghostTrails[i], color, 0.35);
      }
      final center = _px(layout, _ghostTiles[i]);
      var opacity =
          0.55 * (0.92 + 0.08 * math.sin(_flicker * 23 + i * 2.1).abs());
      final shimmer = i < _shimmers.length ? _shimmers[i] : null;
      if (fx && shimmer != null && shimmer.active) {
        final k = shimmer.progress;
        opacity *= k;
        _shimmerPaint.color = color.withValues(alpha: 0.9 * (1 - k));
        canvas.drawCircle(center, cell * (0.3 + 0.35 * k), _shimmerPaint);
      }
      paintPip(canvas, center, cell * 0.3, color, opacity: opacity);
    }

    // Pip.
    if (fx) _drawTrail(canvas, layout, _pip.trail, palette.player, 0.45);
    // The bob is for standing still; a glide carries its own motion.
    final bob = _pip.moving ? 0.0 : _bob.offset;
    final pip = _px(layout, _pipTile) + _nudge.offset + Offset(0, bob);
    paintPip(
      canvas,
      pip,
      cell * 0.3,
      palette.player,
      lookDir: _pip.lookDir,
      lean: _pip.lean,
      stretch: _pip.stretch,
    );
    _drawBattery(canvas, pip, cell);

    if (_winFlash.active) {
      _flashPaint.color = palette.exit.withValues(
        alpha: 0.7 * (1 - _winFlash.progress),
      );
      canvas.drawRect(_staticDst, _flashPaint);
    }
  }

  Offset _px(BoardLayout layout, Offset tile) {
    final o = layout.origin;
    final c = layout.cellSize;
    return Offset(o.dx + (tile.dx + 0.5) * c, o.dy + (tile.dy + 0.5) * c);
  }

  void _drawTrail(
    Canvas canvas,
    BoardLayout layout,
    TrailBuffer trail,
    Color color,
    double alpha,
  ) {
    final points = trail.points;
    if (trail.isEmpty || points.length < 2) return;
    final n = points.length - 1;
    var prev = _px(layout, points[0]);
    for (var j = 1; j <= n; j++) {
      final next = _px(layout, points[j]);
      // Older segments fade out.
      _trailPaint.color = color.withValues(alpha: alpha * j / n);
      canvas.drawLine(prev, next, _trailPaint);
      prev = next;
    }
  }

  /// Moves left as a ring above Pip; it flashes red under 20 %.
  void _drawBattery(Canvas canvas, Offset pip, double cell) {
    const max = Rules.maxTicksPerRun;
    final left = ((max - _ticksUsed) / max).clamp(0.0, 1.0);
    final center = pip.translate(0, -cell * 0.62);
    final radius = cell * 0.09;
    canvas.drawCircle(center, radius, _ringTrackPaint);
    final low = left < _batteryLowFraction;
    final flashOn = _batteryPhase < _batteryFlashPeriod / 2;
    _ringPaint.color = low
        ? (flashOn ? palette.batteryLow : palette.batteryLowDim)
        : palette.platePressed;
    if (left <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * left,
      false,
      _ringPaint,
    );
  }
}

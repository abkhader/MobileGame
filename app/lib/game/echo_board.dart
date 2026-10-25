import 'dart:math' as math;
import 'dart:ui';

import 'package:echo_core/echo_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import '../art/pip.dart';
import 'board_effects.dart';
import 'board_layout.dart';
import 'board_static_layer.dart';
import 'flow_controller.dart';
import 'game_clock.dart';
import 'game_controller.dart';
import 'palette.dart' as palette;

/// Draws the level, echoes and Pip, gliding between beats.
///
/// Its game loop drives [flow] and runs only while time flows or a short
/// effect plays out; when time is frozen and everything has settled the
/// engine pauses, so a still board costs no frames. Any input or game change
/// wakes it.
class EchoBoard extends FlameGame {
  EchoBoard(
    this.flow, {
    bool reduceEffects = false,
    Duration Function()? beatLength,
  }) : _reduceEffects = reduceEffects,
       _beatLength = beatLength ?? (() => MoveSpeed.normal.beat),
       _pip = PipMotion(reduceEffects: reduceEffects),
       _layer = BoardStaticLayer(flow.game.level);

  final FlowController flow;
  final Duration Function() _beatLength;

  GameController get controller => flow.game;

  List<Position>? _hintPath;

  /// Cells to mark as a suggested route; null hides it.
  List<Position>? get hintPath => _hintPath;
  set hintPath(List<Position>? value) {
    _hintPath = value;
    wake();
  }

  bool _reduceEffects;

  /// No trails, shimmer, flicker, lean or squash; the battery warning and the
  /// win light hold steady. Motion and gliding stay.
  bool get reduceEffects => _reduceEffects;
  set reduceEffects(bool value) {
    if (value == _reduceEffects) return;
    _reduceEffects = value;
    _pip.reduceEffects = value;
    _fx.clearTrails();
    wake();
  }

  static const _echoOpacity = 0.55;
  static const _batteryLowFraction = 0.2;

  // Paints, colours and the trail path are reused: render allocates none.
  final _exitGlowPaint = Paint()..style = PaintingStyle.stroke;
  final _platePaint = Paint();
  final _ripplePaint = Paint()..style = PaintingStyle.stroke;
  final _doorPaint = Paint();
  final _hintPaint = Paint()..color = palette.player.withValues(alpha: 0.4);
  final _trailPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final _trailPath = Path();
  final _shimmerPaint = Paint()..style = PaintingStyle.stroke;
  final _ringTrackPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = palette.gridLine;
  final _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final _flashPaint = Paint();
  static final _echoRamps = [for (final c in palette.ghostColors) AlphaRamp(c)];
  static final _playerRamp = AlphaRamp(palette.player);
  static final _exitRamp = AlphaRamp(palette.exit);
  static final _plateRamp = AlphaRamp(palette.platePressed);

  final BoardStaticLayer _layer;
  double _cell = -1;

  final PipMotion _pip;
  final _fx = BoardEffects();
  Set<Position> _pressed = const {};
  bool _wasSettled = true;
  int _run = 0;

  // Interpolated positions in tiles, refreshed before each update and draw.
  Offset _pipTile = Offset.zero;
  final List<Offset> _ghostTiles = [];
  double _ticksUsed = 0;

  /// Starts the engine again if it was paused. Safe to call often.
  void wake() {
    if (paused) resumeEngine();
  }

  @visibleForTesting
  int get staticBuilds => _layer.builds;

  /// Where Pip is drawn, in tiles (before nudge and bob).
  @visibleForTesting
  Offset get pipTileForTesting => _pipTile;

  /// Where each echo is drawn, in tiles.
  @visibleForTesting
  List<Offset> get ghostTilesForTesting => List.unmodifiable(_ghostTiles);

  /// The push nudge, in logical px.
  @visibleForTesting
  Offset get nudgeOffsetForTesting => _fx.nudge.offset;

  @visibleForTesting
  double ghostOpacityForTesting(int i) => _ghostOpacity(i);

  /// How far the door at [p] is drawn open, 0 to 1.
  @visibleForTesting
  double doorOpenForTesting(Position p) => _fx.doors[p]?.value ?? 0;

  @visibleForTesting
  bool get winFlashActiveForTesting => _fx.winFlash.active;

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
    _layer.dispose();
    super.onRemove();
  }

  // --- Reacting to the game ---------------------------------------------

  void _resetWorld() {
    final state = controller.state;
    _run = state.runIndex;
    _fx.doors.clear();
    final level = controller.level;
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        final p = Position(x, y);
        if (level.tileAt(p).kind == TileKind.door) {
          _fx.doors[p] = DoorSlide(open: state.openDoors.contains(p));
        }
      }
    }
    _fx.ripples.clear();
    _pressed = _pressedPlates(state);
    _fx.resetEchoes(state.ghostPositions.length);
    _pip.reset();
    _fx.winFlash.stop();
  }

  void _onGameChanged() {
    final state = controller.state;
    final event = controller.lastEvent;
    final from = _sameRunFrom;
    final count = state.ghostPositions.length;
    final runChanged =
        state.runIndex != _run || count != _fx.ghostTrails.length;
    // Rewind steps are the only other event-less change; anything else
    // event-less is a restart.
    final rewindStep =
        event == GameEvent.none && from != null && from.tick == state.tick + 1;
    final reset = runChanged || (event == GameEvent.none && !rewindStep);

    for (final entry in _fx.doors.entries) {
      entry.value.target = state.openDoors.contains(entry.key);
      if (reset) entry.value.snap();
    }
    final pressed = _pressedPlates(state);
    if (!reset) {
      for (final p in pressed) {
        if (!_pressed.contains(p)) {
          (_fx.ripples[p] ??= PlateRipple()).start();
        }
      }
    }
    _pressed = pressed;

    if (runChanged) {
      // Echoes new to this run shimmer in.
      final before = state.runIndex > _run ? _fx.ghostTrails.length : count;
      _run = state.runIndex;
      _fx.resetEchoes(count, shimmerFrom: _reduceEffects ? count : before);
    }
    if (reset) {
      _pip.reset();
      _fx.winFlash.stop();
      _fx.finish.stop();
    }

    // The clock stops in the beat that ends the run: finish that glide here.
    if ((event == GameEvent.won || event == GameEvent.lost) && from != null) {
      _fx.finish.startFor(
        _beatLength().inMicroseconds / Duration.microsecondsPerSecond,
      );
    }
    if (event == GameEvent.won) _fx.winFlash.start();
    wake();
  }

  /// Each beat: Pip's direction drives the lean, stretch and squash.
  void _onBeat() {
    // A beat can start and end between two updates; it still needs its stop.
    _wasSettled = false;
    final from = _sameRunFrom;
    final state = controller.state;
    if (from != null && from.tick > state.tick) {
      _pip.onRewindBeat();
    } else {
      final to = state.player;
      var dir = Offset.zero;
      if (from != null && from.player != to) {
        dir = Offset(
          (to.x - from.player.x).sign.toDouble(),
          (to.y - from.player.y).sign.toDouble(),
        );
      }
      _pip.onBeat(dir);
    }
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
    _fx.nudge.start(dir);
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
    _fx.finish.update(dt);
    _syncPositions();

    final frozen = flow.frozen;
    final settled = frozen && !_fx.finish.active;
    if (settled && !_wasSettled) _pip.onStop();
    _wasSettled = settled;

    _pip.update(dt, _pipTile);
    _fx.update(
      dt,
      flowing: !frozen,
      ghostTiles: _ghostTiles,
      reduceEffects: _reduceEffects,
    );

    if (frozen && !_pip.busy && !_fx.busy) pauseEngine();
  }

  void _syncPositions() {
    final state = controller.state;
    final from = _sameRunFrom;
    final t = _fx.finish.active ? _fx.finish.progress : flow.beatProgress;
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

  double _ghostOpacity(int i) {
    if (_reduceEffects) return _echoOpacity;
    return _echoOpacity *
        (0.92 + 0.08 * math.sin(_fx.flicker * 23 + i * 2.1).abs());
  }

  // --- Drawing ------------------------------------------------------------

  /// Sizes the paints that scale with the cell; only when the cell changes.
  void _sizePaints(double cell) {
    if (cell == _cell) return;
    _cell = cell;
    _exitGlowPaint
      ..strokeWidth = cell * 0.08
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.08);
    _ripplePaint.strokeWidth = math.max(1, cell * 0.04);
    _trailPaint.strokeWidth = cell * 0.22;
    _shimmerPaint.strokeWidth = math.max(1, cell * 0.05);
    _ringTrackPaint.strokeWidth = math.max(1.5, cell * 0.035);
    _ringPaint.strokeWidth = math.max(1.5, cell * 0.035);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final dpr =
        PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
    final layout = _layer.ensure(size.x, size.y, dpr);
    if (layout == null) return;
    _syncPositions();
    final cell = layout.cellSize;
    _sizePaints(cell);
    final fx = !_reduceEffects;

    _layer.draw(canvas);

    // Exit glow pulses over the cached frame.
    _exitGlowPaint.color = _exitRamp.at(0.15 + 0.4 * _fx.exitPulse.value);
    for (final r in _layer.exitRects) {
      canvas.drawRect(r, _exitGlowPaint);
    }

    _drawPlates(canvas, cell);
    _drawDoors(canvas);

    final hint = _hintPath;
    if (hint != null) {
      for (final p in hint) {
        canvas.drawCircle(layout.centerOf(p), cell * 0.08, _hintPaint);
      }
    }

    // Echoes: trail, translucent flickering body, shimmer on arrival.
    for (var i = 0; i < _ghostTiles.length; i++) {
      final ramp = _echoRamps[i % _echoRamps.length];
      final color = palette.ghostColors[i % palette.ghostColors.length];
      if (fx && i < _fx.ghostTrails.length) {
        _drawTrail(canvas, layout, _fx.ghostTrails[i], ramp, 0.35);
      }
      final center = _px(layout, _ghostTiles[i]);
      var opacity = _ghostOpacity(i);
      final shimmer = i < _fx.shimmers.length ? _fx.shimmers[i] : null;
      if (fx && shimmer != null && shimmer.active) {
        final k = shimmer.progress;
        opacity *= k;
        _shimmerPaint.color = ramp.at(0.9 * (1 - k));
        canvas.drawCircle(center, cell * (0.3 + 0.35 * k), _shimmerPaint);
      }
      paintPip(canvas, center, cell * 0.3, color, opacity: opacity);
    }

    // Pip. The bob is for standing still; a glide carries its own motion.
    if (fx) _drawTrail(canvas, layout, _pip.trail, _playerRamp, 0.45);
    final bob = _pip.moving ? 0.0 : _fx.bob.offset;
    final pip = _px(layout, _pipTile) + _fx.nudge.offset + Offset(0, bob);
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

    final light = _fx.winLight(reduceEffects: _reduceEffects);
    if (light > 0) {
      _flashPaint.color = _exitRamp.at(light);
      canvas.drawRect(_layer.bounds, _flashPaint);
    }
  }

  void _drawPlates(Canvas canvas, double cell) {
    final plates = _layer.platePositions;
    for (var i = 0; i < plates.length; i++) {
      final p = plates[i];
      _platePaint.color = _pressed.contains(p)
          ? palette.platePressed
          : palette.plateIdle;
      canvas.drawRRect(_layer.plateRects[i], _platePaint);
      final ripple = _fx.ripples[p];
      if (ripple != null && ripple.active) {
        final k = ripple.progress;
        _ripplePaint.color = _plateRamp.at(0.8 * (1 - k));
        canvas.drawCircle(
          _layer.plateCenters[i],
          cell * (0.25 + 0.4 * k),
          _ripplePaint,
        );
      }
    }
  }

  /// Doors slide: the closed bar's halves shrink toward its ends.
  void _drawDoors(Canvas canvas) {
    final doors = _layer.doorPositions;
    for (var i = 0; i < doors.length; i++) {
      final open = _fx.doors[doors[i]]?.value ?? 0;
      _doorPaint.color = palette.doorOpen;
      canvas.drawRect(_layer.doorRects[i], _doorPaint);
      if (open >= 1) continue;
      _doorPaint.color = palette.doorClosed;
      final top = _layer.doorTops[i];
      final bottom = _layer.doorBottoms[i];
      canvas
        ..save()
        ..translate(top.dx, top.dy)
        ..scale(1, 1 - open)
        ..drawRect(_layer.doorHalfDown, _doorPaint)
        ..restore()
        ..save()
        ..translate(bottom.dx, bottom.dy)
        ..scale(1, 1 - open)
        ..drawRect(_layer.doorHalfUp, _doorPaint)
        ..restore();
    }
  }

  Offset _px(BoardLayout layout, Offset tile) {
    final o = layout.origin;
    final c = layout.cellSize;
    return Offset(o.dx + (tile.dx + 0.5) * c, o.dy + (tile.dy + 0.5) * c);
  }

  /// One smooth stroke along the trail, fading as it shortens.
  void _drawTrail(
    Canvas canvas,
    BoardLayout layout,
    TrailBuffer trail,
    AlphaRamp ramp,
    double alpha,
  ) {
    final points = trail.points;
    if (trail.isEmpty || points.length < 2) return;
    final o = layout.origin;
    final c = layout.cellSize;
    _trailPath.reset();
    for (var j = 0; j < points.length; j++) {
      final x = o.dx + (points[j].dx + 0.5) * c;
      final y = o.dy + (points[j].dy + 0.5) * c;
      if (j == 0) {
        _trailPath.moveTo(x, y);
      } else {
        _trailPath.lineTo(x, y);
      }
    }
    _trailPaint.color = ramp.at(alpha * trail.length / trail.maxLength);
    canvas.drawPath(_trailPath, _trailPaint);
  }

  /// Moves left as a ring above Pip; under 20 % it turns red and flashes
  /// (steady red with reduced effects).
  void _drawBattery(Canvas canvas, Offset pip, double cell) {
    const max = Rules.maxTicksPerRun;
    final left = ((max - _ticksUsed) / max).clamp(0.0, 1.0);
    final low = left < _batteryLowFraction;
    _ringPaint.color = !low
        ? palette.platePressed
        : _fx.batteryRedLit(reduceEffects: _reduceEffects)
        ? palette.batteryLow
        : palette.batteryLowDim;
    canvas
      ..save()
      ..translate(pip.dx, pip.dy - cell * 0.62)
      ..drawOval(_layer.ringRect, _ringTrackPaint);
    if (left > 0) {
      canvas.drawArc(
        _layer.ringRect,
        -math.pi / 2,
        2 * math.pi * left,
        false,
        _ringPaint,
      );
    }
    canvas.restore();
  }
}

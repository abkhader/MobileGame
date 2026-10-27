import 'dart:math' as math;
import 'dart:ui';

import 'package:echo_core/echo_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import '../art/pip.dart';
import '../art/spark_star.dart';
import '../hints/hint_service.dart';
import 'board_effects.dart';
import 'board_layout.dart';
import 'board_static_layer.dart';
import 'flow_controller.dart';
import 'game_clock.dart';
import 'game_controller.dart';
import 'hits.dart';
import 'palette.dart' as palette;

/// Draws the level, echoes, Shades and Pip, gliding between beats, and the
/// dangers: laser beams, holes in cracked floor, hits.
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

  List<HintStep>? _hintSteps;

  /// The next beats of the suggested route; null or empty hides it. Drawn
  /// statically: setting it repaints once, nothing animates while frozen.
  List<HintStep>? get hintSteps => _hintSteps;
  set hintSteps(List<HintStep>? value) {
    _hintSteps = value;
    wake();
  }

  bool _reduceEffects;

  /// No trails, shimmer, flicker, lean or squash, no Shade wobble, dust,
  /// hit flash or beam glow fades; the battery warning and the win light
  /// hold steady. Motion and gliding stay.
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
  final _exitGlowPaint = Paint()..filterQuality = FilterQuality.low;
  final _platePaint = Paint();
  final _ripplePaint = Paint()..style = PaintingStyle.stroke;
  final _doorPaint = Paint();
  final _hintRamp = AlphaRamp(palette.player);
  final _hintPaint = Paint();
  final _hintGlowPaint = Paint();
  final _hintLinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final _hintShape = Path();
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
  final _sparkPaint = Paint();
  final _sparkCorePaint = Paint();
  final _sparkGlowPaint = Paint();
  final _motePaint = Paint();
  static final _sparkRamp = AlphaRamp(palette.spark);
  static final _sparkCoreRamp = AlphaRamp(palette.sparkCore);
  static final _echoRamps = [for (final c in palette.ghostColors) AlphaRamp(c)];
  static final _playerRamp = AlphaRamp(palette.player);
  static final _exitRamp = AlphaRamp(palette.exit);
  static final _whiteRamp = AlphaRamp(const Color(0xFFFFFFFF));
  static final _plateRamp = AlphaRamp(palette.platePressed);
  static final _laserRamp = AlphaRamp(palette.laser);
  static final _laserCoreRamp = AlphaRamp(palette.laserCore);
  static final _dustRamp = AlphaRamp(palette.dust);
  static final _shadeGlowRamp = AlphaRamp(palette.shadeGlow);
  static final _shadeEyesRamp = AlphaRamp(palette.shadeEyes);

  final _beamGlowPaint = Paint()..strokeCap = StrokeCap.round;
  final _beamPaint = Paint()..strokeCap = StrokeCap.round;
  final _holePaint = Paint()..color = palette.hole;
  final _holeRimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..color = palette.holeRim;
  final _dustPaint = Paint();
  final _shadePaint = Paint()..color = palette.shadeBody;
  final _shadeGlowPaint = Paint();
  final _shadeEyePaint = Paint();
  final _shadePath = Path();
  final _hitPaint = Paint();
  final _hitMotePaint = Paint();
  static final _hitDarkRamp = AlphaRamp(palette.shadeGlow);

  final BoardStaticLayer _layer;
  double _cell = -1;

  // The exit's blurred outline, baked once per exit size; the pulse only
  // changes the paint's alpha, so no blur runs per frame.
  Image? _exitGlow;
  Rect _exitGlowSrc = Rect.zero;
  double _exitGlowMargin = 0;
  Size _exitGlowSize = Size.zero;
  double _exitGlowDpr = 0;
  int _exitGlowBakes = 0;

  /// Battery ring stroke, in cells (its radius, 0.15 cells, is in the
  /// static layer's ringRect).
  static const _ringStroke = 0.058;

  final PipMotion _pip;
  final _fx = BoardEffects();
  Set<Position> _pressed = const {};
  int _sparkMask = 0;
  bool _wasSettled = true;
  int _run = 0;

  // Interpolated positions in tiles, refreshed before each update and draw.
  Offset _pipTile = Offset.zero;
  final List<Offset> _ghostTiles = [];
  final List<Offset> _shadeTiles = [];
  double _ticksUsed = 0;

  /// Unit direction each Shade's eyes look: toward its next step. Worked out
  /// once per state change (the rule walks distance fields), never per
  /// frame.
  List<Offset> _shadeLook = const [];

  /// The holes as last seen, to spot new ones.
  Set<Position> _holes = const {};

  /// Laser beam level per laser now: 0 dark, [_warnLevel] warning, 1 firing.
  double _beamT = 1;
  static const _warnLevel = 0.3;

  /// Shade wobble, in fractions of its radius.
  static const _wobble = 0.08;

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

  @visibleForTesting
  int get exitGlowBakesForTesting => _exitGlowBakes;

  /// The battery ring's radius and stroke width, in cells.
  @visibleForTesting
  (double, double) get batteryRingForTesting =>
      (_layer.ringRect.width / 2 / _cell, _ringPaint.strokeWidth / _cell);

  /// Spark [i] is drawn on its tile (not yet collected, or Pip is still
  /// gliding onto it).
  @visibleForTesting
  bool sparkVisibleForTesting(int i) => _sparkDrawn(i);

  /// A collect burst is playing (or waiting for Pip to arrive).
  @visibleForTesting
  bool get sparkBurstActiveForTesting => _fx.sparkBursts.any((b) => b.active);

  /// Spark [i]'s centre in the board's logical px, or null before layout.
  Offset? sparkCenter(int i) {
    final layout = _layer.layout;
    final sparks = controller.level.sparks;
    if (layout == null || i < 0 || i >= sparks.length) return null;
    return layout.centerOf(sparks[i]);
  }

  /// One tile's size in logical px, or 0 before layout.
  double get cellSize => _layer.layout?.cellSize ?? 0;

  @visibleForTesting
  double get pipLeanForTesting => _pip.lean;

  @visibleForTesting
  double get pipStretchForTesting => _pip.stretch;

  /// Echo [i] is drawn: alive, or still fizzling out.
  @visibleForTesting
  bool ghostDrawnForTesting(int i) => _ghostDrawn(i);

  @visibleForTesting
  bool ghostFizzlingForTesting(int i) =>
      i < _fx.fizzles.length && _fx.fizzles[i].active;

  /// The hole at [p] is drawn (it shows once its dust starts).
  @visibleForTesting
  bool holeDrawnForTesting(Position p) => _holeDrawn(p);

  @visibleForTesting
  bool dustActiveForTesting(Position p) => _fx.dust[p]?.active ?? false;

  @visibleForTesting
  bool get hitBurstActiveForTesting => _fx.hitBurst.active;

  /// Where each Shade is drawn, in tiles.
  @visibleForTesting
  List<Offset> get shadeTilesForTesting => List.unmodifiable(_shadeTiles);

  /// Where each Shade's eyes look.
  @visibleForTesting
  List<Offset> get shadeLookForTesting => List.unmodifiable(_shadeLook);

  /// The first Shade's wobble now, in fractions of its radius: 0 with
  /// reduced effects.
  @visibleForTesting
  double get shadeWobbleForTesting => _wobbleAt(0, 0);

  /// The beam level of the laser at [p] (0 dark, 0.3 warning, 1 firing),
  /// as drawn now without its crackle.
  @visibleForTesting
  double laserGlowForTesting(Position p) {
    _syncPositions();
    final beat = controller.level.lasers[p];
    return beat == null ? 0 : _beamLevel(beat);
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
    _layer.dispose();
    _exitGlow?.dispose();
    _exitGlow = null;
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
    _fx.resetSparks(level.sparks.length);
    _sparkMask = controller.sparkMask;
    _fx.resetEchoes(state.ghostPositions.length);
    _fx.resetDust(level.cracked);
    _holes = state.holes;
    _shadeLook = _lookOf(state);
    _pip.reset();
    _fx.winFlash.stop();
  }

  /// Each Shade's next step, as a unit direction (zero when it waits).
  static List<Offset> _lookOf(GameState state) {
    if (state.shades.isEmpty) return const [];
    final next = Rules.shadeLookahead(state);
    return [
      for (var i = 0; i < next.length; i++)
        Offset(
          (next[i].x - state.shades[i].x).toDouble(),
          (next[i].y - state.shades[i].y).toDouble(),
        ),
    ];
  }

  void _onGameChanged() {
    final state = controller.state;
    final event = controller.lastEvent;
    final from = _sameRunFrom;
    final count = state.ghostPositions.length;
    final runChanged =
        state.runIndex != _run || count != _fx.ghostTrails.length;
    final reset = runChanged || event == GameEvent.restarted;

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

    // Sparks: a new one bursts as Pip lands on it; one dropped by a rewind
    // grows back in; a restart just puts them all back.
    final mask = controller.sparkMask;
    if (event == GameEvent.restarted) {
      _fx.stopSparks();
    } else if (!_reduceEffects && mask != _sparkMask) {
      // Sparks are only grabbed by a forward step: wait until Pip is half
      // way onto the tile.
      final delay =
          _beatLength().inMicroseconds / Duration.microsecondsPerSecond / 2;
      for (var i = 0; i < _fx.sparkBursts.length; i++) {
        final bit = 1 << i;
        if (mask & bit != 0 && _sparkMask & bit == 0) {
          _fx.sparkReturns[i].stop();
          _fx.sparkBursts[i].startAfter(delay);
        } else if (mask & bit == 0 && _sparkMask & bit != 0) {
          _fx.sparkBursts[i].stop();
          _fx.sparkReturns[i].start();
        }
      }
    }
    _sparkMask = mask;

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
      _fx.stopDangers();
    }
    _onDangers(state, event, reset);

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

  /// Holes, echo hits and Pip's hit on a change. A forward beat starts
  /// their effects; a rewind stops the ones it undid. Everything drawn
  /// follows the state, so a rewind restores it all.
  void _onDangers(GameState state, GameEvent event, bool reset) {
    _shadeLook = _lookOf(state);
    final forward =
        event == GameEvent.moved ||
        event == GameEvent.won ||
        event == GameEvent.lost;
    final halfBeat =
        _beatLength().inMicroseconds / Duration.microsecondsPerSecond / 2;
    final fx = !_reduceEffects;

    for (final entry in _fx.dust.entries) {
      final p = entry.key;
      if (!state.holes.contains(p)) {
        entry.value.stop();
      } else if (forward && !reset && !_holes.contains(p) && fx) {
        // The floor breaks once the actor on it is half way off.
        entry.value.startAfter(halfBeat);
      }
    }
    _holes = state.holes;

    final alive = state.ghostAlive;
    for (var i = 0; i < _fx.fizzles.length && i < alive.length; i++) {
      if (alive[i]) _fx.fizzles[i].stop();
    }
    if (forward && !reset) {
      for (final i in state.lastHits.ghosts) {
        if (i < _fx.fizzles.length) _fx.fizzles[i].startAfter(halfBeat);
      }
    }

    final hit = controller.lastPipHit;
    if (hit != null && fx && (event == GameEvent.hit || forward)) {
      // A loss glides onto the tile first; a forced rewind has snapped Pip
      // back, so the flash marks where he fell at once.
      _fx.hitBurst.startAt(
        hit.at,
        dark: hit.cause == HitCause.shade,
        delay: event == GameEvent.hit ? 0 : halfBeat,
      );
    } else if (event == GameEvent.none || event == GameEvent.restarted) {
      _fx.hitBurst.stop();
    }
  }

  Set<Position> _pressedPlates(GameState state) {
    final level = controller.level;
    // A dead echo presses nothing.
    return {
      if (level.tileAt(state.player).kind == TileKind.plate) state.player,
      for (var i = 0; i < state.ghostPositions.length; i++)
        if (state.ghostAlive[i] &&
            level.tileAt(state.ghostPositions[i]).kind == TileKind.plate)
          state.ghostPositions[i],
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
    final shades = state.shades;
    final fromShades = from?.shades;
    _shadeTiles.clear();
    for (var i = 0; i < shades.length; i++) {
      _shadeTiles.add(_tileLerp(fromShades?[i] ?? shades[i], shades[i], t));
    }
    final fromTick = from?.tick ?? state.tick;
    _ticksUsed = fromTick + (state.tick - fromTick) * t;
    _beamT = t;
  }

  /// The beam level for a laser of [beat]: it fades between beats while
  /// time flows (a frozen board is a still frame), and switches outright
  /// with reduced effects.
  double _beamLevel(int beat) {
    final tick = controller.state.tick;
    final to = _laserLevel(beat, tick);
    final from = _sameRunFrom;
    if (_reduceEffects || from == null || from.tick == tick) return to;
    return _laserLevel(beat, from.tick) +
        (to - _laserLevel(beat, from.tick)) * _beamT;
  }

  static double _laserLevel(int beat, int tick) => Rules.laserFires(beat, tick)
      ? 1
      : Rules.laserWarns(beat, tick)
      ? _warnLevel
      : 0;

  /// Shade [i]'s wobble at point [k] of its outline, in fractions of its
  /// radius. It moves only while time flows.
  double _wobbleAt(int i, int k) => _reduceEffects
      ? 0
      : _wobble * math.sin(_fx.flicker * 5 + k * 1.7 + i * 2.3);

  bool _ghostDrawn(int i) {
    final alive = controller.state.ghostAlive;
    if (i >= alive.length) return false;
    return alive[i] || (i < _fx.fizzles.length && _fx.fizzles[i].active);
  }

  bool _holeDrawn(Position p) =>
      controller.state.holes.contains(p) && !(_fx.dust[p]?.waiting ?? false);

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
    _ripplePaint.strokeWidth = math.max(1, cell * 0.04);
    _trailPaint.strokeWidth = cell * 0.22;
    _shimmerPaint.strokeWidth = math.max(1, cell * 0.05);
    _ringTrackPaint.strokeWidth = math.max(2, cell * _ringStroke);
    _ringPaint.strokeWidth = math.max(2, cell * _ringStroke);
  }

  /// Bakes the exit's glowing outline for exits of [size] (all exits share
  /// one size), only when that size or the pixel ratio changes.
  void _bakeExitGlow(Size size, double cell, double dpr) {
    if (size == _exitGlowSize && dpr == _exitGlowDpr && _exitGlow != null) {
      return;
    }
    _exitGlowSize = size;
    _exitGlowDpr = dpr;
    _exitGlow?.dispose();
    _exitGlowBakes++;
    final stroke = cell * 0.08;
    final sigma = cell * 0.08;
    final margin = stroke / 2 + sigma * 3 + 1;
    final pw = math.max(1, ((size.width + margin * 2) * dpr).ceil());
    final ph = math.max(1, ((size.height + margin * 2) * dpr).ceil());
    final recorder = PictureRecorder();
    Canvas(recorder)
      ..scale(dpr)
      ..drawRect(
        Rect.fromLTWH(margin, margin, size.width, size.height),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = palette.exit
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
      );
    final picture = recorder.endRecording();
    _exitGlow = picture.toImageSync(pw, ph);
    picture.dispose();
    _exitGlowSrc = Rect.fromLTWH(0, 0, pw.toDouble(), ph.toDouble());
    _exitGlowMargin = margin;
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

    // Exit glow pulses over the cached frame: a baked image whose alpha
    // follows the pulse.
    final exits = _layer.exitRects;
    if (exits.isNotEmpty) {
      _bakeExitGlow(exits.first.size, cell, dpr);
      _exitGlowPaint.color = _whiteRamp.at(0.15 + 0.4 * _fx.exitPulse.value);
      for (final r in exits) {
        canvas.drawImageRect(
          _exitGlow!,
          _exitGlowSrc,
          r.inflate(_exitGlowMargin),
          _exitGlowPaint,
        );
      }
    }

    _drawHoles(canvas, cell);
    _drawPlates(canvas, cell);
    _drawDoors(canvas);
    _drawBeams(canvas, cell);
    _drawSparks(canvas, cell);

    final hint = _hintSteps;
    if (hint != null && hint.isNotEmpty) _drawHint(canvas, layout, hint, cell);

    // Echoes: trail, translucent flickering body, shimmer on arrival. A hit
    // echo fizzles out and is gone.
    for (var i = 0; i < _ghostTiles.length; i++) {
      if (!_ghostDrawn(i)) continue;
      final ramp = _echoRamps[i % _echoRamps.length];
      final color = palette.ghostColors[i % palette.ghostColors.length];
      if (fx && i < _fx.ghostTrails.length) {
        _drawTrail(canvas, layout, _fx.ghostTrails[i], ramp, 0.35);
      }
      var center = _px(layout, _ghostTiles[i]);
      var opacity = _ghostOpacity(i);
      final fizzle = i < _fx.fizzles.length ? _fx.fizzles[i] : null;
      if (fizzle != null && fizzle.active && !fizzle.waiting) {
        final k = fizzle.progress;
        opacity *= 1 - k;
        // A crackling jitter as it goes (none with reduced effects).
        if (fx) center += Offset(math.sin(k * 71 + i) * cell * 0.04, 0);
      }
      final shimmer = i < _fx.shimmers.length ? _fx.shimmers[i] : null;
      if (fx && shimmer != null && shimmer.active) {
        final k = shimmer.progress;
        opacity *= k;
        _shimmerPaint.color = ramp.at(0.9 * (1 - k));
        canvas.drawCircle(center, cell * (0.3 + 0.35 * k), _shimmerPaint);
      }
      paintPip(canvas, center, cell * 0.3, color, opacity: opacity);
    }

    _drawShades(canvas, layout, cell);

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
    _drawHit(canvas, layout, cell);

    final light = _fx.winLight(reduceEffects: _reduceEffects);
    if (light > 0) {
      _flashPaint.color = _exitRamp.at(light);
      canvas.drawRect(_layer.bounds, _flashPaint);
    }
  }

  /// Holes where cracked floor fell in, with a puff of dust as it breaks.
  void _drawHoles(Canvas canvas, double cell) {
    final tiles = _layer.crackedPositions;
    if (tiles.isEmpty) return;
    _holeRimPaint.strokeWidth = math.max(1, cell * 0.04);
    for (var i = 0; i < tiles.length; i++) {
      final p = tiles[i];
      if (_holeDrawn(p)) {
        final rr = _layer.holeRects[i];
        canvas
          ..drawRRect(rr, _holePaint)
          ..drawRRect(rr, _holeRimPaint);
      }
      final puff = _fx.dust[p];
      if (puff == null || !puff.active || puff.waiting) continue;
      final k = puff.progress;
      final out = 1 - (1 - k) * (1 - k);
      final center = _layer.holeRects[i].center;
      _dustPaint.color = _dustRamp.at(0.7 * (1 - k));
      final dist = cell * (0.1 + 0.35 * out);
      final mote = cell * (0.07 + 0.05 * k);
      // Rising a little as it spreads; unit directions scaled, so no offset
      // is built per mote.
      canvas
        ..save()
        ..translate(center.dx, center.dy - cell * 0.15 * k)
        ..scale(dist);
      for (final d in DustPuff.directions) {
        canvas.drawCircle(d, mote / dist, _dustPaint);
      }
      canvas.restore();
    }
  }

  /// Each laser's beam: a dim glow on the beat before it fires, a bright
  /// crackling beam on its beat.
  void _drawBeams(Canvas canvas, double cell) {
    final beats = _layer.laserBeats;
    if (beats.isEmpty) return;
    final fx = !_reduceEffects;
    for (var i = 0; i < beats.length; i++) {
      final level = _beamLevel(beats[i]);
      if (level <= 0.01) continue;
      final a = _layer.beamStarts[i];
      final b = _layer.beamEnds[i];
      // The glow builds with the level; the core only shows once it fires.
      _beamGlowPaint
        ..strokeWidth = cell * (0.12 + 0.14 * level)
        ..color = _laserRamp.at(0.6 * level);
      canvas.drawLine(a, b, _beamGlowPaint);
      final core = ((level - _warnLevel) / (1 - _warnLevel)).clamp(0.0, 1.0);
      if (core <= 0) continue;
      final crackle = fx && !flow.frozen
          ? 0.75 + 0.25 * math.sin(_fx.flicker * 90 + i * 1.3)
          : 1.0;
      _beamPaint
        ..strokeWidth = cell * 0.05 * crackle
        ..color = _laserCoreRamp.at(core);
      canvas.drawLine(a, b, _beamPaint);
    }
  }

  /// Shades: a dark, wobbling blob with two violet eyes on its next step.
  void _drawShades(Canvas canvas, BoardLayout layout, double cell) {
    final r = cell * 0.32;
    for (var i = 0; i < _shadeTiles.length; i++) {
      final c = _px(layout, _shadeTiles[i]);
      _shadeGlowPaint.color = _shadeGlowRamp.at(0.35);
      canvas.drawCircle(c, r * 1.18, _shadeGlowPaint);
      // A smooth closed outline through midpoints of 8 wobbling points.
      const n = 8;
      _shadePath.reset();
      for (var k = 0; k <= n; k++) {
        final a0 = 2 * math.pi * (k % n) / n;
        final a1 = 2 * math.pi * ((k + 1) % n) / n;
        final r0 = r * (1 + _wobbleAt(i, k % n));
        final r1 = r * (1 + _wobbleAt(i, (k + 1) % n));
        final px = c.dx + math.cos(a0) * r0;
        final py = c.dy + math.sin(a0) * r0;
        final mx = (px + c.dx + math.cos(a1) * r1) / 2;
        final my = (py + c.dy + math.sin(a1) * r1) / 2;
        if (k == 0) {
          _shadePath.moveTo(mx, my);
        } else {
          _shadePath.quadraticBezierTo(px, py, mx, my);
        }
      }
      _shadePath.close();
      canvas.drawPath(_shadePath, _shadePaint);
      // Two eyes side by side, shifted toward the next step.
      final look = i < _shadeLook.length ? _shadeLook[i] : Offset.zero;
      final ex = c.dx + look.dx * r * 0.3;
      final ey = c.dy + look.dy * r * 0.3 - r * 0.08;
      final side = r * 0.3;
      final eye = r * 0.14;
      _shadeEyePaint.color = _shadeEyesRamp.at(1);
      canvas
        ..drawCircle(Offset(ex - side, ey), eye, _shadeEyePaint)
        ..drawCircle(Offset(ex + side, ey), eye, _shadeEyePaint);
    }
  }

  /// Where Pip was hit: his flash fading out and a burst of sparks (dark
  /// and violet for a Shade's catch). None with reduced effects.
  void _drawHit(Canvas canvas, BoardLayout layout, double cell) {
    final burst = _fx.hitBurst;
    if (!burst.active || burst.waiting) return;
    final k = burst.progress;
    final center = layout.centerOf(burst.tile);
    final ramp = burst.dark ? _hitDarkRamp : _whiteRamp;
    _hitPaint.color = ramp.at(0.8 * (1 - k));
    canvas.drawCircle(center, cell * (0.3 + 0.35 * k), _hitPaint);
    paintPip(
      canvas,
      center,
      cell * 0.3,
      burst.dark ? palette.shadeBody : palette.player,
      opacity: 1 - k,
    );
    final out = 1 - (1 - k) * (1 - k);
    _hitMotePaint.color = (burst.dark ? _shadeEyesRamp : _sparkCoreRamp).at(
      1 - k,
    );
    final dist = cell * (0.15 + 0.5 * out);
    final mote = cell * 0.06 * (1 - 0.6 * k);
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(dist);
    for (final d in SparkBurst.directions) {
      canvas.drawCircle(d, mote / dist, _hitMotePaint);
    }
    canvas.restore();
  }

  bool _sparkDrawn(int i) {
    final collected = _sparkMask & (1 << i) != 0;
    return !collected || _fx.sparkBursts[i].waiting;
  }

  /// Uncollected sparks twinkle on their tiles (steady with reduced
  /// effects); a collected one bursts into motes. Paths and paints are
  /// cached: nothing is allocated here.
  void _drawSparks(Canvas canvas, double cell) {
    final centers = _layer.sparkCenters;
    final fx = !_reduceEffects;
    final r = cell * 0.2;
    for (var i = 0; i < centers.length && i < _fx.sparkBursts.length; i++) {
      final center = centers[i];
      if (_sparkDrawn(i)) {
        var alpha = 1.0;
        var scale = 1.0;
        if (fx) {
          final k = _fx.twinkle.at(i);
          alpha = 0.7 + 0.3 * k;
          scale = 0.88 + 0.14 * k;
          final back = _fx.sparkReturns[i];
          if (back.active) {
            alpha *= back.progress;
            scale *= 0.4 + 0.6 * back.progress;
          }
        }
        _drawStar(canvas, center, r * scale, alpha);
        continue;
      }
      final burst = _fx.sparkBursts[i];
      if (!burst.active) continue;
      final k = burst.progress;
      // The star pops (grows and fades) while motes fly out.
      if (k < 0.4) _drawStar(canvas, center, r * (1 + k * 1.5), 1 - k / 0.4);
      final out = 1 - (1 - k) * (1 - k);
      _motePaint.color = _sparkCoreRamp.at(1 - k);
      final dist = cell * (0.12 + 0.38 * out);
      final mote = cell * 0.05 * (1 - 0.6 * k);
      // Scaled so the shared unit directions are the mote centres: no
      // offsets are built per mote.
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..scale(dist);
      for (final d in SparkBurst.directions) {
        canvas.drawCircle(d, mote / dist, _motePaint);
      }
      canvas.restore();
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, double alpha) {
    _sparkGlowPaint.color = _sparkRamp.at(0.22 * alpha);
    canvas.drawCircle(center, r * 1.15, _sparkGlowPaint);
    _sparkPaint.color = _sparkRamp.at(alpha);
    _sparkCorePaint.color = _sparkCoreRamp.at(alpha);
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(r)
      ..drawPath(unitSparkStar, _sparkPaint)
      ..scale(0.45)
      ..drawPath(unitSparkStar, _sparkCorePaint)
      ..restore();
  }

  /// A glowing dotted path; a push is an arrow against the obstacle and a
  /// wait an hourglass. Later beats are fainter. Static: no animation.
  void _drawHint(
    Canvas canvas,
    BoardLayout layout,
    List<HintStep> steps,
    double cell,
  ) {
    _hintLinePaint.strokeWidth = cell * 0.07;
    final stacked = <Position, int>{};
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final a = 1.0 - 0.18 * i;
      final from = layout.centerOf(step.from);
      if (step.move == Move.wait) {
        final n = stacked[step.from] = (stacked[step.from] ?? 0) + 1;
        _drawHourglass(
          canvas,
          from + Offset(cell * 0.3, -cell * 0.3 - (n - 1) * cell * 0.2),
          cell * 0.11,
          a,
        );
      } else if (step.blocked) {
        final n = stacked[step.from] = (stacked[step.from] ?? 0) + 1;
        _drawPushArrow(canvas, from, step.move, cell, a, n - 1);
      } else {
        final to = layout.centerOf(step.to);
        _hintPaint.color = _hintRamp.at(0.55 * a);
        _hintGlowPaint.color = _hintRamp.at(0.25 * a);
        for (final k in const [0.25, 0.5, 0.75]) {
          canvas.drawCircle(Offset.lerp(from, to, k)!, cell * 0.04, _hintPaint);
        }
        canvas.drawCircle(to, cell * 0.2, _hintGlowPaint);
        canvas.drawCircle(to, cell * 0.09, _hintPaint);
      }
    }
  }

  void _drawPushArrow(
    Canvas canvas,
    Offset from,
    Move dir,
    double cell,
    double a,
    int n,
  ) {
    final (dx, dy) = switch (dir) {
      Move.up => (0.0, -1.0),
      Move.down => (0.0, 1.0),
      Move.left => (-1.0, 0.0),
      _ => (1.0, 0.0),
    };
    // Tail near Pip, head at the tile edge: it presses on the obstacle.
    final d = Offset(dx, dy);
    final side = Offset(-dy, dx);
    final off = side * (cell * 0.12 * n);
    final tail = from + d * (cell * 0.22) + off;
    final head = from + d * (cell * 0.46) + off;
    _hintLinePaint.color = _hintRamp.at(0.8 * a);
    canvas.drawLine(tail, head, _hintLinePaint);
    _hintShape
      ..reset()
      ..moveTo(head.dx, head.dy)
      ..lineTo(
        head.dx - d.dx * cell * 0.14 + side.dx * cell * 0.1,
        head.dy - d.dy * cell * 0.14 + side.dy * cell * 0.1,
      )
      ..lineTo(
        head.dx - d.dx * cell * 0.14 - side.dx * cell * 0.1,
        head.dy - d.dy * cell * 0.14 - side.dy * cell * 0.1,
      )
      ..close();
    _hintPaint.color = _hintRamp.at(0.8 * a);
    canvas.drawPath(_hintShape, _hintPaint);
  }

  /// Two triangles tip to tip: the wait marker.
  void _drawHourglass(Canvas canvas, Offset c, double r, double a) {
    _hintShape
      ..reset()
      ..moveTo(c.dx - r, c.dy - r * 1.4)
      ..lineTo(c.dx + r, c.dy - r * 1.4)
      ..lineTo(c.dx, c.dy)
      ..lineTo(c.dx + r, c.dy + r * 1.4)
      ..lineTo(c.dx - r, c.dy + r * 1.4)
      ..lineTo(c.dx, c.dy)
      ..close();
    _hintPaint.color = _hintRamp.at(0.85 * a);
    canvas.drawPath(_hintShape, _hintPaint);
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
      ..translate(pip.dx, pip.dy - cell * 0.72)
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

import 'dart:math' as math;
import 'dart:ui';

import 'package:echo_core/echo_core.dart';

/// The board's short effects as pure, time-driven state. Each is advanced by
/// `update(dt)` (seconds) from the board's game loop and read while drawing,
/// so the math is testable without running Flame. Positions on the board are
/// in tile units.

/// Something that plays once over [duration] seconds after [start].
class OneShot {
  OneShot(this.duration);

  double duration;
  double _t = 0;
  bool _active = false;

  bool get active => _active;

  /// Seconds since [start].
  double get elapsed => _t;

  /// 0 to 1 while running; 1 when done or never started.
  double get progress => _active ? (_t / duration).clamp(0.0, 1.0) : 1;

  void start() {
    _t = 0;
    _active = true;
  }

  void update(double dt) {
    if (!_active) return;
    _t += dt;
    if (_t + 1e-9 >= duration) {
      _t = duration;
      _active = false;
    }
  }

  void stop() => _active = false;
}

/// A push: Pip presses [maxDistance] px toward the obstacle and back.
class BumpNudge extends OneShot {
  BumpNudge() : super(0.12);

  static const maxDistance = 4.0;

  Offset _dir = Offset.zero;

  /// Starts a nudge; [dir] is a unit step toward the obstacle.
  @override
  void start([Offset dir = Offset.zero]) {
    _dir = dir;
    super.start();
  }

  /// Logical px toward the obstacle: a triangle peaking half way.
  double get distance {
    if (!active) return 0;
    final half = duration / 2;
    return maxDistance * (1 - ((elapsed - half).abs() / half)).clamp(0.0, 1.0);
  }

  Offset get offset => _dir * distance;
}

/// A door sliding open (1) or shut (0) over 150 ms.
class DoorSlide {
  DoorSlide({required bool open}) : _target = open, _value = open ? 1 : 0;

  static const duration = 0.15;

  bool _target;
  double _value;

  /// 0 closed, 1 open.
  double get value => _value;

  bool get active => _value != (_target ? 1 : 0);

  set target(bool open) => _target = open;

  /// Jumps to the target, e.g. on a level restart.
  void snap() => _value = _target ? 1 : 0;

  void update(double dt) {
    final goal = _target ? 1.0 : 0.0;
    final step = dt / duration;
    _value = _value < goal
        ? math.min(goal, _value + step)
        : math.max(goal, _value - step);
    if ((_value - goal).abs() < 1e-9) _value = goal;
  }
}

/// A ring spreading from a plate as it is pressed.
class PlateRipple extends OneShot {
  PlateRipple() : super(0.3);
}

/// The light an echo appears in at the start of a run.
class Shimmer extends OneShot {
  Shimmer() : super(0.3);
}

/// The light flooding the board on a win.
class WinFlash extends OneShot {
  WinFlash() : super(0.4);
}

/// The last glide of a run that ended on its beat (a win or a loss): the
/// clock stops in that same beat, so the board times the glide itself.
class FinishGlide extends OneShot {
  FinishGlide() : super(0.2);

  /// Starts a glide lasting [seconds].
  void startFor(double seconds) {
    duration = seconds;
    start();
  }
}

/// A collected spark bursting into a few motes of light. It waits [delay]
/// seconds first (Pip is still gliding onto the tile), then plays 300 ms.
/// The motes fly along fixed directions, so nothing is allocated per frame.
class SparkBurst extends OneShot {
  SparkBurst() : super(0.3);

  static const motes = 6;

  /// Unit directions of the motes, shared by every burst.
  static final List<Offset> directions = List.generate(motes, (i) {
    final a = 2 * math.pi * i / motes + math.pi / 6;
    return Offset(math.cos(a), math.sin(a));
  }, growable: false);

  double _wait = 0;

  /// Still waiting for Pip: the spark is drawn whole.
  bool get waiting => active && _wait > 0;

  void startAfter(double delay) {
    _wait = math.max(0, delay);
    start();
  }

  @override
  void stop() {
    _wait = 0;
    super.stop();
  }

  @override
  void update(double dt) {
    if (!active) return;
    if (_wait > 0) {
      _wait -= dt;
      if (_wait > 0) return;
      dt = -_wait;
      _wait = 0;
    }
    super.update(dt);
  }
}

/// A spark coming back on a rewind: it grows in as the star flies back.
class SparkReturn extends OneShot {
  SparkReturn() : super(0.3);
}

/// The sparks' twinkle: each spark breathes on its own phase, only while
/// time flows.
class SparkTwinkle {
  static const period = 1.4;

  double _t = 0;

  /// 0 to 1 for spark [i].
  double at(int i) => 0.5 + 0.5 * math.sin(2 * math.pi * _t / period + i * 2.1);

  void update(double dt) => _t = (_t + dt) % period;
}

/// [color] at 33 opacity steps, built once, so drawing a fading colour every
/// frame allocates nothing.
class AlphaRamp {
  AlphaRamp(Color color)
    : _steps = List.generate(
        _count + 1,
        (i) => color.withValues(alpha: color.a * i / _count),
        growable: false,
      );

  static const _count = 32;

  final List<Color> _steps;

  /// The colour at [alpha] (0 to 1) of its own opacity.
  Color at(double alpha) => _steps[(alpha.clamp(0.0, 1.0) * _count).round()];
}

/// The exit's glow: 0 to 1 and back every 1.2 s.
class ExitPulse {
  static const period = 1.2;

  double _t = 0;

  double get value => 0.5 - 0.5 * math.cos(2 * math.pi * _t / period);

  void update(double dt) => _t = (_t + dt) % period;
}

/// Pip's resting bob: 2 px top to bottom every 1.6 s.
class IdleBob {
  static const period = 1.6;
  static const height = 2.0;

  double _t = 0;

  /// Vertical px, between -1 and 1.
  double get offset => height / 2 * math.sin(2 * math.pi * _t / period);

  void update(double dt) => _t = (_t + dt) % period;
}

/// The recent path of a moving thing, at most [maxLength] tiles long.
/// Samples are kept oldest first.
class TrailBuffer {
  TrailBuffer({this.maxLength = 0.4});

  final double maxLength;

  final List<Offset> _points = [];
  double _length = 0;

  List<Offset> get points => _points;

  /// Path length in tiles.
  double get length => _length;

  bool get isEmpty => _length <= 1e-6;

  void clear() {
    _points.clear();
    _length = 0;
  }

  /// Adds the newest position. A jump of more than a tile (a new run, a
  /// restart) starts a fresh trail instead of streaking across the board.
  void add(Offset p) {
    if (_points.isEmpty) {
      _points.add(p);
      return;
    }
    final step = (p - _points.last).distance;
    if (step <= 1e-9) return;
    if (step > 1.0 + 1e-6) {
      clear();
      _points.add(p);
      return;
    }
    _points.add(p);
    _length += step;
    _trim(maxLength);
  }

  /// Fades the tail by [amount] tiles, e.g. while Pip stands still.
  void shrink(double amount) {
    if (_points.isEmpty) return;
    _trim(math.max(0, _length - amount));
    if (isEmpty) {
      final last = _points.last;
      clear();
      _points.add(last);
    }
  }

  void _trim(double keep) {
    while (_points.length > 1 && _length > keep + 1e-9) {
      final a = _points[0];
      final b = _points[1];
      final seg = (b - a).distance;
      final excess = _length - keep;
      if (seg <= excess + 1e-9) {
        _points.removeAt(0);
        _length -= seg;
      } else {
        // Cut the oldest segment so exactly [keep] remains.
        _points[0] = Offset.lerp(a, b, excess / seg)!;
        _length = keep;
      }
    }
    if (_length < 0) _length = 0;
  }
}

/// Pip's body language: lean, stretch/squash, gaze and light trail.
class PipMotion {
  PipMotion({this.reduceEffects = false});

  static const maxLean = 8 * math.pi / 180;
  static const startStretch = 0.08;
  static const stopSquash = -0.10;
  static const _kickDuration = 0.16;

  /// Tiles of trail faded per second once Pip stops.
  static const _fadeRate = 3.0;

  /// When true there is no trail, lean or squash; the eye still turns.
  bool reduceEffects;

  final TrailBuffer trail = TrailBuffer();

  Offset _travel = Offset.zero;
  Offset _look = Offset.zero;
  double _lean = 0;
  double _kick = 0;
  double _kickT = _kickDuration;
  Offset? _last;
  bool _rewinding = false;

  /// True while the current beat carries Pip to another tile, forward or
  /// back.
  bool get moving => _travel != Offset.zero || _rewinding;

  /// Unit direction the eye looks; the last travel direction.
  Offset get lookDir => _look;

  /// Radians; positive leans right.
  double get lean => reduceEffects ? 0 : _lean;

  /// Along travel: positive stretches, negative squashes.
  double get stretch {
    if (reduceEffects || _kickT >= _kickDuration) return 0;
    return _kick * (1 - _kickT / _kickDuration);
  }

  /// True while lean, squash or trail are still settling.
  bool get busy =>
      !reduceEffects &&
      (_lean.abs() > 1e-3 || _kickT < _kickDuration || !trail.isEmpty);

  /// A beat began; [dir] is the unit step Pip takes (zero when it stays).
  void onBeat(Offset dir) {
    _rewinding = false;
    if (dir != Offset.zero) {
      if (_travel == Offset.zero) {
        _startKick(startStretch);
      } else if (dir != _travel) {
        _startKick(stopSquash);
      }
      _look = dir;
    } else if (_travel != Offset.zero) {
      _startKick(stopSquash);
    }
    _travel = dir;
  }

  /// A rewind beat: Pip glides back still facing forward, with no lean or
  /// stretch kick.
  void onRewindBeat() {
    _travel = Offset.zero;
    _rewinding = true;
  }

  /// Time froze after the last beat.
  void onStop() {
    _rewinding = false;
    if (_travel != Offset.zero) _startKick(stopSquash);
    _travel = Offset.zero;
  }

  /// Forgets the pose, e.g. on restart.
  void reset() {
    _travel = Offset.zero;
    _rewinding = false;
    _lean = 0;
    _kickT = _kickDuration;
    _last = null;
    trail.clear();
  }

  /// Advances by [dt] seconds with Pip now at [position] (tiles).
  void update(double dt, Offset position) {
    _kickT = math.min(_kickDuration, _kickT + dt);
    final target = _travel.dx * maxLean;
    _lean += (target - _lean) * math.min(1, dt * 18);
    if ((_lean - target).abs() < 1e-4) _lean = target;

    if (reduceEffects) {
      trail.clear();
    } else if (_last != position) {
      trail.add(position);
    } else {
      trail.shrink(dt * _fadeRate);
    }
    _last = position;
  }

  void _startKick(double amount) {
    _kick = amount;
    _kickT = 0;
  }
}

/// Every world effect on the board, advanced together. Pip's own body
/// language lives in [PipMotion].
class BoardEffects {
  static const batteryFlashPeriod = 0.5;

  final nudge = BumpNudge();
  final bob = IdleBob();
  final exitPulse = ExitPulse();
  final winFlash = WinFlash();
  final finish = FinishGlide();
  final Map<Position, DoorSlide> doors = {};
  final Map<Position, PlateRipple> ripples = {};
  final List<TrailBuffer> ghostTrails = [];
  final List<Shimmer> shimmers = [];
  final twinkle = SparkTwinkle();

  /// One burst and one return per spark of the level, made once.
  final List<SparkBurst> sparkBursts = [];
  final List<SparkReturn> sparkReturns = [];

  /// Seconds of flowing time, for the echo flicker.
  double flicker = 0;

  /// Position within the low-battery flash.
  double batteryPhase = 0;

  /// The low-battery warning shows full red now: in the flash's lit half,
  /// or always when effects are reduced.
  bool batteryRedLit({required bool reduceEffects}) =>
      reduceEffects || batteryPhase < batteryFlashPeriod / 2;

  /// Opacity of the win light over the board: a fading flood of light, or a
  /// steady glow when effects are reduced.
  double winLight({required bool reduceEffects}) {
    if (!winFlash.active) return 0;
    return reduceEffects ? 0.3 : 0.7 * (1 - winFlash.progress);
  }

  /// Fresh trails and shimmers for [count] echoes; those from [shimmerFrom]
  /// on shimmer in.
  void resetEchoes(int count, {int? shimmerFrom}) {
    ghostTrails
      ..clear()
      ..addAll([for (var i = 0; i < count; i++) TrailBuffer()]);
    shimmers
      ..clear()
      ..addAll([for (var i = 0; i < count; i++) Shimmer()]);
    for (var i = shimmerFrom ?? count; i < count; i++) {
      shimmers[i].start();
    }
  }

  /// Fresh burst and return slots for [count] sparks.
  void resetSparks(int count) {
    sparkBursts
      ..clear()
      ..addAll([for (var i = 0; i < count; i++) SparkBurst()]);
    sparkReturns
      ..clear()
      ..addAll([for (var i = 0; i < count; i++) SparkReturn()]);
  }

  /// Ends every spark effect at once, e.g. on a restart.
  void stopSparks() {
    for (final b in sparkBursts) {
      b.stop();
    }
    for (final r in sparkReturns) {
      r.stop();
    }
  }

  void clearTrails() {
    for (final t in ghostTrails) {
      t.clear();
    }
  }

  /// Advances one-shots, door slides and echo trails. Looping effects (bob,
  /// exit pulse, flicker, spark twinkle, battery flash) run only while time
  /// [flowing].
  void update(
    double dt, {
    required bool flowing,
    required List<Offset> ghostTiles,
    required bool reduceEffects,
  }) {
    nudge.update(dt);
    winFlash.update(dt);
    for (final d in doors.values) {
      d.update(dt);
    }
    for (final r in ripples.values) {
      r.update(dt);
    }
    for (final b in sparkBursts) {
      b.update(dt);
    }
    for (final r in sparkReturns) {
      r.update(dt);
    }
    for (var i = 0; i < ghostTrails.length && i < ghostTiles.length; i++) {
      final trail = ghostTrails[i];
      final at = ghostTiles[i];
      if (reduceEffects) {
        trail.clear();
      } else if (trail.points.isNotEmpty && trail.points.last == at) {
        // Standing still (or frozen): the trail fades behind it.
        trail.shrink(dt * 3);
      } else {
        trail.add(at);
      }
      shimmers[i].update(dt);
    }
    if (flowing) {
      bob.update(dt);
      exitPulse.update(dt);
      flicker += dt;
      twinkle.update(dt);
      batteryPhase = (batteryPhase + dt) % batteryFlashPeriod;
    }
  }

  /// A short effect is still playing out.
  bool get busy {
    if (nudge.active || winFlash.active || finish.active) return true;
    for (final d in doors.values) {
      if (d.active) return true;
    }
    for (final r in ripples.values) {
      if (r.active) return true;
    }
    for (final s in shimmers) {
      if (s.active) return true;
    }
    for (final b in sparkBursts) {
      if (b.active) return true;
    }
    for (final r in sparkReturns) {
      if (r.active) return true;
    }
    for (final t in ghostTrails) {
      if (!t.isEmpty) return true;
    }
    return false;
  }
}

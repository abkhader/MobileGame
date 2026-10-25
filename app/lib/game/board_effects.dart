import 'dart:math' as math;
import 'dart:ui';

/// The board's short effects as pure, time-driven state. Each is advanced by
/// `update(dt)` (seconds) from the board's game loop and read while drawing,
/// so the math is testable without running Flame. Positions on the board are
/// in tile units.

/// Something that plays once over [duration] seconds after [start].
class OneShot {
  OneShot(this.duration);

  final double duration;
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

  /// True while the current beat carries Pip to another tile.
  bool get moving => _travel != Offset.zero;

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

  /// Time froze after the last beat.
  void onStop() {
    if (_travel != Offset.zero) _startKick(stopSquash);
    _travel = Offset.zero;
  }

  /// Forgets the pose, e.g. on restart.
  void reset() {
    _travel = Offset.zero;
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

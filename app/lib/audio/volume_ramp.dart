import 'dart:async';

/// Fades a volume in small timed steps. A new target cancels the fade in
/// progress and starts from wherever it had got to. Errors from [_set] are
/// swallowed: a fade must never break the game.
class VolumeRamp {
  VolumeRamp(
    this._set, {
    required double initial,
    this.step = const Duration(milliseconds: 25),
  }) : _volume = initial;

  final FutureOr<void> Function(double volume) _set;
  final Duration step;

  double _volume;
  Timer? _timer;

  /// The level last applied (or set by [jump]).
  double get volume => _volume;

  /// Fades from the current level to [target] over [over].
  void to(double target, Duration over) {
    _timer?.cancel();
    _timer = null;
    final from = _volume;
    if (from == target) return;
    final steps = (over.inMicroseconds / step.inMicroseconds).ceil().clamp(
      1,
      1000,
    );
    var i = 0;
    _timer = Timer.periodic(step, (timer) {
      i++;
      final v = i >= steps ? target : from + (target - from) * i / steps;
      _volume = v;
      _apply(v);
      if (i >= steps) {
        timer.cancel();
        if (identical(_timer, timer)) _timer = null;
      }
    });
  }

  /// Records [volume] as the current level without fading, e.g. when the
  /// music starts at it.
  void jump(double volume) {
    _timer?.cancel();
    _timer = null;
    _volume = volume;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void _apply(double v) {
    try {
      final result = _set(v);
      if (result is Future<void>) unawaited(result.catchError((_) {}));
    } catch (_) {}
  }
}

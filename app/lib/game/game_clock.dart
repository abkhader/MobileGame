import 'package:echo_core/echo_core.dart';

/// How fast Pip moves: the length of one game beat.
enum MoveSpeed {
  slow(300),
  normal(200),
  fast(140);

  const MoveSpeed(this._millis);

  final int _millis;

  Duration get beat => Duration(milliseconds: _millis);
}

enum IntentKind { none, move, wait, rewind }

/// Turns a held input into game beats. Driven only by [advance], so it is
/// deterministic in tests. Rewind beats are half the beat length.
class GameClock {
  GameClock({
    required Duration Function() beatLength,
    required void Function(IntentKind kind, Move? dir) onBeat,
  }) : _beatLength = beatLength,
       _onBeat = onBeat;

  /// Most beats fired by a single [advance], so a long stall (a resumed tab)
  /// does not fast-forward the game.
  static const maxBeatsPerAdvance = 3;

  static const _epsilon = 1e-9;

  final Duration Function() _beatLength;
  final void Function(IntentKind kind, Move? dir) _onBeat;

  IntentKind _kind = IntentKind.none;
  Move? _dir;
  bool _running = false;
  double _elapsed = 0;
  double _beatSeconds = 0;

  bool get running => _running;

  /// 0-1 within the current beat; 1 when idle.
  double get beatProgress {
    if (!_running || _beatSeconds <= 0) return 1;
    return (_elapsed / _beatSeconds).clamp(0.0, 1.0);
  }

  void setIntent(IntentKind kind, [Move? dir]) {
    _kind = kind;
    _dir = kind == IntentKind.none ? null : dir;
    if (kind != IntentKind.none && !_running) {
      _running = true;
      _elapsed = 0;
      _fire();
    }
  }

  void advance(double dtSeconds) {
    if (!_running || dtSeconds <= 0) return;
    _elapsed += dtSeconds;
    var fired = 0;
    while (_running && _elapsed + _epsilon >= _beatSeconds) {
      if (_kind == IntentKind.none) {
        _idle();
        return;
      }
      if (fired >= maxBeatsPerAdvance) {
        // Drop the rest of a long stall instead of replaying it.
        _elapsed = 0;
        return;
      }
      _elapsed = (_elapsed - _beatSeconds).clamp(0.0, double.infinity);
      fired++;
      _fire();
    }
  }

  void stop() {
    _kind = IntentKind.none;
    _dir = null;
    _idle();
  }

  void _idle() {
    _running = false;
    _elapsed = 0;
  }

  void _fire() {
    final micros = _beatLength().inMicroseconds;
    final length = _kind == IntentKind.rewind ? micros / 2 : micros.toDouble();
    _beatSeconds = length / Duration.microsecondsPerSecond;
    _onBeat(_kind, _dir);
  }
}

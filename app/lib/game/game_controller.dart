import 'package:echo_core/echo_core.dart';
import 'package:flutter/foundation.dart';

/// What the last change was. [restarted] marks a level restart, so listeners
/// never have to infer it.
enum GameEvent { none, moved, runEnded, won, lost, restarted }

/// Wraps the engine [Rules] for the UI, with a per-run undo stack.
class GameController extends ChangeNotifier {
  GameController(this.level) : _state = GameState.initial(level);

  final Level level;
  final List<GameState> _undoStack = [];

  GameState _state;
  GameState? _previous;
  GameEvent _lastEvent = GameEvent.none;

  GameState get state => _state;

  /// The state before the last move; null tells the board to snap.
  GameState? get previous => _previous;

  GameEvent get lastEvent => _lastEvent;

  bool get _playing => _state.status == GameStatus.playing;

  bool get canUndo => _playing && _undoStack.isNotEmpty;

  bool get canEndRun => _playing && _state.tick > 0;

  int? get stars => _state.status == GameStatus.won
      ? Scoring.stars(
          score: _state.score,
          best: level.bestScore ?? _state.score,
        )
      : null;

  /// Bit i set while this play holds spark i (in `level.sparks` order).
  int get sparkMask => sparkMaskOf(_state);

  /// The spark bits [s] holds.
  int sparkMaskOf(GameState s) {
    final sparks = level.sparks;
    var mask = 0;
    for (var i = 0; i < sparks.length; i++) {
      if (s.collected.contains(sparks[i])) mask |= 1 << i;
    }
    return mask;
  }

  /// True when [m] would leave Pip in place (wall, closed door, edge). Uses
  /// the rules' own logic. Waiting is never blocked, and nothing is once the
  /// level is won or lost (the rules refuse to step then).
  bool isBlocked(Move m) =>
      _playing &&
      m != Move.wait &&
      Rules.step(_state, m).player == _state.player;

  void move(Move m) {
    if (!_playing) return;
    final before = _state;
    final after = Rules.step(before, m);
    final runChanged = after.runIndex != before.runIndex;
    _state = after;
    if (runChanged || after.status != GameStatus.playing) {
      _undoStack.clear();
    } else {
      _undoStack.add(before);
    }
    _previous = runChanged ? null : before;
    _lastEvent = switch (after.status) {
      GameStatus.won => GameEvent.won,
      GameStatus.lost => GameEvent.lost,
      GameStatus.playing => runChanged ? GameEvent.runEnded : GameEvent.moved,
    };
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _state = _undoStack.removeLast();
    _previous = null;
    _lastEvent = GameEvent.none;
    notifyListeners();
  }

  void endRun() {
    if (!canEndRun) return;
    _state = Rules.endRun(_state);
    _undoStack.clear();
    _previous = null;
    _lastEvent = _state.status == GameStatus.lost
        ? GameEvent.lost
        : GameEvent.runEnded;
    notifyListeners();
  }

  void restart() {
    _state = GameState.initial(level);
    _undoStack.clear();
    _previous = null;
    _lastEvent = GameEvent.restarted;
    notifyListeners();
  }
}

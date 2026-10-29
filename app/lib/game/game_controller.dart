import 'package:echo_core/echo_core.dart';
import 'package:flutter/foundation.dart';

import 'hits.dart';

/// What the last change was. [restarted] marks a level restart, so listeners
/// never have to infer it. [hit] is a forced rewind: Pip was hit and his run
/// ended there (a hit on the last run is [lost], with `lastHits.pip` set).
enum GameEvent { none, moved, runEnded, hit, won, lost, restarted }

/// Wraps the engine [Rules] for the UI, with a per-run undo stack.
///
/// Undo also steps back across a forced rewind, through app-only history:
/// the rules and the solver know nothing of it. A run the player ended
/// (New echo), the tick cap and a restart stay hard boundaries.
class GameController extends ChangeNotifier {
  GameController(this.level) : _state = GameState.initial(level);

  final Level level;
  final List<GameState> _undoStack = [];

  /// One entry per forced rewind since the last voluntary run end: the
  /// state just before the fatal beat and that run's undo stack, newest
  /// last. Undo at the start of a run a hit began pops one.
  final List<(GameState, List<GameState>)> _hitHistory = [];
  (GameState, GameState)? _fatalBeat;

  GameState _state;
  GameState? _previous;
  GameEvent _lastEvent = GameEvent.none;
  PipHit? _lastPipHit;

  GameState get state => _state;

  /// The state before the last move; null tells the board to snap.
  GameState? get previous => _previous;

  GameEvent get lastEvent => _lastEvent;

  /// Where and why Pip was hit on the last change; null unless that change
  /// was a step that hit him ([GameEvent.hit], or a hit [GameEvent.lost]).
  PipHit? get lastPipHit => _lastPipHit;

  /// On a forced rewind ([GameEvent.hit]) only: the state before the step
  /// and the beat as it hit ([Rules.stepInRun]: Pip on the tile that hit
  /// him, echoes and Shades where they were), so the board can play the
  /// fatal beat before snapping to the new run. Null after any other change.
  (GameState, GameState)? get fatalBeat => _fatalBeat;

  bool get _playing => _state.status == GameStatus.playing;

  /// Undo steps back one beat in this run, or, at the start of a run a hit
  /// began, back to the state just before that hit.
  bool get canUndo =>
      _playing && (_undoStack.isNotEmpty || _hitHistory.isNotEmpty);

  /// New echo works at tick 0 while runs remain (a 0-move echo waits on the
  /// start); Give up on the final run needs at least one beat, so it is
  /// never an accidental instant loss.
  bool get canEndRun =>
      _playing && (_state.tick > 0 || _state.runIndex < level.runLimit - 1);

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
  /// the rules' own movement, so a step into a danger is not a push. Waiting
  /// is never blocked, and nothing is once the level is won or lost.
  bool isBlocked(Move m) =>
      _playing &&
      m != Move.wait &&
      Rules.moveTarget(level, _state.player, m, _state.openDoors) ==
          _state.player;

  void move(Move m) {
    if (!_playing) return;
    final before = _state;
    final after = Rules.step(before, m);
    final runChanged = after.runIndex != before.runIndex;
    _state = after;
    final forced =
        runChanged && after.lastHits.pip && after.status == GameStatus.playing;
    if (forced) {
      _hitHistory.add((before, List.of(_undoStack)));
    } else if (runChanged) {
      // The tick cap ended the run: a boundary like New echo.
      _hitHistory.clear();
    }
    if (runChanged || after.status != GameStatus.playing) {
      _undoStack.clear();
    } else {
      _undoStack.add(before);
    }
    _previous = runChanged ? null : before;
    _lastPipHit = pipHitOf(before, after);
    _fatalBeat = forced ? (before, Rules.stepInRun(before, m)) : null;
    _lastEvent = switch (after.status) {
      GameStatus.won => GameEvent.won,
      GameStatus.lost => GameEvent.lost,
      GameStatus.playing =>
        !runChanged
            ? GameEvent.moved
            : after.lastHits.pip
            ? GameEvent.hit
            : GameEvent.runEnded,
    };
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    if (_undoStack.isNotEmpty) {
      _state = _undoStack.removeLast();
    } else {
      final (preHit, stack) = _hitHistory.removeLast();
      _state = preHit;
      _undoStack.addAll(stack);
    }
    _previous = null;
    _lastPipHit = null;
    _fatalBeat = null;
    _lastEvent = GameEvent.none;
    notifyListeners();
  }

  void endRun() {
    if (!canEndRun) return;
    _state = Rules.endRun(_state);
    _undoStack.clear();
    _hitHistory.clear();
    _previous = null;
    _lastPipHit = null;
    _fatalBeat = null;
    _lastEvent = _state.status == GameStatus.lost
        ? GameEvent.lost
        : GameEvent.runEnded;
    notifyListeners();
  }

  void restart() {
    _state = GameState.initial(level);
    _undoStack.clear();
    _hitHistory.clear();
    _previous = null;
    _lastPipHit = null;
    _fatalBeat = null;
    _lastEvent = GameEvent.restarted;
    notifyListeners();
  }
}

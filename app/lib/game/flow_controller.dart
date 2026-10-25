import 'package:echo_core/echo_core.dart';
import 'package:flutter/foundation.dart';

import 'game_clock.dart';
import 'game_controller.dart';

/// Where a held input comes from. Each source holds its own intents, so a
/// key release never drops what the joystick still holds.
enum InputSource { joystick, keys, button }

/// Maps clock beats onto [GameController]: move, wait and rewind.
class FlowController extends ChangeNotifier {
  FlowController({required this.game, required MoveSpeed Function() speed}) {
    clock = GameClock(beatLength: () => speed().beat, onBeat: _onBeat);
    game.addListener(_onGameChanged);
  }

  final GameController game;
  late final GameClock clock;

  final ValueNotifier<int> _bumps = ValueNotifier(0);
  final ValueNotifier<Move?> _bumpDir = ValueNotifier(null);
  final ValueNotifier<bool> _frozenN = ValueNotifier(true);
  final ValueNotifier<bool> _rewinding = ValueNotifier(false);
  GameState? _from;

  /// Increments on each bump.
  ValueListenable<int> get bumps => _bumps;
  ValueListenable<Move?> get bumpDir => _bumpDir;

  double get beatProgress => clock.beatProgress;

  /// The state before the latest beat, for interpolation. Null only when no
  /// beat has happened yet or after a run change. It stays readable after the
  /// clock stops, so the last move still animates.
  GameState? get from => _from;

  bool get frozen => !clock.running;

  /// Changes only when time freezes or flows again.
  ValueListenable<bool> get frozenListenable => _frozenN;

  /// True while a rewind input is held and time is running backwards.
  ValueListenable<bool> get rewinding => _rewinding;

  void _syncFeel() {
    _frozenN.value = frozen;
    _rewinding.value =
        clock.running && _top != null && _top!.$1 == IntentKind.rewind;
  }

  final List<(InputSource, IntentKind, Move?)> _held = [];

  /// Held inputs, oldest first, one per source and kind. The last one drives
  /// the clock.
  List<(InputSource, IntentKind, Move?)> get held => List.unmodifiable(_held);

  /// Low level: sets the clock's intent directly. Inputs use [press] and
  /// [release] so two thumbs (or keys) arbitrate.
  void setIntent(IntentKind kind, [Move? dir]) {
    clock.setIntent(kind, dir);
    _syncFeel();
  }

  /// An input of [kind] from [source] went down (or a held move changed
  /// direction). The latest press wins.
  void press(
    IntentKind kind, [
    Move? dir,
    InputSource source = InputSource.button,
  ]) {
    if (kind == IntentKind.none) return;
    final before = _top;
    _held
      ..removeWhere((e) => e.$1 == source && e.$2 == kind)
      ..add((source, kind, kind == IntentKind.move ? dir : null));
    if (_top != before) _applyTop();
    _syncFeel();
  }

  /// The input of [kind] from [source] was let go: the previous held input,
  /// if any, takes over again.
  void release(IntentKind kind, [InputSource source = InputSource.button]) {
    final before = _top;
    _held.removeWhere((e) => e.$1 == source && e.$2 == kind);
    if (_top != before) _applyTop();
    _syncFeel();
  }

  /// Lets go of everything [source] holds, e.g. keys when focus leaves.
  void releaseSource(InputSource source) {
    final before = _top;
    _held.removeWhere((e) => e.$1 == source);
    if (_top != before) _applyTop();
    _syncFeel();
  }

  /// Forgets every held input, e.g. when the app goes to the background.
  void releaseAll() {
    _held.clear();
    clock.setIntent(IntentKind.none);
    _syncFeel();
  }

  /// The winning intent; sources do not matter for the clock.
  (IntentKind, Move?)? get _top =>
      _held.isEmpty ? null : (_held.last.$2, _held.last.$3);

  void _applyTop() {
    final top = _top;
    if (top == null) {
      clock.setIntent(IntentKind.none);
    } else {
      clock.setIntent(top.$1, top.$2);
    }
  }

  void advance(double dt) {
    clock.advance(dt);
    _syncFeel();
  }

  void _onBeat(IntentKind kind, Move? dir) {
    switch (kind) {
      case IntentKind.none:
        return;
      case IntentKind.move:
        final m = dir ?? Move.wait;
        // A blocked move is a push: it still takes a beat.
        if (game.isBlocked(m)) {
          _bumpDir.value = m;
          _bumps.value++;
        }
        _step(m);
      case IntentKind.wait:
        _step(Move.wait);
      case IntentKind.rewind:
        if (game.canUndo) {
          _from = game.state;
          game.undo();
          notifyListeners();
        } else {
          clock.stop();
          _syncFeel();
          notifyListeners();
        }
    }
  }

  void _step(Move m) {
    game.move(m);
    _from = game.previous;
    notifyListeners();
  }

  /// Any run end, including New echo and Give up from outside, stops a held
  /// input so the next run does not start moving on its own.
  void _onGameChanged() {
    switch (game.lastEvent) {
      case GameEvent.runEnded || GameEvent.won || GameEvent.lost:
        clock.stop();
        _syncFeel();
        _from = game.previous;
      case GameEvent.restarted:
        // Nothing to glide from: the level starts over.
        _from = null;
      case GameEvent.none || GameEvent.moved:
        break;
    }
  }

  @override
  void dispose() {
    game.removeListener(_onGameChanged);
    clock.stop();
    _bumps.dispose();
    _bumpDir.dispose();
    _frozenN.dispose();
    _rewinding.dispose();
    super.dispose();
  }
}

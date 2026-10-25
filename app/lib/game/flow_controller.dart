import 'package:echo_core/echo_core.dart';
import 'package:flutter/foundation.dart';

import 'game_clock.dart';
import 'game_controller.dart';

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

  void setIntent(IntentKind kind, [Move? dir]) => clock.setIntent(kind, dir);

  void advance(double dt) => clock.advance(dt);

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
        _from = game.previous;
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
    super.dispose();
  }
}

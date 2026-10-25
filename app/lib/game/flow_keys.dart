import 'package:echo_core/echo_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'flow_controller.dart';
import 'game_clock.dart';

final _moves = {
  LogicalKeyboardKey.arrowUp: Move.up,
  LogicalKeyboardKey.arrowDown: Move.down,
  LogicalKeyboardKey.arrowLeft: Move.left,
  LogicalKeyboardKey.arrowRight: Move.right,
  LogicalKeyboardKey.keyW: Move.up,
  LogicalKeyboardKey.keyS: Move.down,
  LogicalKeyboardKey.keyA: Move.left,
  LogicalKeyboardKey.keyD: Move.right,
};

final _waitKeys = {LogicalKeyboardKey.space};
final _rewindKeys = {LogicalKeyboardKey.keyZ, LogicalKeyboardKey.backspace};

/// Web and desktop keys: arrows/WASD hold to move, Space holds wait,
/// Z/Backspace hold rewind, E makes a new echo, R restarts.
KeyEventResult flowKeyHandler(
  KeyEvent e,
  FlowController flow, {
  required VoidCallback onNewEcho,
  required VoidCallback onRestart,
}) {
  final key = e.logicalKey;
  final keyboard = HardwareKeyboard.instance;
  // Leave shortcuts such as Ctrl/Cmd+R (reload) to the browser.
  if (e is! KeyUpEvent &&
      (keyboard.isControlPressed ||
          keyboard.isMetaPressed ||
          keyboard.isAltPressed)) {
    return KeyEventResult.ignored;
  }
  final down = e is KeyDownEvent;
  final up = e is KeyUpEvent;
  final move = _moves[key];
  if (move != null) {
    if (down) flow.press(IntentKind.move, move, InputSource.keys);
    if (up) {
      // Another direction key still down takes over.
      final still = keyboard.logicalKeysPressed
          .map((k) => _moves[k])
          .whereType<Move>()
          .lastOrNull;
      if (still != null) {
        flow.press(IntentKind.move, still, InputSource.keys);
      } else {
        flow.release(IntentKind.move, InputSource.keys);
      }
    }
    return KeyEventResult.handled;
  }
  final kind = _waitKeys.contains(key)
      ? IntentKind.wait
      : _rewindKeys.contains(key)
      ? IntentKind.rewind
      : null;
  if (kind != null) {
    if (down) flow.press(kind, null, InputSource.keys);
    if (up) flow.release(kind, InputSource.keys);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.keyE || key == LogicalKeyboardKey.keyR) {
    if (down) (key == LogicalKeyboardKey.keyE ? onNewEcho : onRestart)();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

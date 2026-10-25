import 'dart:async';

import 'package:flutter/services.dart';

enum HapticKind { light, medium, heavy }

/// Haptic feedback behind one static hook, so tests can record it.
class Haptics {
  const Haptics._();

  /// Tests set this to capture feedback instead of touching the platform.
  static void Function(HapticKind)? testHook;

  static void play(HapticKind kind) {
    final hook = testHook;
    if (hook != null) {
      hook(kind);
      return;
    }
    try {
      final done = switch (kind) {
        HapticKind.light => HapticFeedback.lightImpact(),
        HapticKind.medium => HapticFeedback.mediumImpact(),
        HapticKind.heavy => HapticFeedback.heavyImpact(),
      };
      unawaited(done.catchError((_) {}));
    } catch (_) {}
  }
}

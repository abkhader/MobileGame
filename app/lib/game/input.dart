import 'dart:ui' show Offset;

import 'package:echo_core/echo_core.dart';

/// Maps a swipe velocity (logical px/s, screen y grows downward) to a move.
///
/// The dominant axis wins; ties go to horizontal. Returns null when that
/// axis is slower than [minSpeed], so slow drags do not move the player.
Move? swipeToMove(Offset velocity, {double minSpeed = 200}) {
  final horizontal = velocity.dx.abs() >= velocity.dy.abs();
  final speed = horizontal ? velocity.dx.abs() : velocity.dy.abs();
  if (speed < minSpeed) return null;
  if (horizontal) {
    return velocity.dx > 0 ? Move.right : Move.left;
  }
  return velocity.dy > 0 ? Move.down : Move.up;
}

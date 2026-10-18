import 'position.dart';

/// A single player action for one tick.
enum Move {
  up('U', Position(0, -1)),
  down('D', Position(0, 1)),
  left('L', Position(-1, 0)),
  right('R', Position(1, 0)),
  wait('W', Position(0, 0));

  const Move(this.code, this.delta);

  /// One-letter code used in level files and solutions.
  final String code;

  /// Displacement applied to the actor's position.
  final Position delta;

  static Move fromCode(String c) {
    for (final m in values) {
      if (m.code == c) return m;
    }
    throw ArgumentError.value(c, 'c', 'Unknown move code');
  }
}

/// A grid coordinate. `x` is the column, `y` is the row; `y` grows downward.
class Position {
  const Position(this.x, this.y);

  final int x;
  final int y;

  Position operator +(Position o) => Position(x + o.x, y + o.y);

  @override
  bool operator ==(Object other) =>
      other is Position && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

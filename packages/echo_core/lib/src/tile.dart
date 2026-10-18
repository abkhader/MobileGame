enum TileKind { floor, wall, start, exit, plate, door }

/// A grid cell. [channel] is the lowercase letter linking plates and doors,
/// and `null` for every other kind.
class Tile {
  const Tile(this.kind, {this.channel});

  final TileKind kind;
  final String? channel;

  @override
  bool operator ==(Object other) =>
      other is Tile && other.kind == kind && other.channel == channel;

  @override
  int get hashCode => Object.hash(kind, channel);

  @override
  String toString() =>
      channel == null ? 'Tile($kind)' : 'Tile($kind, $channel)';
}

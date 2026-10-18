import 'package:echo_core/echo_core.dart';
import 'package:test/test.dart';

void main() {
  test('positions add and compare by value', () {
    expect(const Position(1, 2) + const Position(3, -1), const Position(4, 1));
    expect({Position(1, 1), Position(1, 1)}.length, 1);
  });
  test('moves map to codes and deltas', () {
    expect(Move.values.map((m) => m.code).join(), 'UDLRW');
    expect(Move.up.delta, const Position(0, -1));
    expect(Move.right.delta, const Position(1, 0));
    expect(Move.wait.delta, const Position(0, 0));
    expect(Move.fromCode('L'), Move.left);
    expect(() => Move.fromCode('X'), throwsArgumentError);
  });
  test('tiles compare by kind and channel', () {
    expect(const Tile(TileKind.door, channel: 'a'),
        const Tile(TileKind.door, channel: 'a'));
    expect(
        const Tile(TileKind.door, channel: 'a') ==
            const Tile(TileKind.door, channel: 'b'),
        isFalse);
  });
}

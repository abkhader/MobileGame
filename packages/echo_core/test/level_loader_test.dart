import 'package:echo_core/echo_core.dart';
import 'package:test/test.dart';

const valid = '{"id":"1-02","name":"Hold","runLimit":1,"tip":"t",'
    '"grid":["#####","#SaA#","#..E#"],"bestScore":4,"solution":[["R","R"]]}';

Map<String, dynamic> validMap([Map<String, dynamic> overrides = const {}]) => {
      'id': '1-02',
      'name': 'Hold',
      'runLimit': 1,
      'grid': ['#####', '#SaA#', '#..E#'],
      ...overrides,
    };

void expectRejected(Map<String, dynamic> map, String fragment) {
  expect(
    () => LevelLoader.fromMap(map),
    throwsA(
      isA<LevelFormatException>()
          .having((e) => e.message, 'message', contains(fragment)),
    ),
  );
}

void main() {
  test('parses a valid level', () {
    final l = LevelLoader.parse(valid);
    expect((l.id, l.width, l.height, l.runLimit), ('1-02', 5, 3, 1));
    expect((l.name, l.tip, l.bestScore), ('Hold', 't', 4));
    expect((l.start, l.exit), (const Position(1, 1), const Position(3, 2)));
    expect(l.tileAt(const Position(2, 1)),
        const Tile(TileKind.plate, channel: 'a'));
    expect(l.tileAt(const Position(3, 1)),
        const Tile(TileKind.door, channel: 'a'));
    expect(l.tileAt(const Position(0, 0)), const Tile(TileKind.wall));
    expect(l.tileAt(const Position(1, 1)), const Tile(TileKind.start));
    expect(l.tileAt(const Position(3, 2)), const Tile(TileKind.exit));
    expect(l.tileAt(const Position(1, 2)), const Tile(TileKind.floor));
    expect(l.plates['a'], const Position(2, 1));
    expect(l.doors['a'], [const Position(3, 1)]);
    expect(l.solution, [
      [Move.right, Move.right]
    ]);
    expect(l.inBounds(const Position(5, 0)), isFalse);
    expect(l.inBounds(const Position(-1, 0)), isFalse);
    expect(l.inBounds(const Position(0, 3)), isFalse);
    expect(l.inBounds(const Position(4, 2)), isTrue);
  });

  test('tip, bestScore and solution are optional', () {
    final l = LevelLoader.fromMap(validMap());
    expect((l.tip, l.bestScore, l.solution), (null, null, null));
  });

  test('collections are unmodifiable', () {
    final l = LevelLoader.parse(valid);
    expect(() => l.plates['z'] = const Position(0, 0), throwsUnsupportedError);
    expect(
        () => l.doors['a']!.add(const Position(0, 0)), throwsUnsupportedError);
    expect(() => l.doors['z'] = [], throwsUnsupportedError);
    expect(() => l.solution!.add([]), throwsUnsupportedError);
    expect(() => l.solution![0].add(Move.up), throwsUnsupportedError);
  });

  test('invalid JSON is a LevelFormatException', () {
    expect(
      () => LevelLoader.parse('{nope'),
      throwsA(isA<LevelFormatException>()
          .having((e) => e.message, 'message', contains('invalid JSON'))),
    );
  });

  test('non-object JSON is rejected', () {
    expect(
        () => LevelLoader.parse('[1]'), throwsA(isA<LevelFormatException>()));
  });

  test('rejects rows of different length', () {
    expectRejected(
        validMap({
          'grid': ['#####', '#SaA#', '#.E#']
        }),
        'rectangular');
  });

  test('rejects 9 columns', () {
    expectRejected(
        validMap({
          'grid': ['#########', '#S.....E#']
        }),
        'at most 8 columns');
  });

  test('rejects 11 rows', () {
    expectRejected(
        validMap({
          'grid': [
            '#SE#',
            for (var i = 0; i < 10; i++) '#..#',
          ]
        }),
        'at most 10 rows');
  });

  test('rejects a grid with no S', () {
    expectRejected(
        validMap({
          'grid': ['#####', '#.aA#', '#..E#']
        }),
        'exactly one S');
  });

  test('rejects two E', () {
    expectRejected(
        validMap({
          'grid': ['#####', '#SaA#', '#.EE#']
        }),
        'exactly one E');
  });

  test('rejects runLimit 0', () {
    expectRejected(validMap({'runLimit': 0}), 'runLimit');
  });

  test('rejects runLimit 5', () {
    expectRejected(validMap({'runLimit': 5}), 'runLimit');
  });

  test('rejects a plate letter used twice', () {
    expectRejected(
        validMap({
          'grid': ['#####', '#SaA#', '#aaE#']
        }),
        "plate 'a'");
  });

  test('rejects a door with no matching plate', () {
    expectRejected(
        validMap({
          'grid': ['#####', '#SaA#', '#B.E#']
        }),
        "door 'B'");
  });

  test('rejects an unknown character with coordinates', () {
    expectRejected(
        validMap({
          'grid': ['#####', '#SaA#', '#.?E#']
        }),
        "unknown character '?' at (2, 2)");
  });

  test('rejects an invalid move code in solution', () {
    expectRejected(
        validMap({
          'solution': [
            ['R', 'X']
          ]
        }),
        'solution');
  });

  test('rejects a malformed solution shape', () {
    expectRejected(validMap({'solution': 'RR'}), 'solution');
    expectRejected(
        validMap({
          'solution': ['RR']
        }),
        'solution');
    expectRejected(
        validMap({
          'solution': [
            [1]
          ]
        }),
        'solution');
  });

  test('rejects a missing id', () {
    expectRejected(validMap()..remove('id'), 'id');
  });

  test('rejects an empty id', () {
    expectRejected(validMap({'id': ''}), 'id');
  });

  test('rejects a missing or empty name', () {
    expectRejected(validMap()..remove('name'), 'name');
    expectRejected(validMap({'name': ''}), 'name');
  });

  test('wrong field types become LevelFormatException', () {
    expectRejected(validMap({'runLimit': '1'}), 'runLimit');
    expectRejected(validMap({'id': 5}), 'id');
    expectRejected(validMap({'tip': 5}), 'tip');
    expectRejected(validMap({'bestScore': 'x'}), 'bestScore');
    expectRejected(validMap({'grid': 'S'}), 'grid');
    expectRejected(
        validMap({
          'grid': [1, 2]
        }),
        'grid');
  });
}

import 'package:echo_app/game/board_static_layer.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter_test/flutter_test.dart';

Level _lvl(List<String> grid) =>
    LevelLoader.fromMap({'id': 't', 'name': 't', 'runLimit': 1, 'grid': grid});

/// The single laser's beam ends, after laying the board out.
(Offset, Offset) _beam(Level level) {
  final layer = BoardStaticLayer(level);
  addTearDown(layer.dispose);
  expect(layer.ensure(400, 400, 1), isNotNull);
  return (layer.beamStarts.single, layer.beamEnds.single);
}

void main() {
  // A beam is a gate across the path: it spans the corridor from wall to
  // wall, emitters on the walls, never running along the corridor.
  testWidgets('in a horizontal corridor the beam runs up and down', (t) async {
    final level = _lvl(['#####', 'S.1.E', '#####']);
    expect(laserBeamVertical(level, const Position(2, 1)), isTrue);
    final (a, b) = _beam(level);
    expect(a.dx, b.dx);
    expect(a.dy, lessThan(b.dy));
  });

  testWidgets('in a vertical corridor the beam runs left to right', (t) async {
    final level = _lvl(['#S#', '#.#', '#1#', '#.#', '#E#']);
    expect(laserBeamVertical(level, const Position(1, 2)), isFalse);
    final (a, b) = _beam(level);
    expect(a.dy, b.dy);
    expect(a.dx, lessThan(b.dx));
  });

  testWidgets('the board edge counts as a wall', (t) async {
    expect(laserBeamVertical(_lvl(['S1E']), const Position(1, 0)), isTrue);
  });

  testWidgets('on open floor the beam defaults to left and right', (t) async {
    final level = _lvl(['S...', '.1..', '...E']);
    expect(laserBeamVertical(level, const Position(1, 1)), isFalse);
    final (a, b) = _beam(level);
    expect(a.dy, b.dy);
  });

  testWidgets('a half-open tile crosses its more walled-in axis', (t) async {
    // A wall above only: the beam hangs from it, top to bottom.
    final above = _lvl(['.#..', 'S1.E', '....']);
    expect(laserBeamVertical(above, const Position(1, 1)), isTrue);
    // A wall on the left only: left to right.
    final left = _lvl(['....', '#1.E', 'S...']);
    expect(laserBeamVertical(left, const Position(1, 1)), isFalse);
  });
}

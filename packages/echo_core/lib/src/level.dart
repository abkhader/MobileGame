import 'move.dart';
import 'position.dart';
import 'tile.dart';

/// An immutable, validated puzzle level. Build one with `LevelLoader`.
class Level {
  Level({
    required this.id,
    required this.name,
    required this.runLimit,
    required List<List<Tile>> grid,
    required this.start,
    required this.exit,
    required Map<String, Position> plates,
    required Map<String, List<Position>> doors,
    required List<Position> sparks,
    Map<Position, int> lasers = const {},
    Set<Position> cracked = const {},
    List<Position> shadeStarts = const [],
    this.tip,
    this.bestScore,
    List<List<Move>>? solution,
  }) : _grid = List.unmodifiable(grid.map(List<Tile>.unmodifiable)),
       sparks = List.unmodifiable(sparks),
       lasers = Map.unmodifiable(lasers),
       cracked = Set.unmodifiable(cracked),
       shadeStarts = List.unmodifiable(shadeStarts),
       plates = Map.unmodifiable(plates),
       doors = Map.unmodifiable(
         doors.map((k, v) => MapEntry(k, List<Position>.unmodifiable(v))),
       ),
       solution = solution == null
           ? null
           : List.unmodifiable(solution.map(List<Move>.unmodifiable));

  static const maxWidth = 8, maxHeight = 10, maxRunLimit = 4;

  final String id;
  final String name;
  final int runLimit;
  final String? tip;
  final int? bestScore;
  final List<List<Move>>? solution;
  final Position start;
  final Position exit;

  /// Plate position keyed by lowercase channel letter.
  final Map<String, Position> plates;

  /// Door positions keyed by lowercase channel letter.
  final Map<String, List<Position>> doors;

  /// Spark positions (floor tiles) in reading order (row-major).
  final List<Position> sparks;

  /// Laser tiles (floor that fires) mapped to their beat, 1, 2 or 3. See
  /// `Rules.laserFires` for when each beat fires.
  final Map<Position, int> lasers;

  /// Cracked floor tiles. Each collapses into a hole once everyone has
  /// stepped off it (see `Rules.collapse`); holes last for the rest of a run.
  final Set<Position> cracked;

  /// Shade start tiles (floor) in reading order (row-major). A Shade's index
  /// in this list is its index in `GameState.shades`.
  final List<Position> shadeStarts;

  final List<List<Tile>> _grid;

  int get width => _grid.first.length;
  int get height => _grid.length;

  bool inBounds(Position p) =>
      p.x >= 0 && p.y >= 0 && p.x < width && p.y < height;

  /// The tile at [p]; [p] must be in bounds.
  Tile tileAt(Position p) => _grid[p.y][p.x];
}

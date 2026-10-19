import 'package:echo_core/echo_core.dart';

/// Builds a level from [grid] rows.
Level lvl(List<String> grid, {int runLimit = 1}) => LevelLoader.fromMap({
  'id': 't',
  'name': 't',
  'runLimit': runLimit,
  'grid': grid,
});

/// Applies [script] left to right: `|` ends the run, any other character is
/// a move code.
GameState play(GameState s, String script) {
  for (final c in script.split('')) {
    s = c == '|' ? Rules.endRun(s) : Rules.step(s, Move.fromCode(c));
  }
  return s;
}

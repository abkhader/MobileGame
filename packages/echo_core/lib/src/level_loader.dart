import 'dart:convert';

import 'level.dart';
import 'move.dart';
import 'position.dart';
import 'tile.dart';

/// Thrown when level data is malformed or breaks a level rule.
class LevelFormatException implements Exception {
  const LevelFormatException(this.message);

  final String message;

  @override
  String toString() => 'LevelFormatException: $message';
}

/// Parses and validates level JSON.
abstract final class LevelLoader {
  static Level parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw LevelFormatException('invalid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const LevelFormatException('level must be a JSON object');
    }
    return fromMap(decoded);
  }

  static Level fromMap(Map<String, dynamic> map) {
    final id = _nonEmptyString(map, 'id');
    final name = _nonEmptyString(map, 'name');

    final runLimit = map['runLimit'];
    if (runLimit is! int || runLimit < 1 || runLimit > Level.maxRunLimit) {
      throw const LevelFormatException(
          'runLimit must be an integer from 1 to ${Level.maxRunLimit}');
    }

    final tip = map['tip'];
    if (tip != null && tip is! String) {
      throw const LevelFormatException('tip must be a string');
    }
    final bestScore = map['bestScore'];
    if (bestScore != null && bestScore is! int) {
      throw const LevelFormatException('bestScore must be an integer');
    }

    final rows = _rows(map['grid']);
    final solution = _solution(map['solution']);

    final grid = <List<Tile>>[];
    final plates = <String, Position>{};
    final doors = <String, List<Position>>{};
    final starts = <Position>[];
    final exits = <Position>[];

    for (var y = 0; y < rows.length; y++) {
      final row = <Tile>[];
      for (var x = 0; x < rows[y].length; x++) {
        final ch = rows[y][x];
        final p = Position(x, y);
        switch (ch) {
          case '#':
            row.add(const Tile(TileKind.wall));
          case '.':
            row.add(const Tile(TileKind.floor));
          case 'S':
            starts.add(p);
            row.add(const Tile(TileKind.start));
          case 'E':
            exits.add(p);
            row.add(const Tile(TileKind.exit));
          default:
            final code = ch.codeUnitAt(0);
            if (code >= 0x61 && code <= 0x68) {
              if (plates.containsKey(ch)) {
                throw LevelFormatException(
                    "plate '$ch' appears more than once");
              }
              plates[ch] = p;
              row.add(Tile(TileKind.plate, channel: ch));
            } else if (code >= 0x41 && code <= 0x48) {
              final channel = ch.toLowerCase();
              doors.putIfAbsent(channel, () => []).add(p);
              row.add(Tile(TileKind.door, channel: channel));
            } else {
              throw LevelFormatException("unknown character '$ch' at ($x, $y)");
            }
        }
      }
      grid.add(row);
    }

    if (starts.length != 1) {
      throw const LevelFormatException('grid must contain exactly one S');
    }
    if (exits.length != 1) {
      throw const LevelFormatException('grid must contain exactly one E');
    }
    for (final channel in doors.keys) {
      if (!plates.containsKey(channel)) {
        throw LevelFormatException(
            "door '${channel.toUpperCase()}' has no matching plate '$channel'");
      }
    }

    return Level(
      id: id,
      name: name,
      runLimit: runLimit,
      tip: tip as String?,
      bestScore: bestScore as int?,
      solution: solution,
      grid: grid,
      start: starts.single,
      exit: exits.single,
      plates: plates,
      doors: doors,
    );
  }

  static String _nonEmptyString(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v is! String || v.isEmpty) {
      throw LevelFormatException('$key must be a non-empty string');
    }
    return v;
  }

  static List<String> _rows(Object? raw) {
    if (raw is! List || raw.isEmpty || raw.any((r) => r is! String)) {
      throw const LevelFormatException(
          'grid must be a non-empty list of strings');
    }
    final rows = raw.cast<String>();
    if (rows.any((r) => r.length != rows.first.length)) {
      throw const LevelFormatException('grid must be rectangular');
    }
    if (rows.first.isEmpty) {
      throw const LevelFormatException('grid rows must not be empty');
    }
    if (rows.first.length > Level.maxWidth) {
      throw const LevelFormatException(
          'grid must have at most ${Level.maxWidth} columns');
    }
    if (rows.length > Level.maxHeight) {
      throw const LevelFormatException(
          'grid must have at most ${Level.maxHeight} rows');
    }
    return rows;
  }

  static List<List<Move>>? _solution(Object? raw) {
    if (raw == null) return null;
    const shape = 'solution must be a list of lists of move codes';
    if (raw is! List) throw const LevelFormatException(shape);
    final result = <List<Move>>[];
    for (final run in raw) {
      if (run is! List) throw const LevelFormatException(shape);
      final moves = <Move>[];
      for (final code in run) {
        if (code is! String) throw const LevelFormatException(shape);
        try {
          moves.add(Move.fromCode(code));
        } on ArgumentError {
          throw LevelFormatException("solution has unknown move code '$code'");
        }
      }
      result.add(moves);
    }
    return result;
  }
}

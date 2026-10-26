import 'dart:convert';
import 'dart:io';

import 'package:echo_core/echo_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

// Player-facing helper: a plate at (0,0), start (1,0), door (2,0), exit (3,0).
const G = ['aSAE'];

void main() {
  group('loader', () {
    test('parses sparks in reading order and treats them as floor', () {
      final l = lvl(['#####', '#S*.#', '#*.E#']);
      expect(l.sparks, [const Position(2, 1), const Position(1, 2)]);
      expect(l.tileAt(const Position(2, 1)), const Tile(TileKind.floor));
      final s = play(GameState.initial(l), 'R');
      expect(s.player, const Position(2, 1));
    });
    test('accepts any number of sparks, including none', () {
      expect(lvl(['SE']).sparks, isEmpty);
      expect(lvl(['S*****E']).sparks, hasLength(5));
    });
    test('sparks list is unmodifiable', () {
      expect(
        () => lvl(['S*E']).sparks.add(const Position(0, 0)),
        throwsUnsupportedError,
      );
    });
  });

  group('rules', () {
    test('initial state has no collected sparks, and it is unmodifiable', () {
      final s = GameState.initial(lvl(['S*E']));
      expect(s.collected, isEmpty);
      expect(
        () => s.collected.add(const Position(1, 0)),
        throwsUnsupportedError,
      );
    });
    test('stepping onto a spark collects it once', () {
      var s = play(GameState.initial(lvl(['S*.E'])), 'R');
      expect(s.collected, {const Position(1, 0)});
      s = play(s, 'LR');
      expect(s.collected, {const Position(1, 0)});
      s = play(s, 'W');
      expect(s.collected, hasLength(1));
    });
    test('walking past a non-spark floor tile collects nothing', () {
      final s = play(GameState.initial(lvl(['S.*E'])), 'R');
      expect(s.collected, isEmpty);
    });
    test('a push (blocked move) onto nothing new adds nothing', () {
      final s = play(GameState.initial(lvl(['#S*E'])), 'LL');
      expect(s.collected, isEmpty);
    });
    test('a ghost standing on a spark does not collect it', () {
      // Run 1 collects the spark; rebuild run 2 with it uncollected so only
      // the ghost reaches the tile.
      final l = lvl(['S*E'], runLimit: 2);
      final run2 = play(GameState.initial(l), 'R|');
      final s = GameState(
        level: l,
        runIndex: run2.runIndex,
        tick: run2.tick,
        currentRun: run2.currentRun,
        ghosts: run2.ghosts,
        player: run2.player,
        ghostPositions: run2.ghostPositions,
        openDoors: run2.openDoors,
        completedTicks: run2.completedTicks,
        status: run2.status,
        collected: const {},
        holes: run2.holes,
        ghostAlive: run2.ghostAlive,
        shades: run2.shades,
        lastHits: run2.lastHits,
      );
      final after = Rules.step(s, Move.wait);
      expect(after.ghostPositions, [const Position(1, 0)]);
      expect(after.player, const Position(0, 0));
      expect(after.collected, isEmpty);
    });
    test('collected on the winning move', () {
      // Spark placed on a door-free route; exit adjacent.
      final l = lvl(['S*E']);
      final s = play(GameState.initial(l), 'R');
      expect(s.status, GameStatus.playing);
      final won = play(s, 'R');
      expect(won.status, GameStatus.won);
      expect(won.collected, {const Position(1, 0)});
    });
    test('endRun keeps collected into the next run', () {
      final l = lvl(['S*.E'], runLimit: 2);
      final s = play(GameState.initial(l), 'R|');
      expect(s.runIndex, 1);
      expect(s.collected, {const Position(1, 0)});
      expect(
        () => s.collected.add(const Position(2, 0)),
        throwsUnsupportedError,
      );
    });
    test('lost state keeps collected', () {
      final l = lvl(['S*.E']);
      final s = play(GameState.initial(l), 'R|');
      expect(s.status, GameStatus.lost);
      expect(s.collected, {const Position(1, 0)});
    });
    test('collected survives the 25-tick cap rolling into the next run', () {
      final l = lvl(['S*.E'], runLimit: 2);
      final s = play(GameState.initial(l), 'R${'W' * 24}');
      expect(s.runIndex, 1);
      expect(s.collected, {const Position(1, 0)});
    });
  });

  group('equivalence with sparkless levels', () {
    test('bundled levels behave identically with * replaced by .', () {
      final dir = Directory('../../app/assets/levels');
      expect(dir.existsSync(), isTrue, reason: 'levels dir not reachable');
      final files = dir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.json'),
      );
      expect(files, isNotEmpty);
      for (final f in files) {
        final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final plain = {
          ...map,
          'grid': [
            for (final r in map['grid'] as List)
              (r as String).replaceAll('*', '.'),
          ],
        };
        final withSparks = LevelLoader.fromMap(map);
        final without = LevelLoader.fromMap(plain);
        final solution = withSparks.solution;
        if (solution == null) continue;
        var a = GameState.initial(withSparks);
        var b = GameState.initial(without);
        for (var i = 0; i < solution.length; i++) {
          for (final m in solution[i]) {
            a = Rules.step(a, m);
            b = Rules.step(b, m);
            expect(
              (
                a.status,
                a.score,
                a.player,
                a.tick,
                (a.openDoors.map((p) => '$p').toList()..sort()).join(),
              ),
              (
                b.status,
                b.score,
                b.player,
                b.tick,
                (b.openDoors.map((p) => '$p').toList()..sort()).join(),
              ),
              reason: '${f.path} diverged',
            );
          }
          if (a.status == GameStatus.playing) {
            a = Rules.endRun(a);
            b = Rules.endRun(b);
          }
        }
        expect(a.status, b.status, reason: f.path);
        expect(a.score, b.score, reason: f.path);
        expect(without.sparks, isEmpty);
        expect(a.collected.difference(withSparks.sparks.toSet()), isEmpty);
      }
    });
  });
}

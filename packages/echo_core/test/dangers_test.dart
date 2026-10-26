import 'dart:convert';
import 'dart:io';

import 'package:echo_core/echo_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const _p = Position.new;

GameState start(List<String> grid, {int runLimit = 1}) =>
    GameState.initial(lvl(grid, runLimit: runLimit));

void main() {
  group('loader', () {
    test('reads lasers, cracked floor and Shade starts as floor', () {
      final l = lvl(['S1~x2E3', 'x.~...x']);
      expect(l.lasers, {_p(1, 0): 1, _p(4, 0): 2, _p(6, 0): 3});
      expect(l.cracked, {_p(2, 0), _p(2, 1)});
      expect(l.shadeStarts, [_p(3, 0), _p(0, 1), _p(6, 1)]);
      for (final p in [_p(1, 0), _p(2, 0), _p(3, 0), _p(4, 0), _p(6, 0)]) {
        expect(l.tileAt(p), const Tile(TileKind.floor), reason: '$p');
      }
    });
    test('levels without dangers have empty danger collections', () {
      final l = lvl(['S.E']);
      expect(l.lasers, isEmpty);
      expect(l.cracked, isEmpty);
      expect(l.shadeStarts, isEmpty);
    });
    test('danger collections are unmodifiable', () {
      final l = lvl(['S1~xE']);
      expect(() => l.lasers[_p(0, 0)] = 1, throwsUnsupportedError);
      expect(() => l.cracked.add(_p(0, 0)), throwsUnsupportedError);
      expect(() => l.shadeStarts.add(_p(0, 0)), throwsUnsupportedError);
    });
    test('still rejects other unknown characters', () {
      expect(() => lvl(['S4E']), throwsA(isA<LevelFormatException>()));
      expect(() => lvl(['S0E']), throwsA(isA<LevelFormatException>()));
    });
  });

  group('initial state', () {
    test('Shades on their starts, no holes, no ghosts, no hits', () {
      final s = start(['S.x.xE']);
      expect(s.shades, [_p(2, 0), _p(4, 0)]);
      expect(s.holes, isEmpty);
      expect(s.ghostAlive, isEmpty);
      expect(s.lastHits, Hits.none);
      expect(s.lastHits.pip, isFalse);
      expect(s.lastHits.ghosts, isEmpty);
    });
    test('new collections are unmodifiable', () {
      final s = play(start(['S~.x', '...E']), 'RR');
      expect(() => s.holes.add(_p(0, 0)), throwsUnsupportedError);
      expect(() => s.shades.add(_p(0, 0)), throwsUnsupportedError);
      expect(() => s.ghostAlive.add(true), throwsUnsupportedError);
      expect(() => s.lastHits.ghosts.add(0), throwsUnsupportedError);
    });
  });

  group('laser timing', () {
    test('fires on tick n >= 1 iff n % 3 == beat % 3', () {
      final fires = {
        for (final b in [1, 2, 3])
          b: [
            for (var n = 0; n <= 6; n++)
              if (Rules.laserFires(b, n)) n,
          ],
      };
      expect(fires, {
        1: [1, 4],
        2: [2, 5],
        3: [3, 6],
      });
    });
    test('warns on tick n iff (n + 1) % 3 == beat % 3', () {
      final warns = {
        for (final b in [1, 2, 3])
          b: [
            for (var n = 0; n <= 6; n++)
              if (Rules.laserWarns(b, n)) n,
          ],
      };
      expect(warns, {
        1: [0, 3, 6],
        2: [1, 4],
        3: [2, 5],
      });
    });
    test('Pip standing on a laser is hit on exactly its beat', () {
      for (final b in [1, 2, 3]) {
        var s = play(start(['S$b.E'], runLimit: 2), 'R');
        var hitTick = s.runIndex == 1 ? 1 : null;
        for (var t = 2; hitTick == null && t <= 6; t++) {
          s = play(s, 'W');
          if (s.runIndex == 1) hitTick = t;
        }
        expect(hitTick, b, reason: 'beat $b');
        expect(s.lastHits.pip, isTrue);
        expect(s.ghosts.single.length, b);
      }
    });
    test('walking through between beats is safe', () {
      // Beat 2 fires on ticks 2 and 5; Pip is on it only at tick 1.
      final s = play(start(['S2.E']), 'RRR');
      expect((s.status, s.score), (GameStatus.won, 3));
    });
  });

  group('crumbling floor', () {
    test('collapses once its only occupant steps off', () {
      var s = play(start(['S~.E']), 'R');
      expect(s.holes, isEmpty);
      s = play(s, 'W');
      expect(s.holes, isEmpty, reason: 'waiting on it does not collapse');
      s = play(s, 'R');
      expect(s.holes, {_p(1, 0)});
    });
    test('two actors on it, one leaves: no collapse until both left', () {
      var s = play(start(['S~..E'], runLimit: 2), 'RWWR');
      expect(s.holes, {_p(1, 0)});
      s = play(s, '|');
      expect(s.holes, isEmpty, reason: 'holes reset on a new run');
      s = play(s, 'R'); // Pip and the ghost both on the crack
      expect(s.holes, isEmpty);
      s = play(s, 'R'); // Pip leaves, ghost stays
      expect(s.holes, isEmpty);
      s = play(s, 'W');
      expect(s.holes, isEmpty);
      s = play(s, 'W'); // the ghost leaves
      expect(s.holes, {_p(1, 0)});
      expect(s.ghostAlive, [true]);
    });
    test('Pip stepping into a hole is hit: forced rewind', () {
      final s = play(start(['S~.E'], runLimit: 2), 'RRL');
      expect((s.runIndex, s.tick, s.completedTicks), (1, 0, 3));
      expect(s.ghosts, [
        [Move.right, Move.right, Move.left],
      ]);
      expect(s.player, _p(0, 0));
      expect(s.holes, isEmpty);
      expect(s.lastHits.pip, isTrue);
    });
    test('an echo stepping into a hole Pip made dissolves', () {
      final s = play(start(['S~.E'], runLimit: 2), 'WWR|RRW');
      expect(s.ghostAlive, [false]);
      expect(s.lastHits, Hits(pip: false, ghosts: [0]));
      expect(s.ghostPositions, [_p(1, 0)]);
      expect(s.status, GameStatus.playing);
    });
    test('ruling: an echo caught on a crack does not collapse it', () {
      // Dissolving is not "stepping off": the tile was not left by a live
      // actor, so it stays cracked until someone else steps on and off.
      const g = ['S.~x', '.###', '...E'];
      var s = play(start(g, runLimit: 2), 'RR'); // Pip walks into the Shade
      expect((s.runIndex, s.ghosts.single.length), (1, 2));
      s = play(s, 'D');
      expect(s.shades, [_p(2, 0)]);
      s = play(s, 'D'); // the ghost walks onto the crack and the Shade
      expect(s.ghostAlive, [false]);
      expect(s.ghostPositions, [_p(2, 0)]);
      expect(s.holes, isEmpty);
      s = play(s, 'R');
      expect(s.holes, isEmpty);
      expect(s.status, GameStatus.playing);
      expect(s.shades, [_p(1, 0)]);
    });
  });

  group('echo hits', () {
    test('an echo diverging onto a laser Pip passed safely dissolves', () {
      // Run 1: Pip is blocked by door A, so it is on the beat-3 laser only on
      // ticks 1, 2 and 4. Run 2: Pip holds plate a, the echo gets through
      // the door at tick 2 and steps back onto the laser at tick 3.
      const g = ['S3A.E', 'a####'];
      var s = play(start(g, runLimit: 2), 'RRLR');
      expect(s.runIndex, 0, reason: 'Pip passed the laser safely');
      s = play(s, '|DW');
      expect(s.ghostPositions, [_p(2, 0)]);
      expect(s.ghostAlive, [true]);
      s = play(s, 'W');
      expect(s.ghostAlive, [false]);
      expect(s.lastHits, Hits(pip: false, ghosts: [0]));
      expect(s.ghostPositions, [_p(1, 0)]);
      s = play(s, 'W'); // its recorded R would now succeed, but it is gone
      expect(s.ghostPositions, [_p(1, 0)]);
      expect(s.lastHits, Hits.none, reason: 'cleared on the next step');
    });
    test('a dissolved echo releases its plate for the next beat', () {
      const g = ['Sa.x', '.###', '.A.E'];
      // Run 1: Pip stands on the plate and is caught at tick 2.
      var s = play(start(g, runLimit: 2), 'RW');
      expect(s.runIndex, 1);
      expect(s.shades, [_p(3, 0)]);
      s = play(s, 'D'); // echo on the plate, Shade chases the nearer echo
      expect(s.shades, [_p(2, 0)]);
      expect(s.openDoors, {_p(1, 2)});
      s = play(s, 'D'); // Shade catches the echo on the plate
      expect(s.ghostAlive, [false]);
      expect(s.lastHits, Hits(pip: false, ghosts: [0]));
      expect(s.openDoors, isEmpty);
      s = play(s, 'R'); // door A is shut: blocked
      expect(s.player, _p(0, 2));
      expect(s.shades, [_p(0, 0)], reason: 'a dead echo is not a target');
      expect(s.lastHits, Hits.none);
    });
  });

  group('Shade step', () {
    final open = lvl(['S......E', '........']);
    test('targets the nearest light', () {
      expect(
        Rules.shadeStep(open, const {}, _p(3, 0), [_p(0, 0), _p(5, 0)]),
        _p(4, 0),
      );
    });
    test('ties go to Pip first, then the lowest echo index', () {
      expect(
        Rules.shadeStep(open, const {}, _p(3, 0), [_p(1, 0), _p(5, 0)]),
        _p(2, 0),
      );
      expect(
        Rules.shadeStep(open, const {}, _p(3, 0), [_p(5, 0), _p(1, 0)]),
        _p(4, 0),
      );
      expect(
        Rules.shadeStep(open, const {}, _p(3, 0), [
          _p(7, 1),
          _p(1, 0),
          _p(5, 0),
        ]),
        _p(2, 0),
      );
    });
    test('equal first steps go up, right, down, left', () {
      final l = lvl(['S..', '...', '..E']);
      Position step(Position light) =>
          Rules.shadeStep(l, const {}, _p(1, 1), [light]);
      expect(step(_p(2, 2)), _p(2, 1)); // right before down
      expect(step(_p(0, 0)), _p(1, 0)); // up before left
      expect(step(_p(0, 2)), _p(1, 2)); // down before left
      expect(step(_p(2, 0)), _p(1, 0)); // up before right
    });
    test('walks around walls by walking distance', () {
      final l = lvl(['S#E', '...']);
      expect(Rules.shadeStep(l, const {}, _p(2, 0), [_p(0, 0)]), _p(2, 1));
    });
    test('a closed door traps it; an open one lets it through', () {
      final l = lvl(['xA.S.E', '#####a']);
      expect(Rules.shadeStep(l, const {}, _p(0, 0), [_p(3, 0)]), _p(0, 0));
      expect(Rules.shadeStep(l, {_p(1, 0)}, _p(0, 0), [_p(3, 0)]), _p(1, 0));
      final s = play(start(['xA.S.E', '#####a']), 'WWW');
      expect(s.shades, [_p(0, 0)]);
      expect(s.status, GameStatus.playing);
    });
    test('uses the doors from the previous beat, like movement', () {
      // Pip steps onto plate a at tick 1: door A opens only after the beat,
      // so the Shade is still shut in on tick 1 and comes out on tick 2.
      var s = play(start(['xA.Sa', '####E']), 'R');
      expect(s.openDoors, {_p(1, 0)});
      expect(s.shades, [_p(0, 0)]);
      s = play(s, 'W');
      expect(s.shades, [_p(1, 0)]);
    });
    test('no lights, or already on one: waits', () {
      expect(Rules.shadeStep(open, const {}, _p(3, 0), const []), _p(3, 0));
      expect(Rules.shadeStep(open, const {}, _p(3, 0), [_p(3, 0)]), _p(3, 0));
    });
    test('glides through a firing laser unharmed', () {
      var s = play(start(['S..2.x', '#####E']), 'W');
      expect(s.shades, [_p(4, 0)]);
      s = play(s, 'W'); // tick 2: onto the firing beat-2 laser
      expect(s.shades, [_p(3, 0)]);
      expect(s.lastHits, Hits.none);
      s = play(s, 'W');
      expect(s.shades, [_p(2, 0)]);
    });
    test('glides over a hole unharmed', () {
      var s = play(start(['S~...x', '#.###E']), 'RD');
      expect(s.holes, {_p(1, 0)});
      expect(s.shades, [_p(3, 0)]);
      s = play(s, 'WW');
      expect(s.shades, [_p(1, 0)]);
      expect(s.status, GameStatus.playing);
      s = play(s, 'W');
      expect(s.shades, [_p(1, 1)]);
      expect(s.status, GameStatus.lost);
    });
    test('several Shades step in list order and may share a tile', () {
      var s = play(start(['x.x', '#.#', '#S#', '#E#']), 'W');
      expect(s.shades, [_p(1, 0), _p(1, 0)]);
      s = play(s, 'W');
      expect(s.shades, [_p(1, 1), _p(1, 1)]);
      s = play(s, 'W');
      expect(s.shades, [_p(1, 2), _p(1, 2)]);
      expect(s.status, GameStatus.lost);
    });
  });

  group('Shade catch', () {
    test('a Shade landing on Pip catches him', () {
      final s = play(start(['S.x', '..E'], runLimit: 2), 'R');
      expect((s.runIndex, s.lastHits.pip), (1, true));
    });
    test('Pip walking into a Shade is caught (the Shade waits on him)', () {
      final s = play(start(['Sx', '.E']), 'R');
      expect(s.status, GameStatus.lost);
      expect(s.shades, [_p(1, 0)]);
      expect(s.lastHits.pip, isTrue);
    });
    test('caughtByShade: landing and swapping catch; passing by does not', () {
      bool caught(Position from, Position to, Position sFrom, Position sTo) =>
          Rules.caughtByShade(from, to, [sFrom], [sTo]);
      expect(caught(_p(0, 0), _p(1, 0), _p(1, 0), _p(0, 0)), isTrue); // swap
      expect(caught(_p(0, 0), _p(1, 0), _p(2, 0), _p(1, 0)), isTrue); // land
      expect(caught(_p(0, 0), _p(1, 0), _p(1, 0), _p(1, 0)), isTrue); // wait
      expect(caught(_p(0, 0), _p(0, 1), _p(1, 0), _p(1, 1)), isFalse);
      expect(caught(_p(1, 0), _p(2, 0), _p(0, 0), _p(1, 0)), isFalse); // trail
      expect(
        Rules.caughtByShade(
          _p(0, 0),
          _p(0, 0),
          [_p(5, 5), _p(1, 0)],
          [_p(5, 4), _p(0, 0)],
        ),
        isTrue,
      );
    });
  });

  group('Pip hit', () {
    const g = ['S~...x', '#####E'];
    test('forced rewind: ghost recorded, Shades and holes reset', () {
      var s = play(start(g, runLimit: 2), 'RR');
      expect(s.holes, {_p(1, 0)});
      expect(s.shades, [_p(3, 0)]);
      s = play(s, 'W');
      expect((s.runIndex, s.tick, s.completedTicks), (1, 0, 3));
      expect(s.ghosts, [
        [Move.right, Move.right, Move.wait],
      ]);
      expect(s.ghostAlive, [true]);
      expect(s.player, _p(0, 0));
      expect(s.ghostPositions, [_p(0, 0)]);
      expect(s.holes, isEmpty);
      expect(s.shades, [_p(5, 0)]);
      expect(s.status, GameStatus.playing);
      expect(s.lastHits, Hits(pip: true, ghosts: const []));
      s = play(s, 'W');
      expect(s.lastHits, Hits.none);
    });
    test('on the last run the level is lost, counting the run once', () {
      final s = play(start(g), 'RRW');
      expect(s.status, GameStatus.lost);
      expect((s.tick, s.score), (3, 3));
      expect(s.ghosts, isEmpty);
      expect(s.currentRun, [Move.right, Move.right, Move.wait]);
      expect(s.lastHits.pip, isTrue);
      expect(() => Rules.step(s, Move.wait), throwsStateError);
    });
    test('a hit Pip holds no doors in the lost state', () {
      final s = play(start(['Sax', 'A.E']), 'R');
      expect(s.status, GameStatus.lost);
      expect(s.player, _p(1, 0));
      expect(s.openDoors, isEmpty);
    });
    test('caught on the exit does not win', () {
      var s = play(start(['S.E.x']), 'RR');
      expect(s.player, _p(2, 0));
      expect(s.shades, [_p(2, 0)]);
      expect(s.status, GameStatus.lost);
      s = play(start(['S.E.x'], runLimit: 2), 'RR');
      expect((s.status, s.runIndex), (GameStatus.playing, 1));
    });
    test('a spark collected on the hit beat is kept', () {
      final s = play(start(['S*x', '..E'], runLimit: 2), 'R');
      expect(s.runIndex, 1);
      expect(s.collected, {_p(1, 0)});
    });
    test('a manual endRun clears lastHits', () {
      final s = play(start(['S~.E'], runLimit: 3), 'WWR|RRW');
      expect(s.lastHits.ghosts, [0]);
      expect(play(s, '|').lastHits, Hits.none);
      expect(play(s, '|').ghostAlive, [true, true]);
    });
  });

  test('bundled levels replay their solutions to bestScore unchanged', () {
    final dir = Directory('../../app/assets/levels');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(files, isNotEmpty);
    for (final f in files) {
      final level = LevelLoader.parse(f.readAsStringSync());
      final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      expect(level.solution, isNotNull, reason: f.path);
      expect(map['bestScore'], isA<int>(), reason: f.path);
      var s = GameState.initial(level);
      for (final run in level.solution!) {
        for (final m in run) {
          s = Rules.step(s, m);
          expect(s.holes, isEmpty);
          expect(s.shades, isEmpty);
          expect(s.ghostAlive.every((a) => a), isTrue);
          expect(s.lastHits, Hits.none);
        }
        if (s.status == GameStatus.playing) s = Rules.endRun(s);
      }
      expect((s.status, s.score), (GameStatus.won, level.bestScore));
    }
  });
}

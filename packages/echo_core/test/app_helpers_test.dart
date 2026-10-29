import 'dart:io';

import 'package:echo_core/echo_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const _p = Position.new;

void main() {
  group('moveTarget', () {
    test('is where a move would carry an actor, walls and doors blocking', () {
      final l = lvl(['#S.aAE']);
      final open = <Position>{};
      expect(Rules.moveTarget(l, _p(1, 0), Move.right, open), _p(2, 0));
      expect(Rules.moveTarget(l, _p(1, 0), Move.left, open), _p(1, 0));
      expect(Rules.moveTarget(l, _p(1, 0), Move.up, open), _p(1, 0));
      expect(Rules.moveTarget(l, _p(1, 0), Move.wait, open), _p(1, 0));
      expect(Rules.moveTarget(l, _p(3, 0), Move.right, open), _p(3, 0));
      expect(Rules.moveTarget(l, _p(3, 0), Move.right, {_p(4, 0)}), _p(4, 0));
    });

    test('names the tile a hit Pip stepped onto before his run ended', () {
      final s = GameState.initial(lvl(['S1.E'], runLimit: 2));
      final after = Rules.step(s, Move.right);
      expect(after.lastHits.pip, isTrue);
      expect(after.player, s.level.start);
      expect(
        Rules.moveTarget(s.level, s.player, Move.right, s.openDoors),
        _p(1, 0),
      );
    });
  });

  group('shadeLookahead', () {
    test('is each Shade\'s next step if no actor moved', () {
      final s = GameState.initial(lvl(['S..x', 'E..x']));
      expect(Rules.shadeLookahead(s), [_p(2, 0), _p(3, 0)]);
      // It matches the step a wait beat really takes.
      final waited = Rules.step(s, Move.wait);
      expect(waited.shades, Rules.shadeLookahead(s));
    });

    test('waits with no light in reach', () {
      final level = lvl(['S.E', '###', 'x..']);
      expect(Rules.shadeLookahead(GameState.initial(level)), [_p(0, 2)]);
    });

    test('is empty without Shades', () {
      expect(Rules.shadeLookahead(GameState.initial(lvl(['S.E']))), isEmpty);
    });

    test('follows an echo\'s scripted next move, not where it stands', () {
      // Run 0 stepped down. In run 1 at tick 0 Pip and the echo share the
      // start, but the echo is about to step down: the Shade hunts it the
      // short way (left) instead of Pip (up and around).
      final level = lvl(['S..', '.#.', '..x', 'E##'], runLimit: 2);
      final s = play(GameState.initial(level), 'D|');
      expect(s.runIndex, 1);
      expect(s.shades, [_p(2, 2)]);
      final real = Rules.stepInRun(s, Move.wait).shades;
      expect(real, [_p(1, 2)]);
      expect(Rules.shadeLookahead(s), real);
    });

    test('equals the real step whenever Pip waits, on every Shade level', () {
      // Every state along each bundled Shade level's stored solution
      // (decoys included), and along a few fixed wanderings.
      final files = Directory('../../app/assets/levels')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      var checked = 0;
      var echoesMoved = 0;
      void check(GameState s) {
        if (s.status != GameStatus.playing || s.shades.isEmpty) return;
        final next = Rules.stepInRun(s, Move.wait);
        expect(
          Rules.shadeLookahead(s),
          next.shades,
          reason: '${s.level.id} run ${s.runIndex} tick ${s.tick}',
        );
        checked++;
        for (var i = 0; i < s.ghosts.length; i++) {
          if (s.ghostAlive[i] &&
              next.ghostPositions[i] != s.ghostPositions[i]) {
            echoesMoved++;
          }
        }
      }

      for (final f in files) {
        final level = LevelLoader.parse(f.readAsStringSync());
        if (level.shadeStarts.isEmpty) continue;
        var s = GameState.initial(level);
        final runs = level.solution!;
        for (var r = 0; r < runs.length; r++) {
          for (final m in runs[r]) {
            check(s);
            s = Rules.step(s, m);
          }
          if (r < runs.length - 1 && s.runIndex == r) s = Rules.endRun(s);
        }
        // The stored first run replayed with Pip wandering differently.
        for (final wander in ['', 'UUUU', 'DDDD', 'LLLL', 'RRRR']) {
          var w = GameState.initial(level);
          for (final m in runs.first) {
            w = Rules.step(w, m);
            if (w.status != GameStatus.playing || w.runIndex > 0) break;
          }
          if (w.status != GameStatus.playing || w.runIndex > 0) continue;
          w = Rules.endRun(w);
          for (final c in wander.split('')) {
            if (c.isEmpty || w.status != GameStatus.playing) break;
            check(w);
            final runBefore = w.runIndex;
            w = Rules.step(w, Move.fromCode(c));
            if (w.runIndex != runBefore) break;
          }
          check(w);
        }
      }
      expect(checked, greaterThan(50));
      expect(echoesMoved, greaterThan(0));
    });
  });

  group('stepInRun', () {
    test('is the beat before a hit ends the run', () {
      final s = GameState.initial(lvl(['S1.E'], runLimit: 2));
      final beat = Rules.stepInRun(s, Move.right);
      expect(beat.runIndex, 0);
      expect(beat.tick, 1);
      expect(beat.player, _p(1, 0));
      expect(beat.lastHits.pip, isTrue);
      final step = Rules.step(s, Move.right);
      expect(step.runIndex, 1);
      expect(step.ghosts.single, [Move.right]);
    });

    test('equals step when the run goes on', () {
      final s = GameState.initial(lvl(['S..E']));
      expect(
        Rules.stepInRun(s, Move.right).player,
        Rules.step(s, Move.right).player,
      );
    });
  });
}

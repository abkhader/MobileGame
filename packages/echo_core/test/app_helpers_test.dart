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
  });
}

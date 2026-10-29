import 'package:echo_app/game/game_controller.dart';
import 'package:echo_app/game/hits.dart';
import 'package:echo_core/echo_core.dart';
import 'package:flutter_test/flutter_test.dart';

Level _level(List<String> grid, {int runLimit = 2, int? bestScore}) =>
    LevelLoader.fromMap({
      'id': 't',
      'name': 't',
      'runLimit': runLimit,
      'grid': grid,
      'bestScore': ?bestScore,
    });

void main() {
  test('move and undo', () {
    final c = GameController(_level(['S..E']));
    c.move(Move.right);
    expect(c.state.player, const Position(1, 0));
    expect(c.lastEvent, GameEvent.moved);
    expect(c.previous!.player, const Position(0, 0));
    expect(c.canUndo, isTrue);
    c.undo();
    expect(c.state.player, const Position(0, 0));
    expect(c.previous, isNull);
    expect(c.lastEvent, GameEvent.none);
    expect(c.canUndo, isFalse);
  });

  test('win ignores further moves silently', () {
    final c = GameController(_level(['S..E'], bestScore: 3));
    for (var i = 0; i < 3; i++) {
      c.move(Move.right);
    }
    expect(c.lastEvent, GameEvent.won);
    expect(c.previous, isNotNull);
    expect(c.canUndo, isFalse);
    var n = 0;
    c.addListener(() => n++);
    final s = c.state;
    c.move(Move.left);
    expect(c.state, same(s));
    expect(n, 0);
  });

  test('end run', () {
    final c = GameController(_level(['aSAE']));
    // Ruling: a 0-move echo is allowed while runs remain.
    expect(c.canEndRun, isTrue);
    c.move(Move.left);
    expect(c.canEndRun, isTrue);
    c.endRun();
    expect(c.lastEvent, GameEvent.runEnded);
    expect(c.state.runIndex, 1);
    expect(c.canUndo, isFalse);
    expect(c.previous, isNull);
  });

  test('automatic run end at tick 25 snaps', () {
    final c = GameController(_level(['aSAE']));
    for (var i = 0; i < 25; i++) {
      c.move(Move.wait);
    }
    expect(c.lastEvent, GameEvent.runEnded);
    expect(c.state.runIndex, 1);
    expect(c.previous, isNull);
    expect(c.canUndo, isFalse);
  });

  test('lose', () {
    final c = GameController(_level(['aSAE'], runLimit: 1));
    c.move(Move.left);
    c.endRun();
    expect(c.lastEvent, GameEvent.lost);
    expect(c.state.status, GameStatus.lost);
    expect(c.state.currentRun, [Move.left]);
    expect(c.canUndo, isFalse);
    expect(c.canEndRun, isFalse);
  });

  test('restart resets and notifies even at the start', () {
    final level = _level(['S..E']);
    final c = GameController(level);
    var n = 0;
    c.addListener(() => n++);
    c.restart();
    expect(n, 1);
    c.move(Move.right);
    c.restart();
    expect(n, 3);
    expect(c.state.player, GameState.initial(level).player);
    expect(c.state.tick, 0);
    expect(c.lastEvent, GameEvent.restarted);
    expect(c.previous, isNull);
    expect(c.canUndo, isFalse);
  });

  test('each action notifies exactly once; ignored actions do not', () {
    // One run: Give up at tick 0 is ignored.
    final c = GameController(_level(['aSAE'], runLimit: 1));
    var n = 0;
    c.addListener(() => n++);
    c.undo();
    c.endRun();
    expect(n, 0);
    c.move(Move.left);
    expect(n, 1);
    c.undo();
    expect(n, 2);
    c.move(Move.left);
    c.endRun();
    expect(n, 4);
  });

  test('isBlocked: wall, door and wait', () {
    final c = GameController(_level(['#S.E', 'a.A.']));
    expect(c.isBlocked(Move.left), isTrue);
    expect(c.isBlocked(Move.right), isFalse);
    expect(c.isBlocked(Move.wait), isFalse);
    expect(c.isBlocked(Move.up), isTrue);
    expect(c.isBlocked(Move.down), isFalse);
    c.move(Move.right);
    expect(c.isBlocked(Move.down), isTrue, reason: 'closed door');
  });

  group('New echo at tick 0', () {
    test('allowed on a non-final run: the echo waits on the start', () {
      final c = GameController(_level(['aSAE'], runLimit: 3));
      expect(c.canEndRun, isTrue);
      c.endRun();
      expect(c.lastEvent, GameEvent.runEnded);
      expect(c.state.runIndex, 1);
      expect(c.state.ghosts, [<Move>[]]);
      expect(c.canEndRun, isTrue);
      c.endRun();
      expect(c.state.runIndex, 2);
    });

    test('Give up stays disabled at tick 0 on the final run', () {
      final c = GameController(_level(['aSAE'], runLimit: 1));
      expect(c.canEndRun, isFalse);
      c.endRun();
      expect(c.state.status, GameStatus.playing);
      c.move(Move.left);
      expect(c.canEndRun, isTrue);
    });

    test('nothing ends once the level is over', () {
      final c = GameController(_level(['SE']));
      c.move(Move.right);
      expect(c.state.status, GameStatus.won);
      expect(c.canEndRun, isFalse);
    });
  });

  group('hits', () {
    test('a laser hit is a forced rewind: event hit, a snap, the hit tile', () {
      final c = GameController(_level(['S1.E']));
      expect(c.lastPipHit, isNull);
      c.move(Move.right);
      expect(c.lastEvent, GameEvent.hit);
      expect(c.state.runIndex, 1);
      expect(c.state.player, const Position(0, 0));
      expect(c.previous, isNull);
      expect(c.lastPipHit!.at, const Position(1, 0));
      expect(c.lastPipHit!.cause, HitCause.laser);
    });

    test('the fatal beat: the step before the hit and the beat as it hit', () {
      final c = GameController(_level(['S1.E']));
      expect(c.fatalBeat, isNull);
      final before = c.state;
      c.move(Move.right);
      final (from, at) = c.fatalBeat!;
      expect(identical(from, before), isTrue);
      expect(at.runIndex, 0);
      expect(at.tick, 1);
      expect(at.player, const Position(1, 0));
      expect(at.lastHits.pip, isTrue);
      // Any later change drops it.
      c.move(Move.wait);
      expect(c.fatalBeat, isNull);
    });

    test('no fatal beat for a loss, which keeps its glide', () {
      final c = GameController(_level(['S1.E'], runLimit: 1));
      c.move(Move.right);
      expect(c.fatalBeat, isNull);
    });
  });

  group('undo across a hit', () {
    // Run 0 waits once (a voluntary New echo). In run 1 Pip crosses the
    // crack (it breaks), grabs the spark and stands on the laser, while a
    // far Shade creeps closer; the laser then fires and forces a rewind.
    Level level() => _level(['S~*1E', '####.', 'x....'], runLimit: 4);

    GameController hitRun(List<GameState> seen) {
      final c = GameController(level());
      c.move(Move.wait);
      c.endRun();
      for (final m in [Move.right, Move.right, Move.right]) {
        c.move(m);
        seen.add(c.state);
      }
      c.move(Move.wait);
      return c;
    }

    test('one rewind returns to the state just before the hit beat', () {
      final seen = <GameState>[];
      final c = hitRun(seen);
      final preHit = seen.last;
      expect(c.lastEvent, GameEvent.hit);
      expect(c.state.runIndex, 2);
      expect(c.state.holes, isEmpty);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.lastEvent, GameEvent.none);
      expect(identical(c.state, preHit), isTrue);
      expect(c.state.runIndex, 1);
      expect(c.state.tick, 3);
      expect(c.state.player, const Position(3, 0));
      expect(c.state.holes, {const Position(1, 0)});
      expect(c.state.ghosts, hasLength(1));
      expect(c.state.ghostAlive, [true]);
      expect(c.state.shades, [const Position(3, 2)]);
      expect(c.sparkMask, 1);
      expect(c.previous, isNull);
    });

    test('rewind then goes on through that run, and stops at New echo', () {
      final seen = <GameState>[];
      final c = hitRun(seen);
      c.undo();
      c.undo();
      expect(identical(c.state, seen[1]), isTrue);
      c.undo();
      c.undo();
      expect(c.state.runIndex, 1);
      expect(c.state.tick, 0);
      // The run started with a voluntary New echo: rewind stops here.
      expect(c.canUndo, isFalse);
    });

    test('moves after the hit rewind first, then cross it', () {
      final seen = <GameState>[];
      final c = hitRun(seen);
      c.move(Move.wait);
      c.undo();
      expect(c.state.runIndex, 2);
      expect(c.state.tick, 0);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(identical(c.state, seen.last), isTrue);
    });

    test('a New echo or a restart closes the way back', () {
      final seen = <GameState>[];
      final c = hitRun(seen);
      c.endRun();
      expect(c.state.runIndex, 3);
      expect(c.canUndo, isFalse);

      final r = hitRun(<GameState>[]);
      r.restart();
      expect(r.canUndo, isFalse);
    });

    test('stepping back across two hits in a row', () {
      final c = GameController(_level(['S1.E'], runLimit: 3));
      final start = c.state;
      c.move(Move.right);
      final afterFirst = c.state;
      c.move(Move.right);
      expect(c.state.runIndex, 2);
      c.undo();
      expect(identical(c.state, afterFirst), isTrue);
      c.undo();
      expect(identical(c.state, start), isTrue);
      expect(c.canUndo, isFalse);
    });

    test('a hit on the last run is lost, Pip on the hit tile', () {
      final c = GameController(_level(['S1.E'], runLimit: 1));
      c.move(Move.right);
      expect(c.lastEvent, GameEvent.lost);
      expect(c.state.lastHits.pip, isTrue);
      expect(c.previous, isNotNull);
      expect(c.lastPipHit!.at, const Position(1, 0));
    });

    test('falling into a hole and a Shade catch name their cause', () {
      final hole = GameController(_level(['S~.E']));
      for (final m in [Move.right, Move.right, Move.left]) {
        hole.move(m);
      }
      expect(hole.lastEvent, GameEvent.hit);
      expect(hole.lastPipHit!.cause, HitCause.hole);
      expect(hole.lastPipHit!.at, const Position(1, 0));

      final shade = GameController(_level(['Sx.E']));
      shade.move(Move.wait);
      expect(shade.lastEvent, GameEvent.hit);
      expect(shade.lastPipHit!.cause, HitCause.shade);
      expect(shade.lastPipHit!.at, const Position(0, 0));
    });

    test('lastPipHit clears on the next change', () {
      final c = GameController(_level(['S1.E']));
      c.move(Move.right);
      c.move(Move.wait);
      expect(c.lastPipHit, isNull);
      c.restart();
      c.move(Move.right);
      expect(c.lastPipHit, isNotNull);
      c.restart();
      expect(c.lastPipHit, isNull);
    });

    test('isBlocked is false for a step into a laser from the start', () {
      final c = GameController(_level(['S1.E']));
      expect(c.isBlocked(Move.right), isFalse);
      expect(c.isBlocked(Move.left), isTrue);
    });
  });
}

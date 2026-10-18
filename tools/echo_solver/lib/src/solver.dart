import 'dart:collection';

import 'package:echo_core/echo_core.dart';

sealed class SolveResult {
  const SolveResult();
}

/// The level's minimum total score and a solution reaching it: every run,
/// including the winning one.
class Solved extends SolveResult {
  const Solved(this.bestScore, this.solution);

  final int bestScore;
  final List<List<Move>> solution;
}

class Unsolvable extends SolveResult {
  const Unsolvable();
}

/// The search used more than the allowed number of `Rules.step` calls.
class BudgetExceeded extends SolveResult {
  const BudgetExceeded(this.nodes);

  final int nodes;
}

class _BudgetAbort implements Exception {
  const _BudgetAbort();
}

/// Finds the minimum total score by iterative deepening on the score bound.
/// The first bound that admits a win is the minimum.
SolveResult solve(Level level, {int maxNodes = 5000000}) {
  final search = _Search(level, maxNodes);
  final d0 = search.dist(level.start);
  if (d0 == _Search.unreachable) return const Unsolvable();
  try {
    for (var bound = d0;
        bound <= level.runLimit * Rules.maxTicksPerRun;
        bound++) {
      final win = search.run(bound);
      if (win != null) {
        if (win.score != bound) {
          throw StateError(
              'solver invariant broken: score ${win.score} != bound $bound');
        }
        return Solved(win.score, [...win.ghosts, win.currentRun]);
      }
    }
  } on _BudgetAbort {
    return BudgetExceeded(search.nodes);
  }
  return const Unsolvable();
}

class _Search {
  _Search(this.level, this.maxNodes) {
    _computeDistances();
    d0 = dist(level.start);
  }

  static const unreachable = 1 << 30;

  final Level level;
  final int maxNodes;
  late final int d0;
  int nodes = 0;
  late final List<int> _dist;

  static const _moveOrder = [
    Move.up,
    Move.down,
    Move.left,
    Move.right,
    Move.wait,
  ];

  int dist(Position p) => _dist[p.y * level.width + p.x];

  /// BFS from the exit; doors count as floor, walls are blocked.
  void _computeDistances() {
    final d = List.filled(level.width * level.height, unreachable);
    final queue = Queue<Position>()..add(level.exit);
    d[level.exit.y * level.width + level.exit.x] = 0;
    while (queue.isNotEmpty) {
      final p = queue.removeFirst();
      final here = d[p.y * level.width + p.x];
      for (final m in _moveOrder) {
        final q = p + m.delta;
        if (!_walkable(q)) continue;
        final i = q.y * level.width + q.x;
        if (d[i] == unreachable) {
          d[i] = here + 1;
          queue.add(q);
        }
      }
    }
    _dist = d;
  }

  bool _walkable(Position p) =>
      level.inBounds(p) && level.tileAt(p).kind != TileKind.wall;

  GameState? run(int bound) {
    final root = GameState.initial(level);
    return _dfs(root, bound, level.runLimit == 1 ? <int, int>{} : null);
  }

  GameState _step(GameState s, Move m) {
    if (++nodes > maxNodes) throw const _BudgetAbort();
    return Rules.step(s, m);
  }

  /// [memo] is non-null exactly while in the last run.
  GameState? _dfs(GameState state, int bound, Map<int, int>? memo) {
    if (state.status == GameStatus.won) return state;
    if (state.status == GameStatus.lost) return null;
    final remaining = bound - state.score;
    final lastRun = state.runIndex == level.runLimit - 1;
    if (dist(state.player) > remaining && (lastRun || remaining < d0)) {
      return null;
    }
    if (lastRun) {
      final key = _key(state);
      final seen = memo![key];
      if (seen != null && seen >= remaining) return null;
      memo[key] = remaining;
    }
    for (final move in _moveOrder) {
      if (!_walkable(state.player + move.delta)) continue;
      final next = _step(state, move);
      final win = _dfs(next, bound, _memoFor(state, next, memo));
      if (win != null) return win;
    }
    if (!lastRun &&
        state.tick > 0 &&
        state.currentRun.last != Move.wait &&
        remaining >= d0) {
      final next = Rules.endRun(state);
      final win = _dfs(next, bound, _memoFor(state, next, memo));
      if (win != null) return win;
    }
    return null;
  }

  /// A fresh memo for every entry into the last run; the current one while
  /// staying in it; none before it.
  Map<int, int>? _memoFor(GameState from, GameState to, Map<int, int>? memo) {
    if (to.runIndex == level.runLimit - 1) {
      return to.runIndex > from.runIndex ? <int, int>{} : memo;
    }
    return null;
  }

  /// Canonical packed key of tick, player and every ghost position.
  int _key(GameState s) {
    final cells = level.width * level.height;
    var key = s.tick;
    key = key * cells + s.player.y * level.width + s.player.x;
    for (final g in s.ghostPositions) {
      key = key * cells + g.y * level.width + g.x;
    }
    return key;
  }
}

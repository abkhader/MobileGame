# Follow-ups from Plan 1 (core and solver)

Carried forward from the final whole-branch review of `feat/core-and-solver`.

## Plan 3: do first

**Make the solver scale before designing levels 4–30.** Iterative deepening re-searches every earlier-run prefix at each bound, and only the last run is memoized. Measured on two-plate, three-run levels:

| Grid | Best score | Time |
|---|---|---|
| 6×5 | 14 | 1.5 s |
| 7×6 | 16 | 19 s |
| 8×10 | ≤ 23 | over 160 s, unfinished |

A three-plate, four-run 8×10 level exceeds the default 5M-node budget in 4 s.

1. Add a permanent differential test comparing `solve` with an unpruned search on fixed small levels, and a test where a run auto-ends at tick 25 into the last run. Do this before changing any pruning.
2. Prune non-final runs whose ghost can never stand on a plate or in a doorway.
3. Consider a best-first search ordered by total ticks (spec section 3.2).
4. Add a performance test on a representative 8×10, 3–4 run level.

## Plan 2: the app will need these

- **Tick 25 is invisible.** `Rules.step` auto-ends a non-final run at tick 25 and returns the next run's start state, so the 25th move can't be animated. Either have `GameController` detect `runIndex` changing and compute the intermediate state, or change `step` to return the tick-25 state with a "run must end" flag.
- **Undo across runs.** `GameController` must clear its undo stack whenever `runIndex` changes, including the automatic end at tick 25 (spec section 2.4).
- **Lost state.** When a level is lost, the final run is in `currentRun`/`tick`; it is not appended to `ghosts`. `ghostPositions.length == ghosts.length` always.
- **Hints after deviation.** `level.solution[runIndex]` is only a valid hint if the player's earlier runs match the stored ones. Decide what a hint means otherwise.
- **Level assets.** `levels/` sits at the repo root; Flutter assets usually live inside the app package. Decide how the app bundles them, and add a level manifest for ordering.
- **SDK floor.** When the Flutter SDK is pinned, raise `environment: sdk` in both pubspecs to match (the lockfiles already need Dart ≥ 3.11).

## Small cleanups (any time)

- Reject a non-empty `links` field in `LevelLoader` (reserved, empty at launch).
- Share wall/bounds logic between `Rules` and the solver (`Level.isWalkable`).
- Tighten the `'id'`/`'name'` rejection-message fragments in `level_loader_test.dart`.
- Fix the wrong-bestScore CLI test fixture to use a valid solution (`[['R'], ['R','R','R','R']]`), and test the `solution scores none` branch.
- Restrict the CI `push` trigger to `main` if duplicate PR runs become noise.

## Still to do by Abdullah

Push the repo to GitHub and confirm both CI jobs pass. Then, on a throwaway branch, set `levels/1-03.json` `bestScore` to 6, push, and confirm the solver job fails with `stored 6, computed 5`.

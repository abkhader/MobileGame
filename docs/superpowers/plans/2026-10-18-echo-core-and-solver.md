# Echo Core and Solver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Dart game rules (`echo_core`), the level solver CLI (`echo_solver`), the three tutorial levels, and a CI workflow that tests and validates everything on every push.

**Architecture:** `echo_core` is an immutable-state rules engine with no Flutter dependency: `Rules.step(state, move)` returns a new `GameState`. `echo_solver` reuses it to find each level's minimum score by iterative-deepening search, and writes or checks `bestScore` and `solution` in the level JSON. The Flutter app (Plan 2) will consume both unchanged.

**Tech Stack:** Dart 3 (sealed classes, records), `package:test`, `package:lints`, GitHub Actions with `dart-lang/setup-dart`.

**Spec:** `docs/superpowers/specs/2026-10-15-echo-game-design.md`

**Plan series:** This is Plan 1 of 3. Plan 2 covers the Flutter app (screens, renderer, controller, progress, ads, release build). Plan 3 covers levels 4–30 and sound.

**One naming change from the spec:** the spec's `Action` type is named `Move` here, because Flutter already exports a widely used `Action` class and the app imports both.

## Global Constraints

- Dart SDK constraint `^3.5.0` in every `pubspec.yaml`.
- `echo_core` has no runtime dependencies. Dev dependencies only: `test`, `lints`.
- Analysis uses `package:lints/recommended.yaml`, and CI runs `dart analyze --fatal-infos`.
- Grid: at most 8 columns × 10 rows. Exactly one `S` and one `E`.
- Run limit: 1 to 4. Maximum 25 ticks per run.
- Grid characters: `#` wall, `.` floor, `S` start, `E` exit, `a`–`h` plates, `A`–`H` doors. Each plate letter appears at most once. Every door letter has a matching plate.
- Move codes: `U`, `D`, `L`, `R`, `W`.
- Stars: ★★★ if score ≤ best; ★★ if score ≤ floor(1.5 × best); otherwise ★.
- Coordinates: `x` is the column, `y` is the row, and `y` grows downward (`up` is `(0, -1)`).
- A level file is named `<id>.json`.

## Review Focus

1. **Ending a run at tick 0.** Expected: allowed; the empty ghost stands on the start tile and the run counts toward the limit. (Plan 2 disables the button at tick 0.) Pinned in Task 4.
2. **One plate linked to several doors.** Expected: pressing the plate opens every door with that letter. Pinned in Task 3.
3. **Reaching the exit on exactly tick 25.** Expected: a win, not an automatic run end. Pinned in Task 4.
4. **A ghost reaching the exit.** Expected: no win; only the player counts. Pinned in Task 4.
5. **A level too large for the solver.** Expected: a clear "search budget exceeded" failure, never a hang. Pinned in Tasks 6 and 7.

---

## File Structure

```
packages/echo_core/
  pubspec.yaml, analysis_options.yaml
  lib/echo_core.dart              exports everything below
  lib/src/position.dart           Position value type
  lib/src/move.dart               Move enum (codes, deltas)
  lib/src/tile.dart               TileKind, Tile
  lib/src/level.dart              Level (immutable grid + metadata)
  lib/src/level_loader.dart       JSON parsing + validation, LevelFormatException
  lib/src/game_state.dart         GameStatus, GameState
  lib/src/rules.dart              Rules.step, Rules.endRun
  lib/src/scoring.dart            Scoring.stars
  test/support/fixtures.dart      test helpers: lvl(), play()
  test/*_test.dart
tools/echo_solver/
  pubspec.yaml, analysis_options.yaml
  bin/echo_solver.dart            entry point → runCli
  lib/echo_solver.dart            exports
  lib/src/solver.dart             solve(), SolveResult
  lib/src/replay.dart             replayScore()
  lib/src/cli.dart                runCli()
  test/*_test.dart
levels/1-01.json, 1-02.json, 1-03.json
.github/workflows/ci.yml
.gitignore
```

---

### Task 1: Core package and value types

**Files:**
- Create: `.gitignore`, `packages/echo_core/pubspec.yaml`, `packages/echo_core/analysis_options.yaml`, `packages/echo_core/lib/echo_core.dart`, `lib/src/position.dart`, `lib/src/move.dart`, `lib/src/tile.dart`
- Test: `packages/echo_core/test/value_types_test.dart`

**Interfaces:**
- Produces:
  - `class Position { const Position(int x, int y); final int x, y; Position operator +(Position o); }` with value equality and `hashCode`, and `toString()` returning `(x, y)`
  - `enum Move { up, down, left, right, wait }` with `String get code` (`U`,`D`,`L`,`R`,`W`), `Position get delta`, and `static Move fromCode(String c)` that throws `ArgumentError` for unknown codes
  - `enum TileKind { floor, wall, start, exit, plate, door }`
  - `class Tile { const Tile(TileKind kind, {String? channel}); final TileKind kind; final String? channel; }` where `channel` is the lowercase letter for plates and doors, and `null` otherwise. Value equality.

- [ ] **Step 1: Prerequisite.** Run `dart --version`. Expected: Dart SDK 3.5 or newer. If missing, stop and report; do not continue without it.

- [ ] **Step 2: Create the package files.** `pubspec.yaml`: `name: echo_core`, `publish_to: none`, `environment: sdk: ^3.5.0`, `dev_dependencies: lints: ^5.0.0, test: ^1.25.0`. `analysis_options.yaml`: `include: package:lints/recommended.yaml`. `.gitignore` at the repo root: `.dart_tool/`, `build/`, `pubspec.lock` is **kept** (not ignored). Run `dart pub get` in `packages/echo_core`. Expected: "Got dependencies!"

- [ ] **Step 3: Write the failing test**

```dart
test('positions add and compare by value', () {
  expect(const Position(1, 2) + const Position(3, -1), const Position(4, 1));
  expect({const Position(1, 1), const Position(1, 1)}.length, 1);
});
test('moves map to codes and deltas', () {
  expect(Move.values.map((m) => m.code).join(), 'UDLRW');
  expect(Move.up.delta, const Position(0, -1));
  expect(Move.right.delta, const Position(1, 0));
  expect(Move.wait.delta, const Position(0, 0));
  expect(Move.fromCode('L'), Move.left);
  expect(() => Move.fromCode('X'), throwsArgumentError);
});
test('tiles compare by kind and channel', () {
  expect(const Tile(TileKind.door, channel: 'a'), const Tile(TileKind.door, channel: 'a'));
  expect(const Tile(TileKind.door, channel: 'a') == const Tile(TileKind.door, channel: 'b'), isFalse);
});
```

- [ ] **Step 4: Run** `dart test test/value_types_test.dart`. Expected: FAIL (types not defined).

- [ ] **Step 5: Implement** the three types listed in Interfaces, and export them from `lib/echo_core.dart`.

- [ ] **Step 6: Run** `dart test && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed .`. Expected: all tests pass, no analysis issues, no formatting changes.

- [ ] **Step 7: Commit** `feat(core): add Position, Move and Tile value types`

---

### Task 2: Level model and loader

**Files:**
- Create: `packages/echo_core/lib/src/level.dart`, `lib/src/level_loader.dart`
- Test: `packages/echo_core/test/level_loader_test.dart`

**Interfaces:**
- Consumes: `Position`, `Move`, `Tile`, `TileKind` (Task 1)
- Produces:
  - `class Level` with fields `String id, name; int runLimit, width, height; String? tip; int? bestScore; List<List<Move>>? solution; Position start, exit; Map<String, Position> plates; Map<String, List<Position>> doors` (both keyed by the lowercase letter), plus `Tile tileAt(Position p)` and `bool inBounds(Position p)`. Constants `static const maxWidth = 8, maxHeight = 10, maxRunLimit = 4`.
  - `class LevelFormatException implements Exception { final String message; }`
  - `abstract final class LevelLoader { static Level parse(String json); static Level fromMap(Map<String, dynamic> map); }`

- [ ] **Step 1: Write the failing tests.** One valid case, then one test per rejection. Every rejection must throw `LevelFormatException` whose `message` contains the given fragment.

```dart
const valid = '{"id":"1-02","name":"Hold","runLimit":1,"tip":"t",'
  '"grid":["#####","#SaA#","#..E#"],"bestScore":4,"solution":[["R","R"]]}';

test('parses a valid level', () {
  final l = LevelLoader.parse(valid);
  expect((l.id, l.width, l.height, l.runLimit), ('1-02', 5, 3, 1));
  expect((l.start, l.exit), (const Position(1, 1), const Position(3, 2)));
  expect(l.tileAt(const Position(2, 1)), const Tile(TileKind.plate, channel: 'a'));
  expect(l.doors['a'], [const Position(3, 1)]);
  expect(l.solution, [[Move.right, Move.right]]);
  expect(l.inBounds(const Position(5, 0)), isFalse);
});
test('tip, bestScore and solution are optional', () { /* omit all three → nulls */ });
```

Rejection cases (`grid` / field change → message fragment):

| Case | Fragment |
|---|---|
| rows of different length | `rectangular` |
| 9 columns | `at most 8 columns` |
| 11 rows | `at most 10 rows` |
| no `S` | `exactly one S` |
| two `E` | `exactly one E` |
| `runLimit` 0, and 5 | `runLimit` |
| `a` twice | `plate 'a'` |
| `B` with no `b` | `door 'B'` |
| `?` in grid | `unknown character '?' at (x, y)` with real coordinates |
| solution contains `"X"` | `solution` |
| missing `id` | `id` |

- [ ] **Step 2: Run** `dart test test/level_loader_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement** `Level` and `LevelLoader`. `parse` wraps `jsonDecode` errors as `LevelFormatException('invalid JSON: …')`. Wrong field types (for example `runLimit` as a string) also become `LevelFormatException`, never a `TypeError`.

- [ ] **Step 4: Run** the full test, analyze and format command from Task 1, Step 6. Expected: pass.

- [ ] **Step 5: Commit** `feat(core): add Level model and validating LevelLoader`

---

### Task 3: Game state and single-run rules

**Files:**
- Create: `packages/echo_core/lib/src/game_state.dart`, `lib/src/rules.dart`, `test/support/fixtures.dart`
- Test: `packages/echo_core/test/rules_single_run_test.dart`

**Interfaces:**
- Consumes: `Level`, `LevelLoader.fromMap`, `Move`, `Position` (Tasks 1–2)
- Produces:
  - `enum GameStatus { playing, won, lost }`
  - `class GameState` (immutable, unmodifiable collections) with fields `Level level; int runIndex` (0-based)`; int tick` (ticks taken in the current run)`; List<Move> currentRun; List<List<Move>> ghosts` (completed runs, oldest first)`; Position player; List<Position> ghostPositions` (parallel to `ghosts`)`; Set<Position> openDoors; int completedTicks; GameStatus status`, plus `int get score => completedTicks + tick` and `factory GameState.initial(Level level)`
  - `abstract final class Rules { static const maxTicksPerRun = 25; static GameState step(GameState s, Move m); static GameState endRun(GameState s); }`. Task 3 implements `step` for the player only (no ghosts yet). Leave `endRun` throwing `UnimplementedError`.
  - Test fixtures: `Level lvl(List<String> grid, {int runLimit = 1})` and `GameState play(GameState s, String script)`, where each character is a move code and `|` calls `Rules.endRun`.

- [ ] **Step 1: Write the failing tests**

```dart
test('moving onto floor advances the player, tick and recording', () {
  final s = play(GameState.initial(lvl(['S..E'])), 'R');
  expect((s.player, s.tick, s.currentRun), (const Position(1, 0), 1, [Move.right]));
});
test('walls and grid edges block, but the tick still counts', () {
  final s = play(GameState.initial(lvl(['#S.E'])), 'LU');
  expect((s.player, s.tick), (const Position(1, 0), 2));
});
test('a closed door blocks', () {
  final s = play(GameState.initial(lvl(['SAE', 'a..'])), 'R');
  expect(s.player, const Position(0, 0));
});
test('a door opens at the end of the tick its plate is pressed, '
    'stays open while occupied, and the player wins on the exit', () {
  var s = play(GameState.initial(lvl(['SaAE'])), 'R');
  expect(s.openDoors, {const Position(2, 0)});
  s = play(s, 'R'); // into the doorway, plate released
  expect(s.openDoors, {const Position(2, 0)}); // no crushing
  s = play(s, 'R');
  expect((s.status, s.score), (GameStatus.won, 3));
});
test('a door closes when its plate and doorway are empty', () {
  final s = play(GameState.initial(lvl(['SaA.E'])), 'RL');
  expect(s.openDoors, isEmpty);
});
test('one plate opens every door with its letter', () {
  final s = play(GameState.initial(lvl(['SaAE', '..A.'])), 'R');
  expect(s.openDoors, {const Position(2, 0), const Position(2, 1)});
});
test('stepping after the level ends throws StateError', () {
  final s = play(GameState.initial(lvl(['SE'])), 'R');
  expect(() => Rules.step(s, Move.wait), throwsStateError);
});
```

- [ ] **Step 2: Run** `dart test test/rules_single_run_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement** `GameState` and `Rules.step`. A move is blocked if the target is out of bounds, a wall, or a door not in the *incoming* `state.openDoors`. After moving, `openDoors` is every door whose plate letter is under any actor, plus every door tile with an actor on it. Set `won` when the player is on the exit.

- [ ] **Step 4: Run** the full test, analyze and format command. Expected: pass.

- [ ] **Step 5: Commit** `feat(core): add GameState and single-run movement rules`

---

### Task 4: Runs, ghosts, the tick cap and losing

**Files:**
- Modify: `packages/echo_core/lib/src/rules.dart`
- Test: `packages/echo_core/test/rules_runs_test.dart`

**Interfaces:**
- Consumes: everything from Task 3
- Produces: the complete `Rules.step` (ghosts move before the player, oldest first, with recorded move at index `tick`, or `wait` when the recording has ended) and `Rules.endRun`. `endRun` appends `currentRun` to `ghosts`, adds `tick` to `completedTicks`, and either sets `lost` (when `runIndex == runLimit - 1`) or starts the next run with `runIndex + 1`, `tick` 0, an empty `currentRun`, and every actor on `start` with doors recomputed. `step` calls `endRun` itself when `tick` reaches 25 without a win.

- [ ] **Step 1: Write the failing tests.** Grid `G = ['aSAE']`: plate at (0,0), start at (1,0), door at (2,0), exit at (3,0).

```dart
test('endRun records a ghost and resets actors to start', () {
  final s = play(GameState.initial(lvl(G, runLimit: 2)), 'L|');
  expect((s.runIndex, s.tick, s.completedTicks), (1, 0, 1));
  expect((s.ghosts, s.player, s.ghostPositions), ([[Move.left]], const Position(1, 0), [const Position(1, 0)]));
});
test('a ghost opens a door only from the next tick', () {
  var s = play(GameState.initial(lvl(G, runLimit: 2)), 'L|R');
  expect(s.player, const Position(1, 0)); // blocked: door was closed at the end of the previous tick
  expect(s.openDoors, {const Position(2, 0)});
  s = play(s, 'RR');
  expect((s.status, s.score), (GameStatus.won, 4));
});
test('a finished ghost stays where it stopped', () {
  final s = play(GameState.initial(lvl(G, runLimit: 2)), 'L|WW');
  expect(s.ghostPositions, [const Position(0, 0)]);
});
test('ghost moves are re-evaluated against current doors', () {
  // Run 1: wait, then R into a closed door (blocked). Run 2: the player presses the plate first.
  final s = play(GameState.initial(lvl(G, runLimit: 2)), 'WR|LW');
  expect(s.ghostPositions, [const Position(2, 0)]);
});
test('a ghost on the exit does not win', () {
  final s = play(GameState.initial(lvl(G, runLimit: 2)), 'WRR|LWW');
  expect(s.ghostPositions, [const Position(3, 0)]);
  expect(s.status, GameStatus.playing);
});
test('ending the last run loses', () {
  final s = play(GameState.initial(lvl(G)), 'L|');
  expect(s.status, GameStatus.lost);
});
test('a run ends automatically after 25 ticks', () {
  final s = play(GameState.initial(lvl(G, runLimit: 2)), 'W' * 25);
  expect((s.runIndex, s.tick, s.completedTicks), (1, 0, 25));
});
test('reaching the exit on tick 25 wins', () {
  final s = play(GameState.initial(lvl(['S...E'])), '${'W' * 21}RRRR');
  expect((s.status, s.score), (GameStatus.won, 25));
});
test('ending a run at tick 0 records an empty ghost', () {
  final s = play(GameState.initial(lvl(G, runLimit: 2)), '|');
  expect((s.runIndex, s.ghosts, s.ghostPositions), (1, [<Move>[]], [const Position(1, 0)]));
});
```

- [ ] **Step 2: Run** `dart test test/rules_runs_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement** ghost replay, `endRun` and the 25-tick cap in `rules.dart`.

- [ ] **Step 4: Run** the full test, analyze and format command (Task 3 tests must still pass). Expected: pass.

- [ ] **Step 5: Commit** `feat(core): add runs, ghost replay, tick cap and losing`

---

### Task 5: Scoring

**Files:**
- Create: `packages/echo_core/lib/src/scoring.dart`
- Test: `packages/echo_core/test/scoring_test.dart`

**Interfaces:**
- Produces: `abstract final class Scoring { static int stars({required int score, required int best}); }`, returning 1–3.

- [ ] **Step 1: Write the failing test**

```dart
test('stars follow the spec thresholds', () {
  int s(int score, int best) => Scoring.stars(score: score, best: best);
  expect([s(5, 5), s(7, 5), s(8, 5), s(4, 4), s(6, 4), s(7, 4), s(3, 5)], [3, 2, 1, 3, 2, 1, 3]);
});
```

- [ ] **Step 2: Run** it. Expected: FAIL.
- [ ] **Step 3: Implement**, using integer math `score * 2 <= best * 3` for the ★★ threshold to avoid floating-point rounding.
- [ ] **Step 4: Run** the full test, analyze and format command. Expected: pass.
- [ ] **Step 5: Commit** `feat(core): add star scoring`

---

### Task 6: Solver search

**Files:**
- Create: `tools/echo_solver/pubspec.yaml` (`echo_core` via `path: ../../packages/echo_core`; same dev dependencies and lints), `analysis_options.yaml`, `lib/echo_solver.dart`, `lib/src/solver.dart`, `lib/src/replay.dart`
- Test: `tools/echo_solver/test/solver_test.dart`

**Interfaces:**
- Consumes: `Level`, `GameState`, `Rules`, `Move`, `LevelLoader` (core)
- Produces:
  - `sealed class SolveResult`, with subclasses `Solved(int bestScore, List<List<Move>> solution)`, `Unsolvable()` and `BudgetExceeded(int nodes)`
  - `SolveResult solve(Level level, {int maxNodes = 5000000})`
  - `int? replayScore(Level level, List<List<Move>> runs)`: plays the runs with `Rules.endRun` between them, and returns the score only if the final move of the final run wins and no moves are left over; otherwise `null`

**Search algorithm** (iterative deepening on total score; the first bound that finds a win is the minimum):

```
dist = BFS distances to the exit, treating doors as floor and walls as blocked
if dist[start] is unreachable → Unsolvable
d0 = dist[start]
for bound in d0 .. runLimit * 25:
    if dfs(GameState.initial(level), bound) finds a win → Solved(bound, ghosts + [currentRun])
return Unsolvable

dfs(state, bound):
    count one node per Rules.step call; above maxNodes → BudgetExceeded
    if state.status == won → found;  if lost → fail
    remaining = bound - state.score
    lastRun = state.runIndex == runLimit - 1
    if dist[player] > remaining and (lastRun or remaining < d0) → fail
    if lastRun: memo keyed by (tick, player, ghostPositions), fresh for each
        entry into the last run; skip if memo already holds a budget ≥ remaining
    for move in U, D, L, R, W:
        skip moves whose target is out of bounds or a wall (identical to W, now and in replay)
        recurse on Rules.step(state, move)
    if not lastRun and tick > 0 and last recorded move != W and remaining >= d0:
        recurse on Rules.endRun(state)   # trailing waits are never needed
```

- [ ] **Step 1: Write the failing tests**

```dart
Level l(List<String> g, int runs) => LevelLoader.fromMap({'id': 't', 'name': 't', 'runLimit': runs, 'grid': g});

test('corridor', () {
  final r = solve(l(['#######', '#S...E#', '#######'], 1)) as Solved;
  expect((r.bestScore, r.solution), (4, [[Move.right, Move.right, Move.right, Move.right]]));
});
test('single-run plate and door', () {
  expect((solve(l(['#######', '#S.aAE#', '#######'], 1)) as Solved).bestScore, 4);
});
test('two-run echo level', () {
  final level = l(['#######', '#Sa.AE#', '#######'], 2);
  final r = solve(level) as Solved;
  expect(r.bestScore, 5);
  expect(replayScore(level, r.solution), 5);
});
test('the echo level is unsolvable with one run', () {
  expect(solve(l(['#######', '#Sa.AE#', '#######'], 1)), isA<Unsolvable>());
});
test('an unreachable exit is unsolvable', () {
  expect(solve(l(['S#E'], 4)), isA<Unsolvable>());
});
test('a tiny budget reports BudgetExceeded instead of searching on', () {
  expect(solve(l(['#######', '#Sa.AE#', '#######'], 2), maxNodes: 10), isA<BudgetExceeded>());
});
test('replayScore rejects non-winning and over-long solutions', () {
  final level = l(['S..E'], 1);
  expect(replayScore(level, [[Move.right]]), isNull);
  expect(replayScore(level, [[Move.right, Move.right, Move.right, Move.wait]]), isNull);
});
```

- [ ] **Step 2: Run** `dart pub get && dart test` in `tools/echo_solver`. Expected: FAIL.
- [ ] **Step 3: Implement** `solve` and `replayScore` as specified.
- [ ] **Step 4: Run** the full test, analyze and format command in `tools/echo_solver`. Expected: pass, with the whole suite under 10 seconds.
- [ ] **Step 5: Commit** `feat(solver): add iterative-deepening level solver and replay check`

---

### Task 7: Solver CLI and tutorial levels

**Files:**
- Create: `tools/echo_solver/lib/src/cli.dart`, `bin/echo_solver.dart`, `levels/1-01.json`, `levels/1-02.json`, `levels/1-03.json`
- Test: `tools/echo_solver/test/cli_test.dart`

**Interfaces:**
- Consumes: `solve`, `replayScore`, `LevelLoader`
- Produces: `Future<int> runCli(List<String> args, {StringSink? out})`, returning the process exit code. Usage: `echo_solver <levels-dir> (--check | --write) [--max-nodes N]`.
  - **`--check`:** for each `*.json` in name order, prints `<file>: OK (best N)` or `<file>: FAIL <reason>`. It fails on: a format error (the loader message), `id` not matching the file name, unsolvable, budget exceeded, missing or wrong `bestScore` (`stored X, computed Y`), and a missing `solution` or one whose `replayScore` ≠ `bestScore`. Exits 1 if any file failed, 0 otherwise.
  - **`--write`:** like `--check`, but sets `bestScore` and `solution` from the solver, preserves the other fields, and rewrites the file with `JsonEncoder.withIndent('  ')` plus a trailing newline. Format errors, unsolvable levels and budget failures still fail.
  - Bad arguments print the usage line and exit 64.

- [ ] **Step 1: Write the failing tests** using a temporary directory per test:
  - `--write` on a level without `bestScore` adds `bestScore` and `solution`; a following `--check` exits 0.
  - `--check` on the `1-03` grid from the table in Step 4, written with a correct `solution` and `bestScore` 9, exits 1, and the output contains `stored 9, computed 5`.
  - `--check` on a file named `x.json` whose `id` is `y` exits 1 and the output contains `id`.
  - `--check` on an unsolvable level exits 1 with `unsolvable`.
  - `--max-nodes 10` exits 1 with `budget exceeded`.
  - No mode flag exits 64.

- [ ] **Step 2: Run** `dart test test/cli_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement** `runCli` and a two-line `bin/echo_solver.dart` that calls it and sets `exitCode`.

- [ ] **Step 4: Add the tutorial levels** (without `bestScore` or `solution`):

| File | name | runLimit | grid | tip |
|---|---|---|---|---|
| `1-01.json` | First Step | 1 | `#######`, `#S...E#`, `#######` | Swipe to move. Reach the exit. |
| `1-02.json` | Hold the Door | 1 | `#######`, `#S.aAE#`, `#######` | Step on a plate to open its door. |
| `1-03.json` | Echo | 2 | `#######`, `#Sa.AE#`, `#######` | Tap End run. Your past self will help you. |

- [ ] **Step 5: Run** `dart run bin/echo_solver.dart ../../levels --write`, then `--check`. Expected: `1-01.json: OK (best 4)`, `1-02.json: OK (best 4)`, `1-03.json: OK (best 5)`, exit 0.

- [ ] **Step 6: Run** the full test, analyze and format command. Expected: pass.

- [ ] **Step 7: Commit** `feat(solver): add check/write CLI and tutorial levels`

---

### Task 8: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the commands from Tasks 1–7

- [ ] **Step 1: Write the workflow.** It triggers on `push` and `pull_request` and has two jobs, `core` and `solver`. Each uses `actions/checkout@v4` and `dart-lang/setup-dart@v1` with `sdk: stable`, sets `working-directory` to its package, and runs in order: `dart pub get`, `dart format --output=none --set-exit-if-changed .`, `dart analyze --fatal-infos`, `dart test`. The `solver` job adds a final step: `dart run bin/echo_solver.dart ../../levels --check`.

- [ ] **Step 2: Validate the YAML syntax locally** with `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"`. Expected: no output.

- [ ] **Step 3: Prove the gate works.** Push to the GitHub remote and confirm both jobs pass. Then, on a throwaway branch, change `levels/1-03.json` `bestScore` to 6, push, and confirm the `solver` job fails with `stored 6, computed 5`. Delete the branch.

- [ ] **Step 4: Commit** `ci: test core and solver, validate levels on every push`

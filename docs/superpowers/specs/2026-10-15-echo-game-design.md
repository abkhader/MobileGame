# Echo — Game Design Spec

**Date:** 2026-10-15
**Status:** Draft for review
**Platform:** Android (Google Play), built with Flutter + Flame

---

## 1. Goal

Echo is a turn-based, neon-styled puzzle game in which each level is solved across several runs. Every finished run replays as a ghost, and the player must coordinate with their past selves to reach the exit.

The project has two equal goals:

1. **Earn revenue** through ads, so retention and ad placement matter.
2. **Serve as a portfolio piece** with clean, layered, well-tested code.

### Success criteria

- 30 handcrafted levels, every one verified solvable by the solver in CI.
- Every game rule covered by unit tests.
- CI builds a signed release `.aab` and APK on every push to `main`.
- Ads integrated with test IDs and a consent form, and the game never blocks on an ad.
- The game runs smoothly on a mid-range Android phone.

### Constraints

- The Play Console account is opened only after the game is built and play-tested. Until then, releases stay as CI build artifacts.
- No paid tools or assets. All visuals are drawn in code, and sounds are free-licensed.
- Target Android API level 36, as Google Play requires for new apps.

---

## 2. Game rules

### 2.1 Level contents

A level is a rectangular grid of at most 8 columns × 10 rows. Each tile is one of:

| Tile | Behavior |
|---|---|
| Floor | Walkable |
| Wall | Never walkable |
| Start | Walkable; every run begins here (exactly one per level) |
| Exit | Walkable; reaching it wins (exactly one per level) |
| Plate | Walkable; pressed while any actor stands on it |
| Door | Walkable only while open; linked to exactly one plate |

A plate may be linked to more than one door. A door is linked to exactly one plate.

Each level also defines a **run limit** between 1 and 4.

### 2.2 Runs

- A run starts with the player on the Start tile at tick 0.
- Each tick, the player either **moves** one tile (up, down, left or right) or **waits**.
- The player ends a run by tapping **End run**. A single run may last at most 25 ticks; at tick 25, the run ends automatically.
- The finished run's actions are recorded. The next run begins at tick 0 with all previous runs replaying as ghosts.

### 2.3 Tick resolution

Each tick resolves in this order:

1. Ghosts perform their recorded action for this tick, oldest ghost first. A ghost whose recording has ended stays where it stopped.
2. The player performs their action.
3. Doors update: a door is open if any actor (player or ghost) stands on its plate, and closed otherwise.

Moves in steps 1 and 2 see the door states from the end of the previous tick. A door opened this tick becomes passable on the next tick.

### 2.4 Rules

- **Blocked moves.** Moving into a wall, a closed door or off the grid leaves the actor in place, and the tick still counts. Ghosts follow the same rule. A ghost whose recorded move is blocked stays put; there is no paradox failure.
- **No crushing.** A door stays open while any actor stands in its doorway, even if its plate is released.
- **No collisions.** Any number of actors may share a tile.
- **Win.** The player reaches the Exit on any run. Ghosts reaching the Exit do not count.
- **Lose.** The player ends the final allowed run without reaching the Exit. The level can then be restarted.
- **Undo.** The player may undo moves within the current run without limit. Completed runs cannot be undone; the player restarts the level instead.

### 2.5 Scoring

- **Score** is the total number of ticks across all runs, including the winning run up to the tick the Exit is reached.
- **Best score** for each level is computed by the solver and stored in the level file.
- **Stars:**
  - ★★★ if score equals the best score
  - ★★ if score is at most 1.5 × the best score (rounded down)
  - ★ for any completion

---

## 3. Architecture

One Git repository with three parts. Game rules never depend on rendering, input or ads.

```
echo/
  packages/echo_core/   pure Dart: rules, models, loading, scoring
  tools/echo_solver/    Dart CLI: verifies levels, computes best scores
  app/                  Flutter + Flame: screens, rendering, ads, storage
  levels/               level JSON files (shared by app and solver)
```

### 3.1 `echo_core` (pure Dart, no Flutter dependency)

| Unit | Responsibility |
|---|---|
| `Position`, `Action`, `Tile` | Value types |
| `Level` | Immutable grid, plate-door links, run limit, best score, solution |
| `GameState` | Immutable snapshot: tick, current run's actions, ghost recordings, actor positions, door states, status (playing, won, lost) |
| `Rules.step(state, action)` | Pure function implementing Section 2.3–2.4 |
| `Rules.endRun(state)` | Records the run and starts the next, or marks the level lost |
| `LevelLoader` | Parses and validates level JSON |
| `Scoring` | Computes stars from score and best score |

Undo is a stack of previous `GameState` values held by the caller.

### 3.2 `echo_solver` (Dart command-line tool)

- Reuses `echo_core` so the solver and the game cannot disagree on rules.
- Performs a breadth-first search over the joint plan of all runs, ordered by total ticks, to find the minimum score.
- Writes `bestScore` and the optimal `solution` (one action list per run) into the level file.
- **`--check` mode** (used in CI) fails if any level is unsolvable, has an invalid structure, or has a stored best score that differs from the computed one.
- Runs offline only, never on the device. The grid, run and tick caps in Section 2 keep the search tractable.

### 3.3 `app` (Flutter)

| Unit | Responsibility |
|---|---|
| Screens | Home, Level Select, Game, Level Complete, Settings |
| `GameController` | Converts swipes and taps into actions, calls `Rules`, holds the undo stack, exposes state to the UI |
| Flame renderer | Draws the current state and animates transitions between states |
| `ProgressRepository` | Stars per level and settings, stored with `shared_preferences` |
| `AdService` (interface) | `AdMobAdService` for real ads, `FakeAdService` for tests |
| `HintService` | Returns the stored solution path for the current run |

**Data flow:** input → `GameController` → `Rules.step` → new `GameState` → renderer animates the difference.

### 3.4 Level file format

```json
{
  "id": "1-01",
  "name": "First Step",
  "runLimit": 1,
  "grid": [
    "#######",
    "#S...E#",
    "#######"
  ],
  "links": [],
  "tip": "Swipe to move. Reach the exit.",
  "bestScore": 4,
  "solution": [["R", "R", "R", "R"]]
}
```

- Grid characters: `#` wall, `.` floor, `S` start, `E` exit, `a`–`h` plates, `A`–`H` doors. A door opens when the plate with the matching lowercase letter is pressed. Each plate letter appears at most once; a door letter may appear several times, and every door letter must have a matching plate.
- `links` is reserved for future mechanics and is empty at launch.
- `tip` is optional and shown on tutorial levels.
- Solution actions: `U`, `D`, `L`, `R`, `W` (wait).

---

## 4. Presentation

### 4.1 Visual style

- Dark navy-black background with a faint grid.
- Player: a glowing white dot.
- Ghosts: one neon color each (cyan, magenta, amber), with a fading trail of their recent path.
- Plates glow when pressed. Doors are neon bars that slide open and closed.
- Each tick animates in about 150 ms. A new input during an animation completes the current one immediately.
- All visuals are drawn in code; there are no image assets.

### 4.2 Controls

- Swipe in a direction to move one tile.
- Tap anywhere on the grid to wait one tick.
- On-screen buttons: Undo, End run, Restart, Hint.

### 4.3 Sound

- A calm ambient loop plus short sounds for moving, plate press, door open and close, run end and win.
- Free-licensed assets only, with licenses recorded in the repository.
- Separate music and sound-effect toggles in Settings.

---

## 5. Levels and progression

30 levels at launch, in three chapters:

| Chapter | Levels | Runs | Focus |
|---|---|---|---|
| 1 | 1–10 | 1–2 | Movement, waiting, plates, doors, first ghost. Levels 1–3 show tips. |
| 2 | 11–20 | 2–3 | Multiple doors and timing |
| 3 | 21–30 | 3–4 | Hard multi-ghost coordination |

- Levels unlock in order. Completing a level unlocks the next, with no star requirement.
- Level Select shows each level's best star rating.

---

## 6. Ads

Integrated with the official `google_mobile_ads` plugin and the UMP consent SDK. Google's published test ad unit IDs are used until a real AdMob account exists.

| Placement | Type | Rule |
|---|---|---|
| Between levels | Interstitial | After every 3rd completed level, starting after level 5. Never during play. |
| Hint | Rewarded | Reveals the current run's path from the stored solution |
| Skip level | Rewarded | Marks the level complete with 0 stars and unlocks the next |

- The consent form is shown on first launch where required. Ads load only after consent is resolved.
- If an interstitial isn't loaded, it is skipped silently.
- If a rewarded ad fails, the player sees "No ad available right now, try again later," and the reward is not granted.

---

## 7. Error handling

| Failure | Behavior |
|---|---|
| Invalid or missing level file | Blocked in CI by the solver. At runtime, an error card is shown and the player returns to Level Select. |
| Ad fails to load or show | See Section 6. Gameplay never waits on an ad. |
| Corrupt saved progress | Reset to defaults and continue. |
| Unexpected crash | Reported via Firebase Crashlytics, added in the release phase. |

---

## 8. Testing

1. **Core unit tests** (`echo_core`), written test-first: every rule in Section 2, including blocked moves, door update timing, ghost replay, a ghost blocked mid-replay, no crushing, shared tiles, the 25-tick cap, win and lose, undo and scoring.
2. **Solver tests:** small known levels with hand-computed best scores, plus `--check` run over every level in `levels/`.
3. **App widget tests:** screens, navigation, unlocking and ad rules, using `FakeAdService`.
4. **Integration test:** plays level 1 to completion on an Android emulator in CI.

---

## 9. CI/CD (GitHub Actions)

Runs on every push and pull request:

1. `dart format --set-exit-if-changed` and `dart analyze`
2. Core tests
3. Solver `--check` over all levels
4. App widget tests
5. Emulator integration test
6. On `main` only: build a release `.aab` and APK signed with the upload key from GitHub secrets, and publish both as build artifacts

**Added later**, once the Play Console account exists: Fastlane `supply` uploads the `.aab` to the internal testing track.

---

## 10. Out of scope for launch

Planned for later updates:

- New mechanics (pushable boxes first)
- Daily challenge
- "Remove ads" purchase via Google Play Billing
- Arabic language
- iOS release
- Cloud saves via Play Games Services
- Fastlane upload and Play release automation

---

## 11. Manual steps (owner: Abdullah)

These cannot be automated and happen only when the game is ready:

1. Create the Google Play Console account and complete identity verification.
2. Create the AdMob account and real ad unit IDs.
3. Fill in the content rating, Data Safety and privacy policy forms.
4. Run the closed test with real testers for the required period.
5. Approve the production release.

Generating the upload signing key and adding it to GitHub secrets is done early, before the first CI release build.

# Echo: Flowing Time (Rebuild Round 1 of 6) — Design

**Status:** approved in conversation 2026-10-22; written spec awaiting review.
**Binding parents:** `2026-10-15-echo-game-design.md` (rules, levels, ads), `2026-10-22-echo-story-design.md` (Pip, Lumen City, cards, map).

## 0. The rebuild

The owner wants Echo to be the most attractive game of its kind on Google Play: keep its heart (Pip, echoes of past runs, Lumen City), change a lot, add features. The rebuild runs in six rounds, each with its own spec, plan and review:

1. **Flowing time** — new movement and feel (this spec).
2. Light sparks — 3 per level, a new star system.
3. Dangers — lasers, crumbling floor (rules approved 2026-10-22), Shade enemies; Chapter 4.
4. Pip abilities — dash, light burst, swap with an echo, freeze time.
5. Bosses — one per district.
6. Final polish — art, effects and sound across the game.

Assumptions carried through every round: every level stays provably solvable by the checker (so enemies follow fixed rules); existing levels are adapted, not discarded; Android first; all art drawn in code.

## 1. Goal of this round

Turn-based swiping felt stiff, awkward and slow. Replace it with **"time moves when Pip moves"**: the player steers continuously, the whole world moves at Pip's pace, and it freezes when the player lets go. Puzzles and their proofs are unchanged.

Success:
- Moving feels fluid and immediate on a phone (thumb) and on a computer (keys).
- A player can always stop and think; nothing is lost by being slow.
- All 30 levels, their best scores and stored solutions remain valid; the solver and the rules engine are unchanged.

## 2. Controls and time

### 2.1 Beats
- Game logic stays discrete: one **beat** = one `Rules.step`. A glide from one tile to the next is one beat; waiting in place is one beat (`Move.wait`).
- Beat length by speed setting: **Slow 300 ms, Normal 200 ms, Fast 140 ms** (Normal ≈ 5 tiles/s).
- While an input is held, the game clock fires one beat per beat length; rendering interpolates between beats, so motion is continuous.

### 2.2 Moving (phone)
- Touching anywhere in the **lower 60 % of the board area** that is not a button spawns a **floating joystick** under the thumb (a ring and a knob). Dragging the knob past a **dead zone of 12 logical px** selects the dominant direction (ties → horizontal).
- While the knob stays outside the dead zone, Pip moves one tile per beat in the selected direction; changing direction takes effect on the next beat (corners feel immediate).
- Lifting the thumb, or returning inside the dead zone, stops the clock after the current beat finishes animating — **time freezes**.

### 2.3 Bumps
- Before each beat, the controller asks the rules whether the chosen move is blocked for Pip (wall, closed door, off-grid) **using the same door state `Rules.step` uses**.
- A blocked move does **not** step the game: no beat passes, no battery is used. Pip plays a short bump (a 4 px nudge toward the wall and back, 120 ms), a "tick" sound and a light haptic. Holding into the wall keeps bumping at most once per beat length.
- This is behaviour-preserving: under the existing rules a blocked move was identical to a wait; the player now waits deliberately with ⏳ (2.4). Stored solutions that contain blocked moves still replay identically through `Rules.step`.

### 2.4 Waiting — the ⏳ button
- Right-thumb button. While held, the clock fires `Move.wait` beats; Pip stays put, everything else moves. Releasing freezes time.

### 2.5 Rewinding time — the ⟲ button
- While held, the world plays **backwards** one beat per (beat length ÷ 2) — twice as fast as forward — with interpolation, restoring Pip, echoes, doors and battery. It stops at the start of the current run (it never crosses into a previous run) or when released.
- Replaces both the old Undo and the old swipe-era Undo button.

### 2.6 New echo and Restart
- The button formerly "End run" / "Rewind · N left" becomes **"New echo · N left"** (icon: a person with a trailing copy, e.g. `Icons.people_alt_outlined`), same rule and action as today (`canEndRun`, `endRun`). On the last run it reads **"Give up"** (`Icons.flag`).
- **Restart** stays (restarts the whole level).
- The first-two-times banner text becomes: `Echo created. It will repeat every move you just made.` (unchanged).

### 2.7 Computer (web) controls
- Arrow keys / WASD: move while held (same beat clock). Space: wait while held. Z or Backspace: rewind while held. E: New echo. R: Restart.

### 2.8 Frozen time
- When no input is held the world is frozen mid-pose. A soft blue tint (≈8 % overlay) fades in over 250 ms and the music is low-pass filtered (or, where filtering is unavailable, ducked to 40 % volume). Any input fades both back over 150 ms.

## 3. Look and feel

- **Pip in motion:** leans into travel (≤ 8°), stretches 8 % along travel when starting, squashes 10 % on stop/turn, eye looks toward travel; a short light trail (last ~0.4 tile of path, fading). Idle: gentle bob (2 px, 1.6 s) and the existing blink.
- **Echoes:** same glide, translucent with a faint flicker, a trail in their colour; a shimmer when they first appear at a run's start.
- **World reactions:** plates ripple when pressed; doors slide (150 ms) instead of popping; the exit pulses and floods the screen with light on a win; bumps jolt (2.3).
- **Haptics** (if the device supports it, toggle in Settings): light on bump, medium on plate press, success on win.
- **Rewind effect:** a light scanline/"VHS" shimmer overlay and a rising sound while ⟲ is held; the battery refills visibly.
- **Battery:** moves from the HUD to a small ring above Pip that drains per beat; under 20 % it flashes red and the frozen-time hum rises. The HUD keeps the run Pips (story round) and the exact "Battery, N moves left" semantics label.
- **Performance:** static layers (walls, floor, grid) are recorded once into a `Picture` and redrawn as an image; animated parts repaint only while time flows or an effect runs. **Reduce effects** setting and the OS "reduce motion" flag disable trails, shimmer, tilt/squash and tint (motion stays).

## 4. Levels, hints, tutorial, settings

- **Rules, solver, levels unchanged.** `packages/echo_core`, `tools/echo_solver`, level grids, best scores and solutions are untouched.
- **Hints:** a hint shows a glowing path for the next **4 beats** of the stored solution from the current state (when the state matches the solution, as today); waits appear as a ⏳ marker on Pip's tile; blocked moves in the stored solution are displayed as waits.
- **Tutorial tips** (CI tip rule expands from 1-01..1-03 to 1-01..1-04):
  - 1-01: `Drag anywhere to move Pip.` — plus a looping thumb-drag hint animation until Pip first moves.
  - 1-02: `Plates open doors, but only while something stands on them.` (unchanged)
  - 1-03: `Tap New echo. Pip starts over, and your echo repeats every move.` — New echo pulses until first used (existing pulse behaviour).
  - 1-04: `Hold ⏳ to let time pass while Pip stays still.`
- **Settings additions:** Movement speed (Slow / Normal / Fast, default Normal), Reduce effects (off), Vibration (on). Saved like other settings.
- **Unchanged:** story, cards, city map, Home, ads, progress, scoring.

## 5. Architecture

- `GameClock` (new, `app/lib/game/game_clock.dart`): owns the held intent (`move(dir)`, `wait`, `rewind`, or none) and fires beats on a timer at the speed setting; exposes `beatProgress` (0–1) for interpolation; stops cleanly when intent clears. Pure Dart, injectable time source for tests.
- `GameController` gains `isBlocked(Move)` (via the rules' own blocking logic, exposed from `echo_core` only if needed without changing behaviour) and `stepBack()` for rewind (the existing undo stack, unchanged semantics).
- Input layer replaced: `FloatingJoystick` widget (touch), keyboard handler (web), `HoldButton` widgets for ⏳ and ⟲. The old swipe input is removed.
- `EchoBoard` renders interpolated positions from `beatProgress`, with the static layer cached as a picture.
- Audio: frozen-time filter/duck and rewind sound added to `AudioService` (new methods; silent service in tests). Sounds generated by the existing script.

## 6. Testing

- `GameClock` unit tests with a fake time source: holding a move fires one beat per beat length at each speed; release stops after the current beat; direction change applies next beat; wait and rewind fire at their rates; rewind stops at run start.
- Bump tests: holding into a wall or closed door never advances `tick`; holding into a door that opens via a ghost still bumps until the player waits; stored solutions with blocked moves replay to the same score.
- Joystick tests: dead zone, dominant-axis choice, ties → horizontal, spawn only in the lower 60 % and not on buttons.
- Keyboard tests: each key maps to the right intent; key up clears it.
- Widget tests: New echo / Give up labels; tip text for 1-01..1-04; hint path length 4 with ⏳ markers; settings persist and default correctly; reduce-effects disables trails.
- CI: tip rule updated to 1-01..1-04; solver gate and level tests unchanged and passing; integration test plays 1-01 via the joystick.
- Testing rule unchanged: never `pumpAndSettle` with a Flame `GameWidget` on screen.

## 7. Out of scope (later rounds)

Sparks and stars rework (2), traps and Shades and Chapter 4 (3), abilities (4), bosses (5), full art/sound pass (6).

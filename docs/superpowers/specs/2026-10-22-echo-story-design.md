# Echo: Story & World (Round 1 of 3) — Design

**Status:** approved in conversation 2026-10-22; written spec awaiting review.
**Parent spec:** `2026-10-15-echo-game-design.md` (still binding for rules, levels, ads, sound).
**Rounds:** 1. Story & world (this spec) → 2. Looks & feel → 3. Reasons to return. Each round gets its own spec, plan and review.

## 1. Goal

Make Echo more creative and attractive by giving it a world and a hero whose story *explains the rules* — without slowing down play. The story must stay light: short, skippable cards, almost no words, no cutscenes.

Success:
- A new player understands "battery = 25 moves" and "echo = your past run" from the story, not only from tips.
- Progress feels visible and rewarding: the city lights up as levels are solved.
- No puzzle, level, scoring, ad or sound behaviour changes.

## 2. World

- **Hero: Pip**, a small spark-bot that wakes up in **Lumen City**, a neon city that has gone dark.
- **Rules as story:** Pip's charge lasts 25 moves. When it runs out (or the player taps End run), Pip rewinds and the old run stays behind as an **echo** that keeps replaying.
- **Chapters are districts:**

| Chapter | District | Levels | Feel |
|---|---|---|---|
| 1 | The Outskirts | 1-01 – 1-10 | Pip wakes up and learns to echo |
| 2 | The Market | 2-01 – 2-10 | Crowded streets; several echoes at once |
| 3 | The Core | 3-01 – 3-10 | The power plant; restoring it lights the city |

## 3. Text (final wording)

**Chapter 1 — The Outskirts**
1. Lumen City went dark one night.
2. In a scrapyard on the edge of town, one small spark wakes up. Its name is Pip.
3. Pip's charge lasts 25 moves. When it runs out, Pip rewinds, and its old run stays behind as an echo.

**Chapter 2 — The Market**
1. The Market used to glow all night.
2. Its doors need many hands. Luckily, Pip has echoes.
3. Every echo keeps working, exactly as you taught it.

**Chapter 3 — The Core**
1. The Core powers the whole city.
2. Its locks open only to perfect timing.
3. Four echoes, one Pip, one chance to bring the light back.

**Ending**
1. The Core hums. One by one, the windows wake.
2. Lumen City glows again, lit by a small spark and everything it left behind.
3. Thanks for playing.

**Tips** (only 1-01 to 1-03, as before; replaces the current `tip` values):
- 1-01: "Swipe to move Pip. Find the way out."
- 1-02: "Plates open doors, but only while something stands on them."
- 1-03: "Tap End run. Pip rewinds, and your echo replays every move."

All card text lives in one asset file, `app/assets/story/story.json` (chapters keyed `"1"`–`"3"` with `title` and `lines`, plus `ending.lines`), so it can be edited or translated later without code changes.

## 4. Screens

### 4.1 Home
- Background: the Lumen City skyline drawn in code, showing current progress (lit buildings = solved levels, same rule as the map).
- Pip drawn in the foreground with an idle blink.
- **Play** opens the first unsolved, unlocked level (or the map if all are solved).

### 4.2 City map (replaces the Level Select grid)
- One vertically scrolling screen with three district panels in chapter order: title, then a skyline of 10 buildings, one per level, left to right.
- Building states, from existing progress data:
  - **Locked:** dark silhouette, not tappable.
  - **Unlocked, unsolved:** faint neon outline, tappable.
  - **Solved:** lit, with 1–3 glowing windows matching the level's stars.
- Tapping a building opens that level (same navigation as today's tiles).
- Tapping a district title replays that chapter's card.
- Each building shows its level number for accessibility and tests (semantics label: "Level N, <locked|open|solved, k stars>").

### 4.3 Chapter card
- Full-screen card: district name, the three lines appearing one at a time (tap to advance), a simple scene drawn in code (skyline silhouette + Pip).
- **Skip** button always visible; tapping past the last line or Skip continues to the level.
- Shown automatically the first time the player opens any level of a chapter; then marked seen.

### 4.4 Ending card
- Same card component with the ending lines and a fully lit skyline.
- Shown after the first win on 3-10, after the Level Complete screen's continue action, before returning to the map. Marked seen; replayable from the Core district title.

### 4.5 In game (minimal; full polish is Round 2)
- The player is drawn as Pip: a round bot with one eye, in the current player colour.
- Echoes are drawn as translucent Pips in their existing neon colours (cyan, magenta, amber, …).
- The tick counter is replaced by a **battery bar** that drains over 25 moves (full at tick 0, empty at 25); the exact tick number stays available to screen readers.

## 5. Data

- `ProgressRepository` gains: `seenChapterIntro(int chapter)` / `markChapterIntroSeen(int chapter)` and `endingSeen` / `markEndingSeen()`, saved in `shared_preferences` like existing progress. Defaults: not seen.
- `StoryRepository` loads `story.json` from the asset bundle (same pattern as `LevelRepository`); missing or malformed story data must not break play — the card is skipped and the level opens.
- No new packages.

## 6. Out of scope

- Animation, particles, haptics, transitions, art polish (Round 2).
- Daily puzzle, achievements, skins, streaks (Round 3).
- Voice-over, localisation into other languages (the text file only makes it possible later).
- Any change to levels, rules, solver, scoring, ads or sound.

## 7. Testing

- Unit: `StoryRepository` parses `story.json`; malformed data yields "no story" rather than throwing.
- Unit: `ProgressRepository` seen-flags persist and default to false.
- Widget:
  - First open of a chapter's level shows its card once; the second open goes straight to the level.
  - Skip and tap-through both reach the level.
  - District title tap replays the card.
  - Ending card appears after the first win on 3-10 only.
  - Map building states (locked / open / solved with k windows) match progress.
  - Home Play opens the first unsolved unlocked level.
- Existing tests keep passing; the CI tip rule (tips only on 1-01–1-03) and solver gate are unchanged.
- Testing rule from the parent plan still applies: no `pumpAndSettle` with a Flame `GameWidget` on screen.

# Echo Story & World (Round 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Echo its hero (Pip), its world (Lumen City), chapter and ending story cards, a city-map level select and a battery bar. Also stop the per-swipe sound lag on iPhone web.

**Architecture:**
- Story text lives in an asset (`assets/story/story.json`), loaded by a `StoryRepository` that follows the existing `LevelRepository` pattern.
- "Seen" flags extend `ProgressRepository`.
- Shared drawing code (Pip and skyline) lives in `lib/art/` as plain `Canvas` functions. The board, the map, the home screen and the cards all use it.
- All navigation into a level goes through one helper, `openLevel`, so chapter cards can never be bypassed.

**Tech Stack:** Flutter 3.47.7 / Dart 3.13.5, Flame 1.38, flame_audio 2.12.2, shared_preferences.

**Spec:** `docs/superpowers/specs/2026-10-22-echo-story-design.md` (parent spec: `docs/superpowers/specs/2026-10-15-echo-game-design.md`)

## Global Constraints

- **No new packages.** All art is drawn in code; no image assets.
- **Story text is exactly the spec's §3 wording.** It lives only in `app/assets/story/story.json`, except the three tips, which live in their level JSONs.
- **Tips:** only levels 1-01 to 1-03 have them. The CI rule enforcing this is unchanged.
- **No changes** to `packages/echo_core`, `tools/echo_solver`, level grids/solutions/scores, ads, or the scoring rules.
- **Testing rule:** never use `pumpAndSettle` with a Flame `GameWidget` on screen. Build each widget test's `LevelRepository` and `StoryRepository` from a fresh `PlatformAssetBundle()`, and open repositories inside `tester.runAsync`.
- **Commits:** every commit message ends with:
  `Co-Authored-By: Claude <model name> <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01KmdnqmEPh6FUY7ByRnrW34`
- **Branch:** `feat/story`, created from `feat/levels-and-sound` HEAD.

## Review Focus

1. **Entering a chapter by any route shows its card first.** Routes include: the map, Home Play, Level Complete "Next", and Skip on the last level of a chapter. A card that is bypassed is a broken first impression (Task 3).
2. **Missing or broken `story.json` still lets the level open.** The card is silently skipped; the app never shows a red error screen (Task 2, Task 3).
3. **A skipped level is not left dark.** Skipping records 0 stars, and its building must still show as solved (lit) with 0 windows. Otherwise the map tells players they never passed it (Task 4).
4. **Narrow phones work.** At 320 px width the map's building tap targets stay at least 44 px wide, and the card text wraps without overflow (Task 4, Task 3).
5. **The ending card plays once.** It appears only after the first win on 3-10, never again on replays. It stays replayable from the Core title (Task 3).

---

### Task 1: Pooled move sound (iPhone web lag)

**Files:**
- Modify: `app/lib/audio/flame_audio_service.dart`
- Test: `app/test/audio_wiring_test.dart` (only if the seam below needs it; existing tests must keep passing)

**Interfaces:**
- Consumes: the existing `AudioService.playSfx(Sfx)`.
- Produces: nothing new. The public API is unchanged.

**Why:** `FlameAudio.play` creates a new `AudioPlayer` on every call. On Safari this means a new audio element for every swipe, which stalls each move.

- [ ] **Step 1: Pool the move sound.** In `FlameAudioService`, create an `AudioPool` for `move.wav` lazily, the first time it is needed, with `FlameAudio.createPool('move.wav', maxPlayers: 4)`. Reuse it for every `Sfx.move` call via `pool.start()`. The other sounds stay on `FlameAudio.play`.
- [ ] **Step 2: Remove the per-call wait.** After the first successful `_ensureLoaded()`, `playSfx` must no longer await the shared future. Keep a `bool _loaded` that is set when the load succeeds. Failures are still swallowed, as today.
- [ ] **Step 3: Verify.**
  - From `app/`, run `flutter test`, `flutter analyze` and `dart format --set-exit-if-changed lib test`. Expected: all pass.
  - Run `flutter build web --release`. Expected: `✓ Built build/web`.
- [ ] **Step 4: Commit** with the message `perf(audio): pool the move sound for smooth swipes on web`.

---

### Task 2: Story data and seen flags

**Files:**
- Create: `app/assets/story/story.json`
- Create: `app/lib/data/story_repository.dart`
- Modify:
  - `app/pubspec.yaml` (add the asset dir `assets/story/`)
  - `app/lib/data/progress_repository.dart`
  - `app/lib/app_services.dart` (add `story`)
  - `app/lib/main.dart`
  - `app/test/support/*` (every `AppServices` construction site)
  - `app/assets/levels/1-01.json`, `1-02.json`, `1-03.json` (the `tip` field only)
- Test:
  - `app/test/story_repository_test.dart`
  - `app/test/progress_repository_test.dart` (extend the existing file)

**Interfaces:**
- Produces:
  - `class StoryChapter { final String title; final List<String> lines; }`
  - `class Story { final Map<int, StoryChapter> chapters; final List<String> ending; }`
  - `class StoryRepository { StoryRepository(AssetBundle bundle); Future<Story?> load(); }`
    - `load` returns `null` if the asset is missing or malformed, and never throws.
    - The result is cached after the first successful load.
  - Additions to `ProgressRepository`:
    - `bool seenChapterIntro(int chapter)`
    - `Future<void> markChapterIntroSeen(int chapter)`
    - `bool get endingSeen`
    - `Future<void> markEndingSeen()`
  - Both flags are saved in the same prefs JSON under new keys and default to false. Old saved data without the keys must still load.
  - `AppServices` gains a required `StoryRepository story`.

- [ ] **Step 1: Write the failing tests.**
  - `story_repository_test.dart`:
    - Loads the bundled `story.json` and asserts:
      - `chapters[1].title == 'The Outskirts'`
      - `chapters[2].title == 'The Market'`
      - `chapters[3].title == 'The Core'`
      - each chapter has 3 lines
      - `chapters[1].lines[1] == 'In a scrapyard on the edge of town, one small spark wakes up. Its name is Pip.'`
      - `ending.last == 'Thanks for playing.'`
    - A fake bundle returning `'{"chapters": 5}'` gives `null`.
    - A bundle that throws gives `null`.
  - `progress_repository_test.dart`:
    - Fresh prefs: `seenChapterIntro(2)` is false and `endingSeen` is false.
    - After `markChapterIntroSeen(2)` and `markEndingSeen()`, reopening the repository gives true for both, while `seenChapterIntro(1)` stays false.
    - Prefs saved by the old format (stars only) still open, with both flags false.
  - Extend the existing tip assertions (wherever 1-01..1-03 tips are asserted) to the new text.
- [ ] **Step 2: Run** `flutter test test/story_repository_test.dart test/progress_repository_test.dart`. Expected: FAIL, because `StoryRepository` and the flag methods don't exist yet.
- [ ] **Step 3: Implement.**
  - Write `story.json` with the spec's §3 text verbatim, using this shape: `{"chapters": {"1": {"title": "...", "lines": [...]}, ...}, "ending": {"lines": [...]}}`.
  - Add the repository and the flags, and wire `story` into `AppServices`, `main.dart` and the test support.
  - Replace the three `tip` values with the spec's §3 tip text.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` and the format check from `app/`, then `dart run bin/echo_solver.dart ../../app/assets/levels --check` from `tools/echo_solver`. Expected: all pass. Tips are not part of the solution, so the solver check stays OK.
- [ ] **Step 5: Commit** with the message `feat(story): story text, repository and seen flags`.

---

### Task 3: Story cards and the single route into levels

**Files:**
- Create:
  - `app/lib/screens/story_card_screen.dart`
  - `app/lib/screens/open_level.dart`
- Modify:
  - `app/lib/screens/level_select_screen.dart` (`_open`)
  - `app/lib/screens/level_complete_screen.dart` (`_next`, `_levels`)
  - `app/lib/screens/game_screen.dart` (`_onSkip` next-level push)
- Test: `app/test/story_flow_test.dart`

**Interfaces:**
- Consumes: `StoryRepository.load()` and the `ProgressRepository` flags from Task 2.
- Produces:
  - `StoryCardScreen({required String title, required List<String> lines, required VoidCallback onDone, bool litSkyline = false})`
    - Shows one line at a time. Tapping anywhere shows the next line.
    - After the last line, or on the `Skip` button (always visible, `key: Key('story-skip')`), it calls `onDone` exactly once.
    - Draws a skyline scene via Task 4's `paintSkyline`, so it needs Task 4. Until Task 4 lands, use a plain `background` fill, and Task 4 swaps in the scene.
  - `Future<void> openLevel(BuildContext context, AppServices services, String id, {bool replace = false})`
    - If the level's chapter intro is unseen and the story loaded, it pushes (or replaces with) a `StoryCardScreen` for that chapter. Its `onDone` marks the intro seen and replaces the card with `GameScreen(id)`.
    - Otherwise it pushes (or replaces with) `GameScreen` directly.
    - Every existing route into a level goes through this.
  - `Future<void> showChapterCard(BuildContext context, AppServices services, int chapter)`: replay for the map's district titles. Pops back to the caller on done.
  - `Future<void> showEnding(BuildContext context, AppServices services)`: shows the ending lines with `litSkyline: true`, marks the ending seen, and pops on done.
  - Ending trigger: in `LevelComplete`, when `levelId` is the last bundled level and `!endingSeen`, the `Levels` button calls `showEnding` before returning to the map.

- [ ] **Step 1: Write the failing tests** in `story_flow_test.dart`. The card is plain Flutter, so `pump` frames are fine before the `GameWidget` appears; after it appears, use only `pump(Duration)`.
  - **`first open of 1-01 shows the Outskirts card once`:** expect the text `'The Outskirts'`. Tap 3 times; expect a `GameScreen`. Pop, open 1-01 again; expect a `GameScreen` with no `'The Outskirts'`.
  - **`skip goes straight to the level`:** tap `Key('story-skip')`; expect a `GameScreen`, and expect `seenChapterIntro(1)` to be true.
  - **`entering chapter 2 via Level Complete Next shows the Market card`:** all of chapter 1 completed, then Next from 1-10. Expect `'The Market'`.
  - **`skip on 1-10 shows the Market card`:** this goes through `_onSkip`. Use the existing ads test fakes.
  - **`broken story opens the level`:** story bundle returns `'{}'`. Opening 1-01 shows a `GameScreen` with no card.
  - **`ending shows once after first 3-10 win`:**
    - On the Level Complete screen for `3-10` with `endingSeen` false, tapping `Levels` shows `'Thanks for playing.'`.
    - Tap Skip; the map shows and `endingSeen` is true.
    - Repeat the same steps: no ending.
  - **`card text wraps at 320 px`:** set the view to 320×640 and show chapter 1's card. Expect no overflow exception (`tester.takeException()` is null).
- [ ] **Step 2: Run** `flutter test test/story_flow_test.dart`. Expected: FAIL (`StoryCardScreen` is undefined).
- [ ] **Step 3: Implement** `story_card_screen.dart` and `open_level.dart`. Then route `LevelSelectScreen._open`, `LevelCompleteScreen._next` and `GameScreen._onSkip` through `openLevel` (`replace: true` where they used `replace`/`pushReplacement` today), and add the ending hook to `_levels`.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` and the format check. Expected: all pass. Existing navigation and ads tests may need the intro flags pre-marked in their setup. Do that in `test/support`, not by weakening assertions.
- [ ] **Step 5: Commit** with the message `feat(story): chapter and ending cards on every route into a level`.

---

### Task 4: Art primitives and the city map

**Files:**
- Create:
  - `app/lib/art/pip.dart`
  - `app/lib/art/skyline.dart`
  - `app/lib/screens/city_map_screen.dart`
- Delete: `app/lib/screens/level_select_screen.dart`. Move its `_open` behaviour to `openLevel`, which already exists after Task 3.
- Modify:
  - `app/lib/screens/home_screen.dart` (navigate to `CityMapScreen`)
  - `app/lib/screens/level_complete_screen.dart` (`_levels` pops to the map, as it does today)
  - `app/lib/screens/story_card_screen.dart` (draw the scene)
  - tests that reference `LevelSelectScreen`, the lock icon or chapter headings: `test/navigation_test.dart`, `test/ads_flow_test.dart`, `test/level_repository_test.dart`
- Test:
  - `app/test/city_map_test.dart`
  - `app/test/art_test.dart`

**Interfaces:**
- Produces:
  - `void paintPip(Canvas canvas, Offset center, double radius, Color color, {double eyeOpen = 1.0, double opacity = 1.0})`: a round body, one eye. Board, home and cards all use it.
  - `enum BuildingState { locked, open, solved }`
  - `class Building { final BuildingState state; final int stars; }` (`stars` in 0–3, used only when solved)
  - `void paintSkyline(Canvas canvas, Size size, List<Building> buildings, {bool allLit = false})`: draws the buildings left to right with deterministic heights (seeded by index), so the skyline never jumps between frames.
  - `List<Building> buildingsFor(List<String> ids, ProgressRepository progress)`:
    - `completed` means solved, with `stars` from progress. A skipped level is solved with 0 stars.
    - Otherwise `isUnlocked` means open; anything else is locked.
  - `CityMapScreen({required AppServices services})`:
    - Title: `'Lumen City'`.
    - Three district panels in order. Each has a tappable district title (the chapter title from the story, falling back to `chapterOf(id)` when the story is null) that calls `showChapterCard`. The Core title calls `showEnding` instead once `endingSeen` is true and the chapter is complete.
    - Ten building tap targets per panel. Each target is wrapped in `Semantics(label: 'Level N, locked' | 'Level N, open' | 'Level N, solved, k stars', button: true)` and shows its level number.
    - Locked targets are not tappable. Open and solved targets call `openLevel`.
    - Rebuilds on `ProgressRepository` changes, as Level Select does today.

- [ ] **Step 1: Write the failing tests.**
  - **`art_test.dart`:**
    - `buildingsFor` with 1-01 at 3 stars, 1-02 skipped (`recordSkip`), and nothing else gives `[solved(3), solved(0), open, locked, …]`.
    - `paintSkyline` and `paintPip` draw on a `PictureRecorder` canvas without throwing, for 0 and 30 buildings.
  - **`city_map_test.dart`:**
    - A fresh install shows `bySemanticsLabel('Level 1, open')` and `bySemanticsLabel('Level 2, locked')`.
    - After `recordCompletion('1-01', 2)` the map shows `'Level 1, solved, 2 stars'`.
    - Tapping `'Level 2, locked'` does nothing (no `GameScreen`).
    - Tapping the district title `'The Market'` shows the Market card.
    - At a 320×640 view, every building tap target's rendered width is at least 44.
- [ ] **Step 2: Run** the two test files. Expected: FAIL (undefined symbols).
- [ ] **Step 3: Implement.**
  - Write `pip.dart`, `skyline.dart` and `city_map_screen.dart`.
  - Swap Home's push to `CityMapScreen`.
  - Give `StoryCardScreen` its scene: `paintSkyline` with `allLit: litSkyline`, plus `paintPip` in front.
  - Delete `level_select_screen.dart`, and update the old tests to find levels by the new semantics labels. Keep each test's original intent: lock counts, last-level skip, and so on.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` and the format check. Expected: all pass.
- [ ] **Step 5: Commit** with the message `feat(story): Lumen City map replaces the level grid`.

---

### Task 5: Home screen city and Play-continues

**Files:**
- Modify: `app/lib/screens/home_screen.dart`
- Test: `app/test/navigation_test.dart` (add cases)

**Interfaces:**
- Consumes: `paintSkyline`, `buildingsFor`, `paintPip` and `openLevel`.
- Produces:
  - Home shows the skyline across the bottom (via `buildingsFor` on all ids) and Pip blinking. The eye closes for 150 ms every 4 s, using a `Ticker`/`AnimationController`.
  - `Play` opens the first level that is unlocked and not completed, via `openLevel`. If every level is completed, it opens `CityMapScreen`.
  - A second button, `Map`, always opens `CityMapScreen`.
  - `Settings` is unchanged. Music still starts on the Play tap.

- [ ] **Step 1: Write the failing tests.**
  - **`Play on a fresh install opens 1-01`:** this goes through the Outskirts card, which the test pre-marks as seen. Expect `GameScreen` with `levelId == '1-01'`.
  - **`Play continues at the first unsolved level`:** with 1-01 to 1-04 completed, expect `'1-05'`.
  - **`Play with all levels done opens the map`:** expect `CityMapScreen`.
  - **`Map button opens the map`.**
  - The blink uses an `AnimationController`. Tests must not hang: use `pump(Duration)`, never `pumpAndSettle`, because the blink repeats forever.
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement** the Home changes.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` and the format check. Expected: all pass.
- [ ] **Step 5: Commit** with the message `feat(story): home shows Lumen City; Play continues where you left off`.

---

### Task 6: Pip on the board and the battery bar

**Files:**
- Modify:
  - `app/lib/game/echo_board.dart` (player and ghost drawing)
  - `app/lib/screens/game_screen.dart` (replace `Text('Moves ${state.tick}')` around line 251)
- Create: `app/lib/game/battery_bar.dart`
- Test: `app/test/battery_bar_test.dart`, plus additions to `app/test/game_screen_test.dart`

**Interfaces:**
- Consumes: `paintPip`.
- Produces:
  - `EchoBoard` draws the player with `paintPip(..., palette.player)`, and each ghost with `paintPip(..., ghostColor, opacity: 0.55)`. Ghost trails stay as they are.
  - `BatteryBar({required int tick, int max = Rules.maxTicksPerRun})`:
    - A horizontal bar whose fill fraction is `(max - tick) / max`, clamped to 0–1.
    - The fill colour is `palette.platePressed` above 30 % and `palette.doorClosed` at 30 % or below.
    - Wrapped in `Semantics(label: 'Battery, ${max - tick} moves left')`.
  - `GameScreen` shows `BatteryBar(tick: state.tick)` where the moves text was.

- [ ] **Step 1: Write the failing tests.**
  - **`battery_bar_test.dart`:**
    - tick 0 gives the semantics label `'Battery, 25 moves left'` with fill 1.0.
    - tick 25 gives `'Battery, 0 moves left'` with fill 0.0.
    - tick 20 (20 % left) uses the low colour.
  - **`game_screen_test.dart`:**
    - After one fling, `bySemanticsLabel('Battery, 24 moves left')` is found.
    - The text `'Moves 1'` is no longer found.
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement** the battery bar and the board drawing.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` and the format check, plus `flutter test integration_test` if an emulator exists. If none exists, CI covers it. Expected: all pass. Integration tests that read `'Moves N'` must switch to the battery semantics label.
- [ ] **Step 5: Commit** with the message `feat(story): Pip and echoes on the board, battery bar`.

---

### Task 7: Ship the preview

**Files:**
- Modify: `app/web/index.html`: `<title>Echo</title>` and meta description `Echo — help Pip relight Lumen City with echoes of your past runs.`

- [ ] **Step 1: Edit** `index.html` as above. Run `flutter build web --release`. Expected: `✓ Built build/web`.
- [ ] **Step 2: Commit** with the message `chore(web): page title and description`, then push the branch `feat/story` with `git push -u origin feat/story`.
- [ ] **Step 3: Point the Pages workflow at the new branch.** Add `feat/story` to `on.push.branches` in `.github/workflows/pages.yml`, then commit and push.
- [ ] **Step 4: Verify CI.** Using `gh api repos/abkhader/MobileGame/actions/runs?branch=feat/story`, check that every job of `CI` and `Web preview` concludes `success`.
- [ ] **Step 5: Verify the site.** Fetch `https://abkhader.github.io/MobileGame/`. Expected: the title is `Echo`.

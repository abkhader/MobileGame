import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/game_clock.dart';

/// One level's saved result. Stars are kept across plays: one for
/// finishing, one for all three sparks (each remembered once collected in a
/// won play), one for a play in the best number of moves or fewer.
class LevelProgress {
  const LevelProgress({
    this.completed = false,
    this.finished = false,
    this.sparkMask = 0,
    this.movesStar = false,
  });

  /// Won or skipped: the next level is unlocked.
  final bool completed;

  /// Won at least once (a skip does not count).
  final bool finished;

  /// Bit i set: spark i (in `Level.sparks` order) was collected in a won play.
  final int sparkMask;

  /// Won at least once in bestScore moves or fewer.
  final bool movesStar;

  static const allSparks = 0x7;

  bool get allSparksStar => sparkMask == allSparks;

  /// The three goals in display order.
  ({bool finished, bool allSparks, bool moves}) get goals =>
      (finished: finished, allSparks: allSparksStar, moves: movesStar);

  /// 0–3.
  int get stars =>
      (finished ? 1 : 0) + (allSparksStar ? 1 : 0) + (movesStar ? 1 : 0);

  /// How many sparks are saved, 0–3.
  int get sparkCount => _bitCount(sparkMask);
}

int _bitCount(int mask) => (mask & 1) + ((mask >> 1) & 1) + ((mask >> 2) & 1);

/// Reads one saved level entry; anything unexpected falls back to defaults.
/// Old saves stored only `{'stars': n}` (a skip stored 0, a win 1–3, and 3
/// meant score <= best).
LevelProgress _entryFromJson(Map<String, dynamic> entry) {
  final isNew =
      entry.containsKey('completed') ||
      entry.containsKey('finished') ||
      entry.containsKey('sparks') ||
      entry.containsKey('moves');
  if (!isNew) {
    final s = entry['stars'];
    final n = s is int ? s.clamp(0, 3) : 0;
    return LevelProgress(completed: true, finished: n > 0, movesStar: n == 3);
  }
  final sparks = entry['sparks'];
  return LevelProgress(
    completed: true,
    finished: entry['finished'] == true,
    sparkMask: sparks is int && sparks >= 0 && sparks <= LevelProgress.allSparks
        ? sparks
        : 0,
    movesStar: entry['moves'] == true,
  );
}

/// Stars, unlocks and settings, persisted as one JSON string.
/// Notifies listeners after each successful save.
class ProgressRepository extends ChangeNotifier {
  ProgressRepository._(
    this._prefs,
    this._levels,
    this._musicOn,
    this._sfxOn,
    this._seenChapters,
    this._endingSeen,
    this._rewindTipsShown,
    this._moveSpeed,
    this._reduceEffects,
    this._vibration,
  );

  /// Every preview build is published to the same URL, so they share one
  /// localStorage. Saves go under v2 only; an older build writing its own v1
  /// save can then never overwrite this format.
  static const storageKey = 'echo.progress.v2';

  /// Older builds' key. Read only as the migration source when no v2 save
  /// exists; never written.
  static const legacyStorageKey = 'echo.progress.v1';

  final SharedPreferences _prefs;
  // Presence of a key means the level is completed.
  final Map<String, LevelProgress> _levels;
  bool _musicOn;
  bool _sfxOn;
  final Set<int> _seenChapters;
  bool _endingSeen;
  int _rewindTipsShown;
  MoveSpeed _moveSpeed;
  bool _reduceEffects;
  bool _vibration;

  static Future<ProgressRepository> open() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = <String, LevelProgress>{};
    var musicOn = true;
    var sfxOn = true;
    final seenChapters = <int>{};
    var endingSeen = false;
    var rewindTipsShown = 0;
    var moveSpeed = MoveSpeed.normal;
    var reduceEffects = false;
    var vibration = true;
    var migrating = false;
    try {
      var raw = prefs.getString(storageKey);
      if (raw == null) {
        raw = prefs.getString(legacyStorageKey);
        migrating = raw != null;
      }
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final levels = decoded['levels'];
          if (levels is Map<String, dynamic>) {
            levels.forEach((id, entry) {
              if (entry is Map<String, dynamic>) {
                saved[id] = _entryFromJson(entry);
              }
            });
          }
          if (decoded['musicOn'] is bool) musicOn = decoded['musicOn'] as bool;
          if (decoded['sfxOn'] is bool) sfxOn = decoded['sfxOn'] as bool;
          final seen = decoded['seenChapters'];
          if (seen is List<dynamic>) seenChapters.addAll(seen.whereType<int>());
          if (decoded['endingSeen'] is bool) {
            endingSeen = decoded['endingSeen'] as bool;
          }
          final tips = decoded['rewindTipsShown'];
          if (tips is int && tips > 0) rewindTipsShown = tips;
          final speed = decoded['moveSpeed'];
          if (speed is String) {
            moveSpeed = MoveSpeed.values.firstWhere(
              (m) => m.name == speed,
              orElse: () => MoveSpeed.normal,
            );
          }
          if (decoded['reduceEffects'] is bool) {
            reduceEffects = decoded['reduceEffects'] as bool;
          }
          if (decoded['vibration'] is bool) {
            vibration = decoded['vibration'] as bool;
          }
        }
      }
    } catch (_) {
      saved.clear();
      musicOn = true;
      sfxOn = true;
      seenChapters.clear();
      endingSeen = false;
      rewindTipsShown = 0;
      moveSpeed = MoveSpeed.normal;
      reduceEffects = false;
      vibration = true;
    }
    final repo = ProgressRepository._(
      prefs,
      saved,
      musicOn,
      sfxOn,
      seenChapters,
      endingSeen,
      rewindTipsShown,
      moveSpeed,
      reduceEffects,
      vibration,
    );
    // Write the migrated data to v2 at once so it never depends on v1 again.
    if (migrating) await repo._save();
    return repo;
  }

  bool get musicOn => _musicOn;
  bool get sfxOn => _sfxOn;
  bool get endingSeen => _endingSeen;
  MoveSpeed get moveSpeed => _moveSpeed;

  /// No trails, shimmer, tilt/squash or tint (motion stays).
  bool get reduceEffects => _reduceEffects;

  /// Haptic feedback on push, plate and win.
  bool get vibration => _vibration;

  /// How many times the first-rewind tip has been shown (it stops at 2).
  int get rewindTipsShown => _rewindTipsShown;

  bool seenChapterIntro(int chapter) => _seenChapters.contains(chapter);

  LevelProgress progressOf(String id) => _levels[id] ?? const LevelProgress();

  /// Sparks saved across all levels.
  int get totalSparks {
    var n = 0;
    for (final p in _levels.values) {
      n += p.sparkCount;
    }
    return n;
  }

  bool isUnlocked(String id, List<String> orderedIds) {
    final i = orderedIds.indexOf(id);
    if (i < 0) return false;
    if (i == 0) return true;
    return _levels.containsKey(orderedIds[i - 1]);
  }

  /// A won play: finished, its sparks added to the saved ones (bit i is
  /// spark i in `Level.sparks` order), and the moves star when [score] is at
  /// most [best]. Goals once earned are never lost.
  Future<void> recordWin(
    String id, {
    required int score,
    required int best,
    required int sparkMask,
  }) {
    final prev = progressOf(id);
    _levels[id] = LevelProgress(
      completed: true,
      finished: true,
      sparkMask: prev.sparkMask | (sparkMask & LevelProgress.allSparks),
      movesStar: prev.movesStar || score <= best,
    );
    return _save();
  }

  /// Unlocks the next level without earning any star.
  Future<void> recordSkip(String id) {
    _levels.putIfAbsent(id, () => const LevelProgress(completed: true));
    return _save();
  }

  Future<void> setMusicOn(bool value) {
    _musicOn = value;
    return _save();
  }

  Future<void> setSfxOn(bool value) {
    _sfxOn = value;
    return _save();
  }

  Future<void> setMoveSpeed(MoveSpeed value) {
    _moveSpeed = value;
    return _save();
  }

  Future<void> setReduceEffects(bool value) {
    _reduceEffects = value;
    return _save();
  }

  Future<void> setVibration(bool value) {
    _vibration = value;
    return _save();
  }

  Future<void> markChapterIntroSeen(int chapter) {
    _seenChapters.add(chapter);
    return _save();
  }

  Future<void> markEndingSeen() {
    _endingSeen = true;
    return _save();
  }

  Future<void> markRewindTipShown() {
    _rewindTipsShown++;
    return _save();
  }

  Future<void> _save() async {
    final json = jsonEncode({
      'levels': {
        for (final e in _levels.entries)
          e.key: {
            'completed': true,
            'finished': e.value.finished,
            'sparks': e.value.sparkMask,
            'moves': e.value.movesStar,
          },
      },
      'musicOn': _musicOn,
      'sfxOn': _sfxOn,
      'seenChapters': _seenChapters.toList()..sort(),
      'endingSeen': _endingSeen,
      'rewindTipsShown': _rewindTipsShown,
      'moveSpeed': _moveSpeed.name,
      'reduceEffects': _reduceEffects,
      'vibration': _vibration,
    });
    await _prefs.setString(storageKey, json);
    notifyListeners();
  }
}

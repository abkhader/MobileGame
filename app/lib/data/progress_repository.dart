import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LevelProgress {
  const LevelProgress({this.completed = false, this.stars = 0});

  final bool completed;
  final int stars;
}

/// Stars, unlocks and settings, persisted as one JSON string.
/// Notifies listeners after each successful save.
class ProgressRepository extends ChangeNotifier {
  ProgressRepository._(
    this._prefs,
    this._stars,
    this._musicOn,
    this._sfxOn,
    this._seenChapters,
    this._endingSeen,
    this._rewindTipsShown,
  );

  static const storageKey = 'echo.progress.v1';

  final SharedPreferences _prefs;
  // Presence of a key means the level is completed.
  final Map<String, int> _stars;
  bool _musicOn;
  bool _sfxOn;
  final Set<int> _seenChapters;
  bool _endingSeen;
  int _rewindTipsShown;

  static Future<ProgressRepository> open() async {
    final prefs = await SharedPreferences.getInstance();
    final stars = <String, int>{};
    var musicOn = true;
    var sfxOn = true;
    final seenChapters = <int>{};
    var endingSeen = false;
    var rewindTipsShown = 0;
    try {
      final raw = prefs.getString(storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final levels = decoded['levels'];
          if (levels is Map<String, dynamic>) {
            levels.forEach((id, entry) {
              if (entry is Map<String, dynamic>) {
                final s = entry['stars'];
                stars[id] = s is int ? s.clamp(0, 3) : 0;
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
        }
      }
    } catch (_) {
      stars.clear();
      musicOn = true;
      sfxOn = true;
      seenChapters.clear();
      endingSeen = false;
      rewindTipsShown = 0;
    }
    return ProgressRepository._(
      prefs,
      stars,
      musicOn,
      sfxOn,
      seenChapters,
      endingSeen,
      rewindTipsShown,
    );
  }

  bool get musicOn => _musicOn;
  bool get sfxOn => _sfxOn;
  bool get endingSeen => _endingSeen;

  /// How many times the first-rewind tip has been shown (it stops at 2).
  int get rewindTipsShown => _rewindTipsShown;

  bool seenChapterIntro(int chapter) => _seenChapters.contains(chapter);

  LevelProgress progressOf(String id) {
    final s = _stars[id];
    return s == null
        ? const LevelProgress()
        : LevelProgress(completed: true, stars: s);
  }

  bool isUnlocked(String id, List<String> orderedIds) {
    final i = orderedIds.indexOf(id);
    if (i < 0) return false;
    if (i == 0) return true;
    return _stars.containsKey(orderedIds[i - 1]);
  }

  Future<void> recordCompletion(String id, int stars) {
    final clamped = stars.clamp(0, 3);
    final prev = _stars[id] ?? 0;
    _stars[id] = clamped > prev ? clamped : prev;
    return _save();
  }

  Future<void> recordSkip(String id) {
    _stars.putIfAbsent(id, () => 0);
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
        for (final e in _stars.entries) e.key: {'stars': e.value},
      },
      'musicOn': _musicOn,
      'sfxOn': _sfxOn,
      'seenChapters': _seenChapters.toList()..sort(),
      'endingSeen': _endingSeen,
      'rewindTipsShown': _rewindTipsShown,
    });
    await _prefs.setString(storageKey, json);
    notifyListeners();
  }
}

import 'dart:convert';

import 'package:flutter/services.dart';

class StoryChapter {
  const StoryChapter({required this.title, required this.lines});

  final String title;
  final List<String> lines;
}

class Story {
  const Story({required this.chapters, required this.ending});

  final Map<int, StoryChapter> chapters;
  final List<String> ending;
}

class StoryRepository {
  StoryRepository(this._bundle);

  static const path = 'assets/story/story.json';

  final AssetBundle _bundle;
  Story? _cached;

  /// The bundled story, or null if the asset is missing or malformed.
  /// Never throws; a successful load is cached.
  Future<Story?> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final decoded = jsonDecode(await _bundle.loadString(path));
      return _cached = _parse(decoded);
    } catch (_) {
      return null;
    }
  }

  static Story _parse(Object? decoded) {
    final root = decoded as Map<String, dynamic>;
    final chapters = <int, StoryChapter>{};
    (root['chapters'] as Map<String, dynamic>).forEach((key, value) {
      final entry = value as Map<String, dynamic>;
      chapters[int.parse(key)] = StoryChapter(
        title: entry['title'] as String,
        lines: _lines(entry['lines']),
      );
    });
    final ending = (root['ending'] as Map<String, dynamic>)['lines'];
    return Story(chapters: chapters, ending: _lines(ending));
  }

  static List<String> _lines(Object? value) => [
    for (final l in value as List<dynamic>) l as String,
  ];
}

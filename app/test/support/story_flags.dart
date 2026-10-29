import 'dart:convert';
import 'dart:io';

import 'package:echo_app/data/progress_repository.dart';

/// Mock prefs with every chapter intro already seen, for tests that open
/// levels and are not about the story cards. The ending stays unseen.
///
/// The chapters come from the bundled story file, so a new chapter is
/// covered without editing this helper.
Map<String, Object> introsSeenPrefs() => {
  ProgressRepository.storageKey: jsonEncode({
    'seenChapters': _bundledChapters(),
  }),
};

List<int> _bundledChapters() {
  final story =
      jsonDecode(File('assets/story/story.json').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final key in (story['chapters'] as Map<String, dynamic>).keys)
      int.parse(key),
  ]..sort();
}

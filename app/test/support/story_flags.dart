import 'dart:convert';

import 'package:echo_app/data/progress_repository.dart';

/// Mock prefs with every chapter intro already seen, for tests that open
/// levels and are not about the story cards. The ending stays unseen.
Map<String, Object> introsSeenPrefs() => {
  ProgressRepository.storageKey: jsonEncode({
    'seenChapters': [1, 2, 3],
  }),
};

import 'dart:convert';

import 'package:echo_app/data/progress_repository.dart';
import 'package:echo_app/data/story_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock prefs with every chapter intro already seen, for tests that open
/// levels and are not about the story cards. The ending stays unseen.
///
/// The chapters come from the bundled story file, read through a fresh
/// asset bundle (inside [WidgetTester.runAsync]), so a new chapter is
/// covered without editing this helper and it works on a device too, where
/// the project's files are not on disk.
Future<Map<String, Object>> introsSeenPrefs(WidgetTester t) async {
  final story = await t.runAsync(StoryRepository(PlatformAssetBundle()).load);
  if (story == null) throw StateError('The bundled story did not load.');
  return {
    ProgressRepository.storageKey: jsonEncode({
      'seenChapters': story.chapters.keys.toList()..sort(),
    }),
  };
}

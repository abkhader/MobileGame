import 'dart:convert';

import 'package:echo_app/data/story_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _StringBundle extends AssetBundle {
  _StringBundle(this.files);
  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final text = files[key];
    if (text == null) throw FlutterError('Unable to load asset: $key');
    return text;
  }
}

class _ThrowingBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) => throw StateError('boom');

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      throw StateError('boom');
}

class _CountingBundle extends _ThrowingBundle {
  int loads = 0;

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    loads++;
    return super.loadString(key, cache: cache);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the bundled story', () async {
    final story = await StoryRepository(rootBundle).load();
    expect(story, isNotNull);
    expect(story!.chapters[1]!.title, 'The Outskirts');
    expect(story.chapters[2]!.title, 'The Market');
    expect(story.chapters[3]!.title, 'The Core');
    for (final c in [1, 2, 3]) {
      expect(story.chapters[c]!.lines, hasLength(3));
    }
    expect(
      story.chapters[1]!.lines[1],
      'In a scrapyard on the edge of town, one small spark wakes up. '
      'Its name is Pip.',
    );
    expect(story.ending.last, 'Thanks for playing.');
  });

  test('a failed load is cached and not retried', () async {
    final bundle = _CountingBundle();
    final repo = StoryRepository(bundle);
    expect(await repo.load(), isNull);
    expect(await repo.load(), isNull);
    expect(bundle.loads, 1);
  });

  test('malformed story gives null', () async {
    final bundle = _StringBundle({StoryRepository.path: '{"chapters": 5}'});
    expect(await StoryRepository(bundle).load(), isNull);
  });

  test('missing story gives null', () async {
    expect(await StoryRepository(_StringBundle({})).load(), isNull);
  });

  test('throwing bundle gives null', () async {
    expect(await StoryRepository(_ThrowingBundle()).load(), isNull);
  });

  test('successful load is cached', () async {
    final repo = StoryRepository(rootBundle);
    final a = await repo.load();
    expect(await repo.load(), same(a));
  });
}

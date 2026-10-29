import 'dart:convert';

import 'package:echo_app/data/level_repository.dart';
import 'package:echo_core/echo_core.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('levelIds lists bundled levels in order', () async {
    final ids = await LevelRepository(rootBundle).levelIds();
    expect(ids.take(3), ['1-01', '1-02', '1-03']);
    expect(ids, [...ids]..sort());
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[1-4]-(0[1-9]|10)$')));
    }
  });

  test('load parses a level', () async {
    final l = await LevelRepository(rootBundle).load('1-03');
    expect((l.name, l.runLimit, l.bestScore), ('Echo', 2, 5));
  });

  test('missing and invalid levels throw LevelFormatException', () async {
    expect(
      LevelRepository(rootBundle).load('9-99'),
      throwsA(isA<LevelFormatException>()),
    );
    final bad = _StringBundle({'assets/levels/x.json': '{not json'});
    expect(
      LevelRepository(bad).load('x'),
      throwsA(isA<LevelFormatException>()),
    );
  });

  test('levelNumber and chapterOf', () {
    expect(levelNumber(['1-01', '1-02', '2-01'], '2-01'), 3);
    expect(chapterOf('2-07'), 'Chapter 2');
  });
}

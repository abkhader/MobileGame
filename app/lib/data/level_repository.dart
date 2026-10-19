import 'package:echo_core/echo_core.dart';
import 'package:flutter/services.dart';

class LevelRepository {
  LevelRepository(this._bundle);

  static const dir = 'assets/levels/';

  final AssetBundle _bundle;

  Future<List<String>> levelIds() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
    final ids = [
      for (final key in manifest.listAssets())
        if (key.startsWith(dir) && key.endsWith('.json'))
          key.substring(dir.length, key.length - '.json'.length),
    ]..sort();
    return ids;
  }

  Future<Level> load(String id) async {
    final String text;
    try {
      text = await _bundle.loadString('$dir$id.json');
    } catch (_) {
      throw LevelFormatException('missing level $id');
    }
    return LevelLoader.parse(text);
  }
}

/// 1-based position of [id] in [ids].
int levelNumber(List<String> ids, String id) => ids.indexOf(id) + 1;

String chapterOf(String id) => 'Chapter ${id.split('-').first}';

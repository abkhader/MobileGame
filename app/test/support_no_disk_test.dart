import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The integration tests run on a device, where the project's files are
  // not on disk: what they share with the widget tests must load assets
  // through the bundle, never through dart:io.
  test('helpers shared with integration tests never read from disk', () {
    final files = [
      ...Directory('integration_test').listSync(recursive: true),
      ...Directory('test/support').listSync(recursive: true),
    ].whereType<File>().where((f) => f.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    for (final f in files) {
      expect(
        f.readAsStringSync(),
        isNot(contains("import 'dart:io'")),
        reason: f.path,
      );
    }
  });
}

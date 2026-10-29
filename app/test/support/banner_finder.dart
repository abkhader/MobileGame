import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether the top banner showing [text] lets touches through: the widget
/// directly above the banner's fade is an [IgnorePointer] that ignores.
///
/// Checks that exact parent, not any IgnorePointer somewhere above the text
/// (the screen has others), so the test cannot pass by accident.
bool bannerIgnoresPointer(WidgetTester t, String text) {
  final fade = find.ancestor(
    of: find.text(text),
    matching: find.byType(AnimatedOpacity),
  );
  final element = t.element(fade.first);
  Widget? parent;
  element.visitAncestorElements((e) {
    parent = e.widget;
    return false;
  });
  final p = parent;
  return p is IgnorePointer && p.ignoring;
}

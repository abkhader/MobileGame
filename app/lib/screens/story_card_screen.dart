import 'package:flutter/material.dart';

import '../game/palette.dart' as palette;

/// A full-screen story card: a title and lines that appear one at a time.
///
/// Tapping anywhere reveals the next line; tapping past the last line, or
/// the always-visible Skip button, calls [onDone] exactly once.
class StoryCardScreen extends StatefulWidget {
  const StoryCardScreen({
    required this.title,
    required this.lines,
    required this.onDone,
    this.litSkyline = false,
    super.key,
  });

  final String title;
  final List<String> lines;
  final VoidCallback onDone;

  /// Draws the skyline fully lit (the ending card).
  final bool litSkyline;

  @override
  State<StoryCardScreen> createState() => _StoryCardScreenState();
}

class _StoryCardScreenState extends State<StoryCardScreen> {
  static const _fade = Duration(milliseconds: 300);
  static const _ink = Colors.white;

  int _shown = 1;
  bool _done = false;

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  void _advance() {
    if (_shown >= widget.lines.length) return _finish();
    setState(() => _shown++);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: palette.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _advance,
        child: Stack(
          children: [
            // Task 4 paints the skyline and Pip here (lit when litSkyline).
            const Positioned.fill(child: ColoredBox(color: palette.background)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.title.isNotEmpty) ...[
                      Text(
                        widget.title,
                        style: textTheme.headlineMedium?.copyWith(color: _ink),
                      ),
                      const SizedBox(height: 24),
                    ],
                    for (var i = 0; i < widget.lines.length; i++)
                      _line(i, textTheme),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  key: const Key('story-skip'),
                  onPressed: _finish,
                  style: TextButton.styleFrom(foregroundColor: _ink),
                  child: const Text('Skip'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Every line is laid out from the start so the card never jumps; the
  /// unrevealed ones are invisible and hidden from screen readers.
  Widget _line(int i, TextTheme textTheme) {
    final visible = i < _shown;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: _fade,
          child: Text(
            widget.lines[i],
            style: textTheme.titleMedium?.copyWith(color: _ink),
          ),
        ),
      ),
    );
  }
}

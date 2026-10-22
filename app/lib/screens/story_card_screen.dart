import 'package:flutter/material.dart';

import '../art/pip.dart';
import '../art/skyline.dart';
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
            Positioned.fill(
              child: CustomPaint(painter: _ScenePainter(widget.litSkyline)),
            ),
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

/// The card's backdrop: a skyline along the bottom with Pip in front. Dark
/// with a few outlined buildings, or fully lit for the ending.
class _ScenePainter extends CustomPainter {
  _ScenePainter(this.lit);

  final bool lit;

  static const _count = 12;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.background);
    final height = size.height * 0.34;
    final top = size.height - height;
    final buildings = [
      for (var i = 0; i < _count; i++)
        Building(
          state: i == 2 || i == 10 ? BuildingState.open : BuildingState.locked,
        ),
    ];
    canvas.save();
    canvas.translate(0, top);
    paintSkyline(canvas, Size(size.width, height), buildings, allLit: lit);
    canvas.restore();
    final radius = (size.shortestSide * 0.07).clamp(14.0, 40.0);
    paintPip(
      canvas,
      Offset(size.width / 2, size.height - radius * 1.25),
      radius,
      palette.player,
    );
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.lit != lit;
}

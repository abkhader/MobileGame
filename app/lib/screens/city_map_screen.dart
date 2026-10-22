import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../art/skyline.dart';
import '../data/level_repository.dart';
import '../data/story_repository.dart';
import '../game/palette.dart' as palette;
import 'open_level.dart';

/// Lumen City: one district panel per chapter, each a skyline with one
/// building per level. Open and solved buildings open their level; a
/// district title replays its chapter card.
class CityMapScreen extends StatefulWidget {
  const CityMapScreen({required this.services, super.key});

  final AppServices services;

  @override
  State<CityMapScreen> createState() => _CityMapScreenState();
}

class _CityMapScreenState extends State<CityMapScreen> {
  List<String>? _ids;
  Story? _story;

  AppServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await services.levels.levelIds();
    final story = await services.story.load();
    if (mounted) {
      setState(() {
        _ids = ids;
        _story = story;
      });
    }
  }

  /// The last district's title replays the ending once it has been seen and
  /// the district is complete; otherwise any title replays its card.
  void _openDistrict(int chapter, List<String> districtIds, bool isLast) {
    final progress = services.progress;
    final complete = districtIds.every(
      (id) => progress.progressOf(id).completed,
    );
    if (isLast && progress.endingSeen && complete) {
      showEnding(context, services);
    } else {
      showChapterCard(context, services, chapter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = _ids;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: const Text('Lumen City'),
        backgroundColor: palette.background,
        foregroundColor: Colors.white,
      ),
      body: ids == null
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: services.progress,
              builder: (context, _) => _buildDistricts(ids),
            ),
    );
  }

  Widget _buildDistricts(List<String> ids) {
    final districts = <int, List<String>>{};
    for (final id in ids) {
      districts.putIfAbsent(chapterNumberOf(id) ?? 0, () => []).add(id);
    }
    final lastChapter = districts.keys.isEmpty ? null : districts.keys.last;
    // Unlocks depend on the level before, across districts: map all at once.
    final all = buildingsFor(ids, services.progress);
    final buildingOf = {for (var i = 0; i < ids.length; i++) ids[i]: all[i]};
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final MapEntry(key: chapter, value: districtIds)
              in districts.entries)
            _DistrictPanel(
              title:
                  _story?.chapters[chapter]?.title ??
                  chapterOf(districtIds.first),
              allIds: ids,
              districtIds: districtIds,
              buildings: [for (final id in districtIds) buildingOf[id]!],
              onTitle: () =>
                  _openDistrict(chapter, districtIds, chapter == lastChapter),
              onOpen: (id) => openLevel(context, services, id),
            ),
        ],
      ),
    );
  }
}

class _DistrictPanel extends StatefulWidget {
  const _DistrictPanel({
    required this.title,
    required this.allIds,
    required this.districtIds,
    required this.buildings,
    required this.onTitle,
    required this.onOpen,
  });

  final String title;
  final List<String> allIds;
  final List<String> districtIds;
  final List<Building> buildings;
  final VoidCallback onTitle;
  final ValueChanged<String> onOpen;

  @override
  State<_DistrictPanel> createState() => _DistrictPanelState();
}

class _DistrictPanelState extends State<_DistrictPanel> {
  static const _minSlot = 48.0;
  static const _skylineHeight = 148.0;
  static const _labelHeight = 28.0;

  ScrollController? _scroll;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1020),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.gridLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton(
            onPressed: widget.onTitle,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: Text(
              widget.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          LayoutBuilder(builder: _buildSkyline),
        ],
      ),
    );
  }

  Widget _buildSkyline(BuildContext context, BoxConstraints constraints) {
    final n = widget.buildings.length;
    final width = constraints.maxWidth;
    final slot = n == 0 ? width : math.max(width / n, _minSlot);
    final contentWidth = slot * n;
    final skyline = SizedBox(
      width: math.max(contentWidth, width),
      height: _skylineHeight + _labelHeight,
      child: Stack(
        children: [
          Positioned.fill(
            bottom: _labelHeight,
            child: CustomPaint(painter: _SkylinePainter(widget.buildings)),
          ),
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < n; i++)
                  SizedBox(width: slot, child: _target(i)),
              ],
            ),
          ),
        ],
      ),
    );
    if (contentWidth <= width) return skyline;
    // Narrow screens scroll the skyline; start with the next building to
    // play in view.
    _scroll ??= ScrollController(
      initialScrollOffset: _frontierOffset(slot, width, contentWidth),
    );
    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      child: skyline,
    );
  }

  double _frontierOffset(double slot, double width, double contentWidth) {
    final i = widget.buildings.indexWhere((b) => b.state == BuildingState.open);
    if (i < 0) return 0;
    return (i * slot - (width - slot) / 2).clamp(0, contentWidth - width);
  }

  Widget _target(int i) {
    final id = widget.districtIds[i];
    final b = widget.buildings[i];
    final n = levelNumber(widget.allIds, id);
    final label = switch (b.state) {
      BuildingState.locked => 'Level $n, locked',
      BuildingState.open => 'Level $n, open',
      BuildingState.solved => 'Level $n, solved, ${b.stars} stars',
    };
    final onTap = b.state == BuildingState.locked
        ? null
        : () => widget.onOpen(id);
    final ink = switch (b.state) {
      BuildingState.locked => Colors.white24,
      BuildingState.open => Colors.white70,
      BuildingState.solved => Colors.white,
    };
    return Semantics(
      key: ValueKey('building-$id'),
      container: true,
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: _labelHeight,
            child: Center(
              child: Text(
                '$n',
                style: TextStyle(
                  color: ink,
                  fontWeight: b.state == BuildingState.solved
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkylinePainter extends CustomPainter {
  _SkylinePainter(this.buildings);

  final List<Building> buildings;

  @override
  void paint(Canvas canvas, Size size) => paintSkyline(canvas, size, buildings);

  @override
  bool shouldRepaint(_SkylinePainter old) {
    if (old.buildings.length != buildings.length) return true;
    for (var i = 0; i < buildings.length; i++) {
      final a = old.buildings[i];
      final b = buildings[i];
      if (a.state != b.state || a.stars != b.stars) return true;
    }
    return false;
  }
}

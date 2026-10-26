import 'package:flutter/material.dart';

import '../app_services.dart';
import '../art/skyline.dart';
import '../data/level_repository.dart';
import '../data/story_repository.dart';
import '../game/palette.dart' as palette;
import 'ability_badges.dart';
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
        actions: [
          if (ids != null)
            ListenableBuilder(
              listenable: services.progress,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  // Three sparks per bundled level.
                  child: SparkTotal(
                    count: services.progress.totalSparks,
                    of: ids.length * 3,
                  ),
                ),
              ),
            ),
        ],
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AbilityBadges(total: services.progress.totalSparks),
          const SizedBox(height: 12),
          for (final MapEntry(key: chapter, value: districtIds)
              in districts.entries)
            _DistrictPanel(
              seed: chapter,
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

class _DistrictPanel extends StatelessWidget {
  const _DistrictPanel({
    required this.seed,
    required this.title,
    required this.allIds,
    required this.districtIds,
    required this.buildings,
    required this.onTitle,
    required this.onOpen,
  });

  /// Gives each district its own silhouette.
  final int seed;
  final String title;
  final List<String> allIds;
  final List<String> districtIds;
  final List<Building> buildings;
  final VoidCallback onTitle;
  final ValueChanged<String> onOpen;

  static const _skylineHeight = 148.0;
  static const _labelHeight = 28.0;

  @override
  Widget build(BuildContext context) {
    // Slim padding so ten buildings fit side by side at 320 px: each column
    // is (320 - 2*12 - 2*1 - 2*4) / 10 = 28.6 wide.
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1020),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.gridLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton(
            onPressed: onTitle,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          SizedBox(
            height: _skylineHeight + _labelHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  bottom: _labelHeight,
                  // The skyline only repaints when its buildings change, not
                  // on every ink splash above it.
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _SkylinePainter(buildings, seed),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < buildings.length; i++)
                        Expanded(child: _target(i)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The whole building column is the tap target.
  Widget _target(int i) {
    final id = districtIds[i];
    final b = buildings[i];
    final n = levelNumber(allIds, id);
    final label = switch (b.state) {
      BuildingState.locked => 'Level $n, locked',
      BuildingState.open => 'Level $n, open',
      BuildingState.solved => 'Level $n, solved, ${b.stars} stars',
    };
    final onTap = b.state == BuildingState.locked ? null : () => onOpen(id);
    final ink = switch (b.state) {
      BuildingState.locked => Colors.white38,
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
      // A transparent Material above the painter, so the press shows.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          splashColor: Colors.white24,
          highlightColor: Colors.white10,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: _labelHeight,
              child: Center(
                child: Text(
                  '$n',
                  style: TextStyle(
                    color: ink,
                    // Two digits fit a 28 px column.
                    fontSize: 12,
                    fontWeight: b.state == BuildingState.solved
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
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
  _SkylinePainter(this.buildings, this.seed);

  final List<Building> buildings;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) =>
      paintSkyline(canvas, size, buildings, seed: seed);

  @override
  bool shouldRepaint(_SkylinePainter old) {
    if (old.seed != seed || old.buildings.length != buildings.length) {
      return true;
    }
    for (var i = 0; i < buildings.length; i++) {
      final a = old.buildings[i];
      final b = buildings[i];
      if (a.state != b.state ||
          a.stars != b.stars ||
          a.sparkMask != b.sparkMask) {
        return true;
      }
    }
    return false;
  }
}

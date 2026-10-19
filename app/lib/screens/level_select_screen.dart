import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/level_repository.dart';
import 'game_screen.dart';

class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({required this.services, super.key});

  final AppServices services;

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  List<String>? _ids;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await widget.services.levels.levelIds();
    if (mounted) setState(() => _ids = ids);
  }

  Future<void> _open(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(services: widget.services, levelId: id),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ids = _ids;
    return Scaffold(
      appBar: AppBar(title: const Text('Levels')),
      body: ids == null
          ? const Center(child: CircularProgressIndicator())
          : _buildChapters(context, ids),
    );
  }

  Widget _buildChapters(BuildContext context, List<String> ids) {
    final chapters = <String, List<String>>{};
    for (final id in ids) {
      chapters.putIfAbsent(chapterOf(id), () => []).add(id);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final entry in chapters.entries) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              entry.key,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [for (final id in entry.value) _tile(ids, id)],
          ),
        ],
      ],
    );
  }

  Widget _tile(List<String> ids, String id) {
    final progress = widget.services.progress;
    final unlocked = progress.isUnlocked(id, ids);
    if (!unlocked) {
      return const OutlinedButton(onPressed: null, child: Icon(Icons.lock));
    }
    final stars = progress.progressOf(id).stars;
    return OutlinedButton(
      onPressed: () => _open(id),
      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${levelNumber(ids, id)}'),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Icon(i < stars ? Icons.star : Icons.star_border, size: 10),
            ],
          ),
        ],
      ),
    );
  }
}

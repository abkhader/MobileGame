import 'dart:async';

import 'package:flutter/material.dart';

import '../app_services.dart';
import 'game_screen.dart';
import 'story_card_screen.dart';

/// The chapter number of a level id: "2-05" → 2.
int? chapterNumberOf(String id) => int.tryParse(id.split('-').first);

/// True while an [openLevel] call is loading, so a double tap is ignored.
bool _opening = false;

/// The single route into a level. Shows the chapter's intro card first if it
/// is unseen and the story loaded; the card's done marks it seen and
/// replaces the card with the level.
///
/// With [replace], the route that owns [context] is replaced, even if a menu
/// sits above it.
Future<void> openLevel(
  BuildContext context,
  AppServices services,
  String id, {
  bool replace = false,
}) async {
  if (_opening) return;
  _opening = true;
  try {
    await _openLevel(context, services, id, replace: replace);
  } finally {
    _opening = false;
  }
}

Future<void> _openLevel(
  BuildContext context,
  AppServices services,
  String id, {
  required bool replace,
}) async {
  final navigator = Navigator.of(context);
  final oldRoute = replace ? ModalRoute.of(context) : null;
  final chapter = chapterNumberOf(id);
  final progress = services.progress;

  // Only touch the story when a card might show, so replays stay instant.
  var lines = const <String>[];
  var title = '';
  if (chapter != null && !progress.seenChapterIntro(chapter)) {
    final card = (await services.story.load())?.chapters[chapter];
    if (card != null) {
      lines = card.lines;
      title = card.title;
    }
  }
  if (!context.mounted || (oldRoute != null && !oldRoute.isActive)) return;

  Route<void> gameRoute() => MaterialPageRoute<void>(
    builder: (_) => GameScreen(services: services, levelId: id),
  );

  final Route<void> route;
  if (lines.isEmpty) {
    route = gameRoute();
  } else {
    late final Route<void> cardRoute;
    cardRoute = MaterialPageRoute<void>(
      builder: (_) => StoryCardScreen(
        title: title,
        lines: lines,
        onDone: () {
          unawaited(progress.markChapterIntroSeen(chapter!).catchError((_) {}));
          if (cardRoute.isActive) {
            navigator.replace(oldRoute: cardRoute, newRoute: gameRoute());
          }
        },
      ),
    );
    route = cardRoute;
  }

  if (oldRoute != null) {
    navigator.replace(oldRoute: oldRoute, newRoute: route);
  } else {
    unawaited(navigator.push(route));
  }
}

/// Replays a chapter's intro card, then returns to the caller.
Future<void> showChapterCard(
  BuildContext context,
  AppServices services,
  int chapter,
) async {
  final navigator = Navigator.of(context);
  final card = (await services.story.load())?.chapters[chapter];
  if (card == null || card.lines.isEmpty || !context.mounted) return;
  await _showCard(navigator, title: card.title, lines: card.lines);
}

/// Shows the ending with a fully lit skyline, marks it seen for the current
/// final level, then returns to
/// the caller. Does nothing if the story could not be loaded.
Future<void> showEnding(BuildContext context, AppServices services) async {
  final navigator = Navigator.of(context);
  final ending = (await services.story.load())?.ending;
  final ids = await services.levels.levelIds();
  if (ending == null || ending.isEmpty || ids.isEmpty || !context.mounted) {
    return;
  }
  // Seen as soon as it shows, so system Back cannot make it replay or lose
  // it; kept per final level, so a new last level shows it again.
  unawaited(services.progress.markEndingSeen(ids.last).catchError((_) {}));
  await _showCard(navigator, title: '', lines: ending, litSkyline: true);
}

/// Pushes a card that pops itself when done; completes once it is gone.
Future<void> _showCard(
  NavigatorState navigator, {
  required String title,
  required List<String> lines,
  bool litSkyline = false,
}) {
  late final Route<void> cardRoute;
  cardRoute = MaterialPageRoute<void>(
    builder: (_) => StoryCardScreen(
      title: title,
      lines: lines,
      litSkyline: litSkyline,
      onDone: () {
        if (cardRoute.isCurrent) navigator.pop();
      },
    ),
  );
  return navigator.push(cardRoute);
}

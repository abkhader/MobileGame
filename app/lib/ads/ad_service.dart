/// Ads behind a small seam so the game never depends on an ad SDK.
abstract interface class AdService {
  /// Starts consent and ad loading. Never throws.
  Future<void> initialize();

  /// Shows an interstitial if one is already loaded; returns at once if not.
  Future<void> showInterstitialIfLoaded();

  /// Shows a rewarded ad. True only when the reward was earned.
  Future<bool> showRewarded();
}

/// When an interstitial may appear between levels.
class AdPolicy {
  const AdPolicy();

  /// Only for level 6 or later, on every third completion of the session.
  bool shouldShowInterstitial({
    required int completedThisSession,
    required int levelNumber,
  }) => levelNumber > 5 && completedThisSession % 3 == 0;
}

/// Used on web, where there are no ads: grants every reward.
class DebugAdService implements AdService {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> showInterstitialIfLoaded() async {}

  @override
  Future<bool> showRewarded() async => true;
}

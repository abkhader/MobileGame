import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_service.dart';

/// AdMob with Google's test ad units and the UMP consent flow.
class AdMobAdService implements AdService {
  static const interstitialUnitId = 'ca-app-pub-3940256099942544/1033173712';
  static const rewardedUnitId = 'ca-app-pub-3940256099942544/5224354917';

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _ready = false;

  @override
  Future<void> initialize() async {
    try {
      await _resolveConsent();
    } catch (_) {
      // Consent failed: ads may still load, non-personalized.
    }
    try {
      await MobileAds.instance.initialize();
      _ready = true;
      _loadInterstitial();
      _loadRewarded();
    } catch (_) {
      // Ads are optional: the game carries on without them.
    }
  }

  /// Completes once consent is resolved. A failure still lets ads load
  /// (they may be non-personalized).
  Future<void> _resolveConsent() {
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((_) => finish()),
      (_) => finish(),
    );
    return done.future;
  }

  void _loadInterstitial() {
    if (!_ready) return;
    InterstitialAd.load(
      adUnitId: interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  void _loadRewarded() {
    if (!_ready) return;
    RewardedAd.load(
      adUnitId: rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  @override
  Future<void> showInterstitialIfLoaded() async {
    final ad = _interstitial;
    if (ad == null) return;
    _interstitial = null;
    final done = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) {
        ad.dispose();
        _loadInterstitial();
        if (!done.isCompleted) done.complete();
      },
      onAdFailedToShowFullScreenContent: (_, _) {
        ad.dispose();
        _loadInterstitial();
        if (!done.isCompleted) done.complete();
      },
    );
    try {
      await ad.show();
      await done.future;
    } catch (_) {
      ad.dispose();
      _loadInterstitial();
    }
  }

  @override
  Future<bool> showRewarded() async {
    final ad = _rewarded;
    if (ad == null) return false;
    _rewarded = null;
    final done = Completer<bool>();
    void finish(bool earned) {
      if (!done.isCompleted) done.complete(earned);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => finish(false),
      onAdFailedToShowFullScreenContent: (_, _) => finish(false),
    );
    try {
      await ad.show(onUserEarnedReward: (_, _) => finish(true));
      return await done.future;
    } catch (_) {
      return false;
    } finally {
      ad.dispose();
      _loadRewarded();
    }
  }
}

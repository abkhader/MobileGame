import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_service.dart';

/// AdMob with Google's test ad units and the UMP consent flow.
class AdMobAdService implements AdService {
  static const interstitialUnitId = 'ca-app-pub-3940256099942544/1033173712';
  static const rewardedUnitId = 'ca-app-pub-3940256099942544/5224354917';
  static const _retryDelay = Duration(seconds: 30);
  static const _interstitialTimeout = Duration(seconds: 30);

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _ready = false;
  bool _canRequestAds = false;
  bool _loadingInterstitial = false;
  bool _loadingRewarded = false;

  @override
  Future<void> initialize() async {
    try {
      await _resolveConsent();
    } catch (_) {
      // Consent failed: whatever was gathered before still applies.
    }
    try {
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
      if (!_canRequestAds) return;
      await MobileAds.instance.initialize();
      _ready = true;
      _loadInterstitial();
      _loadRewarded();
    } catch (_) {
      // Ads are optional: the game carries on without them.
    }
  }

  /// Completes once the consent flow is resolved or has failed.
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

  bool get _mayLoad => _ready && _canRequestAds;

  void _loadInterstitial({bool isRetry = false}) {
    if (!_mayLoad || _loadingInterstitial || _interstitial != null) return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (_) {
          _loadingInterstitial = false;
          // Retry once; after that, the next show request starts a load.
          if (!isRetry) {
            Timer(_retryDelay, () => _loadInterstitial(isRetry: true));
          }
        },
      ),
    );
  }

  void _loadRewarded({bool isRetry = false}) {
    if (!_mayLoad || _loadingRewarded || _rewarded != null) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingRewarded = false;
          _rewarded = ad;
        },
        onAdFailedToLoad: (_) {
          _loadingRewarded = false;
          // Retry once; after that, the next show request starts a load.
          if (!isRetry) Timer(_retryDelay, () => _loadRewarded(isRetry: true));
        },
      ),
    );
  }

  @override
  Future<void> showInterstitialIfLoaded() async {
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return;
    }
    _interstitial = null;
    final done = Completer<void>();
    void finish() {
      if (done.isCompleted) return;
      ad.dispose();
      _loadInterstitial();
      done.complete();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => finish(),
      onAdFailedToShowFullScreenContent: (_, _) => finish(),
    );
    try {
      await ad.show();
    } catch (_) {
      return finish();
    }
    // Never let Level Complete's buttons hang on a lost callback.
    await done.future.timeout(_interstitialTimeout, onTimeout: () {});
  }

  @override
  Future<bool> showRewarded() async {
    final ad = _rewarded;
    if (ad == null) {
      _loadRewarded();
      return false;
    }
    _rewarded = null;
    final done = Completer<bool>();
    var earned = false;
    // Completes only once the ad has left the screen.
    void finish(bool result) {
      if (done.isCompleted) return;
      ad.dispose();
      _loadRewarded();
      done.complete(result);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => finish(earned),
      onAdFailedToShowFullScreenContent: (_, _) => finish(false),
    );
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
    } catch (_) {
      finish(false);
      return false;
    }
    return done.future;
  }
}

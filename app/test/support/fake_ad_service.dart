import 'package:echo_app/ads/ad_service.dart';

class FakeAdService implements AdService {
  bool rewardResult = true;
  int interstitialsShown = 0;
  int rewardedShown = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showInterstitialIfLoaded() async => interstitialsShown++;

  @override
  Future<bool> showRewarded() async {
    rewardedShown++;
    return rewardResult;
  }
}

import 'package:echo_app/ads/ad_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interstitial rule', () {
    bool s(int c, int n) => const AdPolicy().shouldShowInterstitial(
      completedThisSession: c,
      levelNumber: n,
    );
    expect(
      [s(3, 3), s(3, 5), s(3, 6), s(4, 7), s(6, 9), s(5, 9)],
      [false, false, true, false, true, false],
    );
  });

  test('DebugAdService grants rewards and never blocks', () async {
    final ads = DebugAdService();
    await ads.initialize();
    await ads.showInterstitialIfLoaded();
    expect(await ads.showRewarded(), isTrue);
  });
}

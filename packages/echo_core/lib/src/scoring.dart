/// Star ratings for a finished run, compared against a level's best score.
abstract final class Scoring {
  /// Returns 3 stars when [score] is at most [best], 2 stars when it is at most
  /// floor(1.5 × [best]), and 1 star otherwise.
  ///
  /// The 2-star bound is compared as `score * 2 <= best * 3`, which is exact
  /// integer arithmetic equivalent to `score <= floor(1.5 * best)`.
  static int stars({required int score, required int best}) {
    if (score <= best) return 3;
    if (score * 2 <= best * 3) return 2;
    return 1;
  }
}

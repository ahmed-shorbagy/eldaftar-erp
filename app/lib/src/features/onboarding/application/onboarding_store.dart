/// Remembers which guided entry paths the owner has dismissed or finished.
abstract class OnboardingStore {
  Future<bool> isComplete(String path);
  Future<int> readStep(String path);
  Future<void> saveStep(String path, int step);
  Future<void> markComplete(String path);
}

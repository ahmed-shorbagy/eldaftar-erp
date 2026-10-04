/// Serializes compound local operations across adapter instances in this isolate.
final class NotePersistenceQueue {
  final _tails = <String, Future<void>>{};

  Future<T> run<T>(String scope, Future<T> Function() action) {
    final previous = _tails[scope] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[scope] = tail;
    tail.then((_) {
      if (identical(_tails[scope], tail)) _tails.remove(scope);
    });
    return result;
  }
}

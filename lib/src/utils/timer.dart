/// A high-resolution wall-clock timer that wraps [Stopwatch].
///
/// Provides nanosecond / microsecond / millisecond accessors and supports
/// lap timing.
class PrecisionTimer {
  final Stopwatch _sw = Stopwatch();
  final List<int> _laps = [];

  /// Starts (or restarts) the timer.
  void start() {
    _sw.reset();
    _sw.start();
  }

  /// Records a lap and returns the elapsed milliseconds since the last lap
  /// (or since [start] for the first lap).
  int lap() {
    final now = _sw.elapsedMilliseconds;
    final previous = _laps.isEmpty ? 0 : _laps.last;
    _laps.add(now);
    return now - previous;
  }

  /// Stops the timer.
  void stop() => _sw.stop();

  /// Elapsed time in milliseconds (rounded).
  int get elapsedMs => _sw.elapsedMilliseconds;

  /// Elapsed time in microseconds.
  int get elapsedUs => _sw.elapsedMicroseconds;

  /// Elapsed time in nanoseconds (approximated from microseconds).
  int get elapsedNs => _sw.elapsedMicroseconds * 1000;

  /// All recorded lap times in milliseconds.
  List<int> get laps => List.unmodifiable(_laps);

  /// Resets the timer and clears lap data.
  void reset() {
    _sw.reset();
    _laps.clear();
  }

  /// Convenience: executes [fn] and returns the elapsed milliseconds.
  static Future<int> measure(Future<void> Function() fn) async {
    final sw = Stopwatch()..start();
    await fn();
    sw.stop();
    return sw.elapsedMilliseconds;
  }

  /// Convenience: executes [fn], records elapsed time, and returns [T].
  static Future<(T result, int elapsedMs)> measureWithResult<T>(
    Future<T> Function() fn,
  ) async {
    final sw = Stopwatch()..start();
    final result = await fn();
    sw.stop();
    return (result, sw.elapsedMilliseconds);
  }
}

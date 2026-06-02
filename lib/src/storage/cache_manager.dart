import 'dart:async';

/// A simple TTL-based in-memory cache.
///
/// Used internally to cache schema introspection results, computed
/// suggestions, and other expensive operations.
class CacheManager<K, V> {
  final Duration _ttl;
  final Map<K, _CacheEntry<V>> _store = {};
  Timer? _pruneTimer;

  /// Creates a [CacheManager] with the given time-to-live [ttl].
  ///
  /// Starts a periodic prune job every [ttl].
  CacheManager({required Duration ttl}) : _ttl = ttl {
    _pruneTimer = Timer.periodic(ttl, (_) => _prune());
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns the cached value for [key], or `null` if absent or expired.
  V? get(K key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _store.remove(key);
      return null;
    }
    return entry.value;
  }

  /// Returns a cached value or computes it with [compute] and caches it.
  Future<V> getOrCompute(K key, Future<V> Function() compute) async {
    final cached = get(key);
    if (cached != null) return cached;
    final value = await compute();
    set(key, value);
    return value;
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Stores [value] under [key] with the configured TTL.
  void set(K key, V value) {
    _store[key] = _CacheEntry(value, DateTime.now().add(_ttl));
  }

  /// Removes [key] from the cache.
  void invalidate(K key) => _store.remove(key);

  /// Clears all cached entries.
  void clear() => _store.clear();

  // ── Housekeeping ──────────────────────────────────────────────────────────

  void _prune() {
    _store.removeWhere((_, entry) => entry.isExpired);
  }

  /// Cancels the background prune timer and releases resources.
  void dispose() {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _store.clear();
  }

  /// Number of non-expired entries currently in the cache.
  int get size => _store.values.where((e) => !e.isExpired).length;
}

class _CacheEntry<V> {
  final V value;
  final DateTime expiresAt;
  _CacheEntry(this.value, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

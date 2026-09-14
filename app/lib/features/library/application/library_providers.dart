import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../core/storage/cache_database.dart';
import '../../../shared/models/models.dart';
import '../domain/library_mappers.dart';

/// Local-only 稍后阅读 list, newest save first.
final readLaterProvider = FutureProvider<List<V2Topic>>((ref) async {
  final rows = await ref.watch(cacheDatabaseProvider).readLaterAll();
  return rows.map(topicFromReadLater).toList(growable: false);
});

/// Local-only 浏览历史 list, newest view first.
final historyProvider = FutureProvider<List<V2Topic>>((ref) async {
  final rows = await ref.watch(cacheDatabaseProvider).historyAll();
  return rows.map(topicFromHistory).toList(growable: false);
});

/// Whether a topic is in 稍后阅读, keyed by topic id.
final isSavedProvider = FutureProvider.family<bool, int>((ref, topicId) {
  return ref.watch(cacheDatabaseProvider).readLaterContains(topicId);
});

/// Mutations for the local personal stores.
///
/// Kept as a plain [Provider] rather than a `Notifier`: nothing here has
/// renderable state of its own, and every mutation invalidates the derived
/// [`readLaterProvider`] / [`historyProvider`] / [`isSavedProvider`] instead.
class LibraryController {
  LibraryController(this._ref);

  final Ref _ref;

  CacheDatabase get _database => _ref.read(cacheDatabaseProvider);

  /// Saves [topic] when absent, removes it when present. Returns `true` when the
  /// topic ended up saved.
  Future<bool> toggleReadLater(V2Topic topic) async {
    final saved = await _database.readLaterContains(topic.id);
    if (saved) {
      await _database.readLaterRemove(topic.id);
    } else {
      await _database.readLaterAdd(readLaterCompanionFromTopic(topic));
    }
    _ref.invalidate(readLaterProvider);
    _ref.invalidate(isSavedProvider(topic.id));
    return !saved;
  }

  Future<void> removeReadLater(int topicId) async {
    await _database.readLaterRemove(topicId);
    _ref.invalidate(readLaterProvider);
    _ref.invalidate(isSavedProvider(topicId));
  }

  Future<void> clearReadLater() async {
    await _database.readLaterClear();
    _ref.invalidate(readLaterProvider);
  }

  /// Fire-and-forget history write.
  ///
  /// History is a convenience record: a storage failure (or a provider that has
  /// already been disposed mid-await) must never break the topic page, so every
  /// error is swallowed here instead of surfacing to the caller.
  Future<void> recordHistory(V2Topic topic) async {
    try {
      await _database.historyRecord(historyCompanionFromTopic(topic));
      _ref.invalidate(historyProvider);
    } catch (_) {
      // Best effort; see doc comment.
    }
  }

  Future<void> removeHistory(int topicId) async {
    await _database.historyRemove(topicId);
    _ref.invalidate(historyProvider);
  }

  Future<void> clearHistory() async {
    await _database.historyClear();
    _ref.invalidate(historyProvider);
  }
}

final libraryControllerProvider = Provider<LibraryController>(
  LibraryController.new,
);

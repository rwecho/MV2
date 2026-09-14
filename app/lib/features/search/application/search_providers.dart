import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/provider_retry.dart';
import '../../../shared/models/models.dart';
import '../../blocked/application/blocked_content.dart';
import '../../blocked/application/blocked_users_controller.dart';
import '../../nodes/application/nodes_providers.dart';

/// Sort modes shown as chips in `designs/05-search.png`.
///
/// [sov2exValue] is the raw `sort` query parameter. The live API only accepts
/// `sumup` (权重/相关度) and `created` (发帖时间) — anything else answers
/// `400 {"message":"invalid sort"}`. There is no reply-count ordering, so
/// [replies] falls back to `created` and its chip stays disabled in the UI
/// (see `search_page.dart`).
enum SearchSort {
  relevance('sumup', '相关度'),
  created('created', '最新'),
  replies('created', '热门');

  const SearchSort(this.sov2exValue, this.label);

  final String sov2exValue;
  final String label;
}

/// Selected sort mode (相关度 / 最新). The disabled chips never set it.
class SearchSortController extends Notifier<SearchSort> {
  @override
  SearchSort build() => SearchSort.relevance;

  void select(SearchSort sort) => state = sort;
}

final searchSortProvider = NotifierProvider<SearchSortController, SearchSort>(
  SearchSortController.new,
);

/// The committed query. The page debounces the text field before writing here.
class SearchQueryController extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;

  void clear() => state = '';
}

final searchQueryProvider = NotifierProvider<SearchQueryController, String>(
  SearchQueryController.new,
);

/// Topic results for the 主题 tab (sov2ex). Empty query → no request.
final searchResultsProvider = FutureProvider.autoDispose<List<V2Topic>>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const <V2Topic>[];
  final sort = ref.watch(searchSortProvider);
  final topics = await ref
      .watch(v2exApiProvider)
      .searchTopics(query, sort: sort.sov2exValue);
  return BlockedContent.topics(ref.watch(blockedUsersProvider), topics);
}, retry: mv2Retry);

/// User results for the 用户 tab.
final searchUsersProvider = FutureProvider.autoDispose<List<V2User>>((ref) {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return Future<List<V2User>>.value(const <V2User>[]);
  return ref.watch(v2exApiProvider).searchUsers(query);
}, retry: mv2Retry);

/// Node results for the 节点 tab: the hot node list filtered client-side.
final searchNodesProvider = FutureProvider.autoDispose<List<V2Node>>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  if (query.isEmpty) return const <V2Node>[];
  final nodes = await ref.watch(nodesProvider.future);
  return nodes
      .where(
        (node) =>
            node.name.toLowerCase().contains(query) ||
            node.key.toLowerCase().contains(query) ||
            node.tags.any((tag) => tag.toLowerCase().contains(query)),
      )
      .toList(growable: false);
}, retry: mv2Retry);

/// 最近搜索, persisted in `SharedPreferences` (survives restarts).
///
/// Hydration mirrors `SettingsController`: defaults render for the first frame
/// and the stored list replaces them once storage answers.
class RecentSearchesController extends Notifier<List<String>> {
  static const String _storageKey = 'mv2.recentSearches';
  static const int _maxEntries = 8;

  /// Seeded once, on a fresh install, so the empty-query state matches
  /// `designs/05-search.png`. 清空 removes the key, so the seed does not return.
  static const List<String> _seed = <String>[
    'Claude Code',
    'MAUI',
    'Indie Hacker',
    '远程开发',
  ];

  SharedPreferences? _prefs;

  @override
  List<String> build() {
    Future<void>(() async => _hydrate());
    return const <String>[];
  }

  Future<void> _hydrate() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    state = prefs.getStringList(_storageKey) ?? List<String>.of(_seed);
  }

  /// Promotes [term] to the front; most-recent-first, de-duplicated.
  Future<void> add(String term) async {
    final value = term.trim();
    if (value.isEmpty) return;
    final next = <String>[
      value,
      ...state.where((item) => item != value),
    ].take(_maxEntries).toList(growable: false);
    state = next;
    await _save(next);
  }

  Future<void> clear() async {
    state = const <String>[];
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<void> _save(List<String> value) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, value);
  }
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesController, List<String>>(
      RecentSearchesController.new,
    );

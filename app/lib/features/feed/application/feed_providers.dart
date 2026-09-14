import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/data/home_tab.dart';
import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/provider_retry.dart';
import '../../../shared/models/models.dart';
import '../../blocked/application/blocked_content.dart';
import '../../blocked/application/blocked_users_controller.dart';

/// Currently selected home tab (`技术 … VXNA`).
///
/// The choice is persisted: first run selects [HomeTab.initial] (`R2`) and
/// every later launch restores the last tab, matching the "动态选中 + 记住上
/// 次" behaviour. Hydration follows the `SettingsController` pattern — the UI
/// renders the default for the first frame and rebuilds once storage answers.
class HomeTabController extends Notifier<HomeTab> {
  /// `SharedPreferences` key holding the persisted [HomeTab.name].
  static const String storageKey = 'mv2.homeTab';

  SharedPreferences? _prefs;

  @override
  HomeTab build() {
    Future<void>(() async => _hydrate());
    return HomeTab.initial;
  }

  Future<void> _hydrate() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    // The first frame may be disposed (tests, hot restart) before storage
    // answers; writing state then would throw `UnmountedRefException`.
    if (!ref.mounted) return;
    state = HomeTab.fromName(prefs.getString(storageKey)) ?? HomeTab.initial;
  }

  Future<void> select(HomeTab tab) async {
    if (state == tab) return;
    state = tab;
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(storageKey, tab.name);
  }
}

final homeTabProvider = NotifierProvider<HomeTabController, HomeTab>(
  HomeTabController.new,
);

/// Topic list for one topic tab, cached per tab so swiping back to an already
/// visited tab does not refetch. Returns an empty list for [HomeTab.vxna],
/// which the page renders through [xnaFeedProvider] instead.
///
/// 屏蔽用户 is applied here so every consumer (home, and anything that reuses
/// this provider) sees the same filtered list.
final feedProvider = FutureProvider.family<List<V2Topic>, HomeTab>((
  ref,
  tab,
) async {
  if (tab.isAggregator) return const <V2Topic>[];
  final topics = await ref.watch(v2exApiProvider).feed(tab);
  return BlockedContent.topics(ref.watch(blockedUsersProvider), topics);
}, retry: mv2Retry);

/// VXNA aggregator entries (`/xna`).
final xnaFeedProvider = FutureProvider<List<V2XnaEntry>>((ref) {
  return ref.watch(v2exApiProvider).xna();
}, retry: mv2Retry);

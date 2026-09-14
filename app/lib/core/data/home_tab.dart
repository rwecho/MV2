import '../network/v2ex_endpoints.dart';

/// The home feed's top tab row, mirroring `www.v2ex.com`'s `#Tabs` in order
/// and label (verified live 2026-09-11):
///
/// `技术 创意 好玩 Apple 酷工作 交易 城市 问与答 最热 全部 R2 VXNA`.
///
/// Every entry except [HomeTab.vxna] is a topic list served from
/// `/?tab={slug}` and parsed by `FeedParser`. [HomeTab.vxna] is the site's
/// external-source aggregator at `/xna` — a different page layout, a different
/// item model and external outbound links — so it is routed separately.
enum HomeTab {
  tech('tech', '技术'),
  creative('creative', '创意'),
  play('play', '好玩'),
  apple('apple', 'Apple'),
  jobs('jobs', '酷工作'),
  deals('deals', '交易'),
  city('city', '城市'),
  qna('qna', '问与答'),
  hot('hot', '最热'),
  all('all', '全部'),
  r2('r2', 'R2'),
  vxna('xna', 'VXNA');

  const HomeTab(this.slug, this.label);

  /// Value of the site's `?tab=` query parameter (`vxna` maps to `/xna`).
  final String slug;

  /// Tab label exactly as rendered by V2EX.
  final String label;

  /// The aggregator tab: its page markup and item schema differ from the
  /// topic-list tabs, so the feed branches on this.
  bool get isAggregator => this == HomeTab.vxna;

  /// Site path that serves this tab.
  String get path =>
      isAggregator ? V2exEndpoints.xna : V2exEndpoints.homeTab(slug);

  /// First-run selection; afterwards the user's last choice is restored
  /// (`HomeTabController`).
  static const HomeTab initial = HomeTab.r2;

  /// Resolves a persisted enum [name] back to a tab, or `null` when the stored
  /// value is unknown (e.g. a tab removed in a later release).
  static HomeTab? fromName(String? name) {
    if (name == null) return null;
    for (final tab in values) {
      if (tab.name == name) return tab;
    }
    return null;
  }
}

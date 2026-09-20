/// Freshness windows for stale-while-revalidate reads (磁盘换时间).
///
/// A window gates whether a disk-cached response may be rendered as the first
/// frame. It is *not* how long the user looks at it: a hit always kicks off an
/// immediate background revalidation, so cached data is on screen only for the
/// network round-trip before being swapped in place. Entries older than the
/// window are never rendered (过期不展示) — they remain reachable solely
/// through the 7-day offline fallback in `HttpCache`, and pull-to-refresh
/// always bypasses the cache entirely.
abstract final class CacheTtl {
  /// Home feed tabs. 30 分钟覆盖「切出去几分钟再回来」的高频场景；隔夜后的
  /// 冷启动宁可走骨架屏也不显示过期列表。调这个值之前先看
  /// `feed_cache_hit` 的 `age_sec` 分布。
  static const Duration feedFresh = Duration(minutes: 30);
}

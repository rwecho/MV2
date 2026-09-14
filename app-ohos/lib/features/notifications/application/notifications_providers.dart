import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/errors/provider_retry.dart';
import '../../../core/native/widget_sync.dart';
import '../../../core/parser/notification_parser.dart';
import '../../../core/push/push_providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/notification_page.dart';
import '../../../shared/models/topic_detail.dart';
import '../../auth/application/auth_controller.dart';

/// Unread notifications shown on the shell's tab-bar badge.
///
/// Real value: `AuthSession.unreadCount`, scraped from the signed-in home
/// page's `#Rightbar` (the same signal the website badge uses). `0` while
/// signed out or before the account has been revalidated — no hardcoded `3`.
final notificationUnreadProvider = Provider<int>((ref) {
  final session = ref.watch(authControllerProvider).value;
  return session?.unreadCount ?? 0;
});

/// One page of `/notifications` (page N).
final notificationsPageProvider = FutureProvider.family<NotificationPage, int>((
  ref,
  page,
) {
  return ref.watch(v2exApiProvider).notifications(page: page);
}, retry: mv2Retry);

/// First notifications page — the simple handle for callers that do not page.
final notificationsProvider = FutureProvider<NotificationPage>((ref) {
  return ref.watch(v2exApiProvider).notifications();
}, retry: mv2Retry);

/// Accumulated notification list behind the infinite-scroll page.
@immutable
class NotificationsState {
  const NotificationsState({
    this.groups = const <V2NotificationGroup>[],
    this.pagination = const V2Pagination(),
    this.isSignedOut = false,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.failed = false,
    this.failure,
  });

  final List<V2NotificationGroup> groups;
  final V2Pagination pagination;

  /// `/notifications` redirected to `/signin` — the page shows the CTA.
  final bool isSignedOut;

  /// First page still loading (skeleton state).
  final bool isLoading;

  /// Next page in flight (inline footer spinner).
  final bool isLoadingMore;

  /// The first page failed (error state).
  final bool failed;

  /// The failure behind [failed] / the last [loadMore] error, so the page can
  /// toast the real message. `null` once a load succeeds.
  final Failure? failure;

  bool get isEmpty => groups.every((group) => group.items.isEmpty);

  bool get hasMore => !isSignedOut && !failed && pagination.hasMore;

  NotificationsState copyWith({
    List<V2NotificationGroup>? groups,
    V2Pagination? pagination,
    bool? isSignedOut,
    bool? isLoading,
    bool? isLoadingMore,
    bool? failed,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return NotificationsState(
      groups: groups ?? this.groups,
      pagination: pagination ?? this.pagination,
      isSignedOut: isSignedOut ?? this.isSignedOut,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      failed: failed ?? this.failed,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

/// Loads the first page eagerly and appends subsequent pages on demand.
///
/// Duplicate loads are guarded by [NotificationsState.isLoadingMore] /
/// [NotificationsState.isLoading] and by notification id while merging, so a
/// fast scroll cannot queue the same page twice.
class NotificationsController extends Notifier<NotificationsState> {
  @override
  NotificationsState build() {
    Future<void>(() => _loadFirstPage());
    return const NotificationsState();
  }

  /// Re-runs the first page from scratch (error-state 重试 action).
  Future<void> refresh() async {
    ref.invalidate(notificationsProvider);
    await _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    state = state.copyWith(isLoading: true, failed: false, clearFailure: true);
    try {
      final page = await ref.read(notificationsProvider.future);
      state = NotificationsState(
        groups: page.groups,
        pagination: page.pagination,
        isSignedOut: page.isSignedOut,
        isLoading: false,
      );
      // Opening the page marks the notifications read server-side, so re-scrape
      // the account to clear the tab-bar badge.
      if (!page.isSignedOut) {
        // Mirror the page into the Home Screen widget. This is the only place
        // previews reach the widget, and it happens because the user actually
        // opened the notifications page — never as a side effect of launching.
        unawaited(publishWidgetSnapshot(ref, page: page));
        unawaited(ref.read(authControllerProvider.notifier).refreshAccount());
        // This page is the only place the account's private feed URL appears,
        // and the push worker needs it to poll for new notifications.
        unawaited(ref.read(pushServiceProvider).register(feedUrl: page.feedUrl));
      }
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        failed: true,
        failure: error is Failure ? error : const ServerFailure(),
      );
    }
  }

  /// Appends the next page when the list approaches the bottom.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final next = state.pagination.current + 1;
    state = state.copyWith(isLoadingMore: true, clearFailure: true);
    try {
      final page = await ref.read(notificationsPageProvider(next).future);
      state = state.copyWith(
        groups: _mergeGroups(state.groups, page.groups),
        pagination: page.pagination,
        isLoadingMore: false,
      );
    } catch (error) {
      state = state.copyWith(
        isLoadingMore: false,
        failure: error is Failure ? error : const ServerFailure(),
      );
    }
  }

  /// Appends [next] onto [current], de-duplicating by notification id.
  static List<V2NotificationGroup> _mergeGroups(
    List<V2NotificationGroup> current,
    List<V2NotificationGroup> next,
  ) {
    final seen = <String>{
      for (final group in current) ...group.items.map((item) => item.id),
    };
    final merged = <String, List<V2Notification>>{
      for (final group in current)
        group.title: List<V2Notification>.of(group.items),
    };

    for (final group in next) {
      final bucket = merged.putIfAbsent(group.title, () => <V2Notification>[]);
      for (final item in group.items) {
        if (seen.add(item.id)) bucket.add(item);
      }
    }

    return <V2NotificationGroup>[
      for (final title in NotificationParser.groupOrder)
        if (merged[title]?.isNotEmpty ?? false)
          V2NotificationGroup(title: title, items: merged[title]!),
    ];
  }
}

final notificationsControllerProvider =
    NotifierProvider<NotificationsController, NotificationsState>(
      NotificationsController.new,
    );

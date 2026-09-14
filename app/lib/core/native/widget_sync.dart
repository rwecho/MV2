import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_session.dart';
import '../../shared/models/notification_page.dart';
import 'mv2_native_bridge.dart';
import 'widget_snapshot.dart';

/// The notifications page the widget is currently showing previews from.
///
/// Count-only updates (a badge change, a session refresh) reuse it, otherwise the
/// widget would lose its previews every time the unread number moved.
class WidgetPreviewController extends Notifier<NotificationPage?> {
  @override
  NotificationPage? build() => null;

  void set(NotificationPage page) => state = page;

  void clear() => state = null;
}

final widgetPreviewProvider =
    NotifierProvider<WidgetPreviewController, NotificationPage?>(
      WidgetPreviewController.new,
    );

/// Publishes a widget snapshot.
///
/// Called from the feature that owns the data — the notifications controller
/// pushes a page here as soon as it loads — and from [widgetSyncProvider] for
/// count/session changes. It must never be called merely to *trigger* a
/// `/notifications` fetch: that marks the account's notifications read on the
/// server (`docs/12` §8).
Future<void> publishWidgetSnapshot(Ref ref, {NotificationPage? page}) {
  final auth = ref.read(authControllerProvider);
  // A half-loaded session would flash "未登录" on the widget and wipe previews.
  if (!auth.hasValue) return Future<void>.value();

  final signedIn = auth.value?.isSignedIn ?? false;
  final previews = ref.read(widgetPreviewProvider.notifier);
  if (page != null) previews.set(page);
  // Signing out must not leave the previous account's previews on screen.
  if (!signedIn) previews.clear();

  final current = ref.read(widgetPreviewProvider);
  final items = <Mv2WidgetItem>[
    if (current != null && !current.isSignedOut)
      for (final item in current.items.take(3))
        Mv2WidgetItem(
          actor: item.actor.username,
          text: item.quote.trim().isNotEmpty ? item.quote : item.sourceTitle,
          topicId: item.topicId,
        ),
  ];

  return ref
      .read(nativeBridgeProvider)
      .setWidgetSnapshot(
        Mv2WidgetSnapshot(
          // Same source the tab-bar badge uses (the sidebar's unread count).
          unreadCount: auth.value?.unreadCount ?? 0,
          updatedAt: DateTime.now(),
          signedIn: signedIn,
          items: items,
        ),
      );
}

/// Root-level sync for the parts of the snapshot the account already carries
/// (unread count + signed-in state). Watched once from `app.dart`.
///
/// It reacts to [authControllerProvider] only, and must not import the
/// notifications providers: the notifications controller imports this file to
/// publish its page, and depending on it here would close an import cycle.
final widgetSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<AuthSession>>(
    authControllerProvider,
    (previous, next) => unawaited(publishWidgetSnapshot(ref)),
  );

  // Initial publish: count + session only — never a notification fetch.
  unawaited(publishWidgetSnapshot(ref));
});

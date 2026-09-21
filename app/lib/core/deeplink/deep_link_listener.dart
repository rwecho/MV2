import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/router.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_session.dart';
import '../../features/composer/presentation/composer_sheets.dart';
import '../../ui/utils/mv2_breakpoints.dart';
import '../native/mv2_native_bridge.dart';
import '../push/push_payload.dart';
import '../push/push_providers.dart';
import '../telemetry/mv2_analytics.dart';
import '../telemetry/mv2_events.dart';
import 'clipboard_probe.dart';
import 'deep_link.dart';

/// Receives `mv2://` links while the app is running and offers to open V2EX
/// links found on the clipboard.
///
/// Cold starts are handled by the router's `initialLocation` (see
/// `app/router.dart`); this widget covers the warm path — the app is already
/// open and the link arrives from another app — plus the pasteboard case, which
/// is the only way a shared `https://www.v2ex.com/...` link can reach us
/// (`docs/02` §Deep Link).
///
/// It is also where FCM lives: the push service is started here (once, at
/// first shell build), notification taps are turned into routes, and a
/// foreground message refreshes the unread badge — the system does not render
/// foreground notifications, so the badge is the only visible signal.
class Mv2DeepLinkListener extends ConsumerStatefulWidget {
  const Mv2DeepLinkListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<Mv2DeepLinkListener> createState() =>
      _Mv2DeepLinkListenerState();
}

class _Mv2DeepLinkListenerState extends ConsumerState<Mv2DeepLinkListener>
    with WidgetsBindingObserver {
  final AppLinks _links = AppLinks();
  StreamSubscription<Uri>? _subscription;
  StreamSubscription<Map<String, Object?>>? _pushOpened;
  StreamSubscription<Map<String, Object?>>? _pushForeground;

  static final RegExp _topicRoute = RegExp(r'^/topic/(\d+)');

  /// Last link we opened or prompted for; stops the resume loop from nagging.
  String? _lastSeen;

  /// 上次已处理过的系统剪贴板计数（iOS `changeCount`），持久化到
  /// SharedPreferences：同一段剪贴板内容跨冷启动只处理一次，否则每次
  /// 打开 app 都会对着同一段 Mac 上的内容再弹一次「允许粘贴」。
  static const String _pasteboardCountKey = 'mv2.clipboard.handledChangeCount';
  int? _handledPasteboardCount;
  bool _pasteboardCountReady = false;

  String get _layout => mv2IsTwoPane(context) ? 'tablet' : 'phone';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _links.uriLinkStream.listen(
      (uri) => _open(uri.toString()),
      // A malformed link from the platform must not take the app down.
      onError: (Object _) {},
    );
    _startPush();
    _startQuickActions();
    // On a cold start the `resumed` callback has already fired before this
    // widget mounts, so check the pasteboard once here as well — after the
    // persisted change counter loaded, or the first launch would re-read a
    // clipboard it has already offered on.
    SharedPreferences.getInstance().then((prefs) {
      _handledPasteboardCount = prefs.getInt(_pasteboardCountKey);
      _pasteboardCountReady = true;
      unawaited(_offerClipboardLink());
    }).catchError((Object _) {
      // 测试/无插件环境：没有持久化计数也照样工作（退化为每次会话检测）。
      _pasteboardCountReady = true;
      unawaited(_offerClipboardLink());
    });
  }

  /// Home Screen quick actions (long-press the app icon). The item's `route` is
  /// declared in `Info.plist`; a cold launch buffers it natively until here.
  void _startQuickActions() {
    final bridge = ref.read(nativeBridgeProvider);
    bridge.onQuickAction((String route) {
      if (mounted) _openQuickAction(route);
    });
    unawaited(() async {
      final route = await bridge.consumePendingQuickAction();
      if (!mounted || route == null) return;
      _openQuickAction(route);
    }());
  }

  /// Quick-action routes are ordinary locations, except 发布主题: the composer
  /// is a modal sheet over wherever the user is (same as the shell's 发布
  /// tab), not a route — `/publish` deliberately does not exist in the table.
  void _openQuickAction(String route) {
    if (route == '/publish') {
      _showPublishComposer();
      return;
    }
    _navigate(route);
  }

  void _showPublishComposer() {
    // The navigator mounts with the first frame; a cold-start quick action can
    // arrive before that, so defer one frame if it is not up yet.
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      unawaited(showPublishComposer(context, source: 'quick_action'));
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = rootNavigatorKey.currentContext;
      if (context != null) {
        unawaited(showPublishComposer(context, source: 'quick_action'));
      }
    });
  }

  /// Boots FCM and wires taps / foreground messages. Registration itself needs
  /// the account's feed URL, which only `/notifications` carries — a device
  /// that has visited it before re-registers here on every cold start.
  void _startPush() {
    final push = ref.read(pushServiceProvider);
    _pushOpened = push.openedPayloads.listen(_openPushPayload);
    _pushForeground = push.foregroundMessages.listen((_) {
      // Do NOT reload the notifications page: fetching it marks the server-side
      // notifications read. Refreshing the account only moves the badge.
      unawaited(ref.read(authControllerProvider.notifier).refreshAccount());
    });
    unawaited(push.start().then((_) {
      if (!mounted) return;
      if (ref.read(authControllerProvider).value?.isSignedIn ?? false) {
        unawaited(push.register());
      }
    }));
  }

  void _openPushPayload(Map<String, Object?> data) {
    final route = Mv2PushPayload.routeFor(data);
    if (route == null) {
      // 点击事件确实到达了 Dart，但 worker 的 payload 拼不出路由 —— 这与
      // "点击无反应"是两种故障，留一行痕迹才分得开（issue #2 排查）。
      debugPrint('MV2: push tap carried no usable route: $data');
      return;
    }
    // 归因:推送点开 + 若落地是主题,补一条带 push 来源的 topic_open。
    final match = _topicRoute.firstMatch(route);
    if (match != null) {
      final topicId = int.parse(match.group(1)!);
      Mv2Analytics.logPushOpen(topicId: topicId);
    }
    _navigate(route, source: 'push');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    unawaited(_pushOpened?.cancel());
    unawaited(_pushForeground?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_offerClipboardLink());
  }

  void _open(String raw) {
    final route = Mv2DeepLink.routeFor(raw);
    if (route == null) return;
    _lastSeen = Mv2DeepLink.urlIn(raw) ?? raw;
    Mv2Analytics.logDeeplinkOpen(kind: raw.startsWith('mv2://') ? 'mv2' : 'web');
    _navigate(route, source: 'deeplink');
  }

  /// Sheet cards (用户主页, 节点, 设置, …) and topic detail ride above whatever
  /// is on screen: `go` to one of those would *become* the whole stack — a
  /// topic page opened from a notification had nothing beneath it, so its
  /// back button (and Android's system back) had nothing to pop. Only the
  /// shell branch locations keep `go`: there it is the ordinary tab switch,
  /// and `push` would stack a duplicate page above the shell.
  ///
  /// [source] only feeds the `topic_open` attribution when the route lands on
  /// a topic; quick actions (which never target `/topic/…`) pass nothing and
  /// stay unlogged here.
  void _navigate(String route, {String source = Mv2Events.unspecified}) {
    final match = _topicRoute.firstMatch(route);
    if (match != null) {
      Mv2Analytics.logTopicOpen(
        topicId: int.parse(match.group(1)!),
        source: source,
        layout: _layout,
      );
    }
    final router = ref.read(routerProvider);
    if (mv2IsShellBranchLocation(route)) {
      router.go(route);
    } else {
      router.push(route);
    }
  }

  /// Reading the pasteboard makes iOS show its "允许粘贴" prompt, so the raw
  /// read is the LAST step, behind two prompt-free gates from
  /// [ClipboardProbe]: the pasteboard must have changed since the last
  /// handled check (`changeCount`, persisted — the same Mac-side clipboard
  /// must not re-prompt on every launch), and it must look like a web URL
  /// (`detectPatterns`). Only a genuinely new link pays the prompt, with the
  /// offer appearing right after it.
  Future<void> _offerClipboardLink() async {
    if (!_pasteboardCountReady) return;
    final probe = ref.read(clipboardProbeProvider);
    final count = await probe.changeCount();
    final counted = count != null;
    if (counted && count == _handledPasteboardCount) return;

    final probable = await probe.hasProbableWebURL();
    if (probable == false) {
      // 不是链接：记住这个计数，同一段内容不再反复探测。
      if (counted) await _rememberPasteboardCount(count);
      return;
    }

    final ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (counted) await _rememberPasteboardCount(count);

    final text = data?.text;
    final route = Mv2DeepLink.routeFor(text);
    final url = Mv2DeepLink.urlIn(text);
    if (route == null || url == null || url == _lastSeen) return;
    _lastSeen = url;

    messenger.hideCurrentSnackBar();
    Mv2Analytics.logClipboardOffer(action: 'shown');
    messenger.showSnackBar(
      SnackBar(
        content: const Text('检测到 V2EX 链接'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '打开',
          onPressed: () {
            Mv2Analytics.logClipboardOffer(action: 'accepted');
            _navigate(route, source: 'clipboard');
          },
        ),
      ),
    );
  }

  Future<void> _rememberPasteboardCount(int count) async {
    _handledPasteboardCount = count;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_pasteboardCountKey, count);
    } catch (_) {
      // 持久化失败只影响跨启动去重，本会话内的闸门仍然有效。
    }
  }

  @override
  Widget build(BuildContext context) {
    // Signing out must stop the worker from polling the previous account's
    // feed; the next `/notifications` visit registers the new one.
    ref.listen<AsyncValue<AuthSession>>(authControllerProvider, (previous, next) {
      final wasSignedIn = previous?.value?.isSignedIn ?? false;
      final isSignedIn = next.value?.isSignedIn ?? false;
      if (wasSignedIn && !isSignedIn) {
        unawaited(ref.read(pushServiceProvider).forgetFeedUrl());
      }
    });
    return widget.child;
  }
}

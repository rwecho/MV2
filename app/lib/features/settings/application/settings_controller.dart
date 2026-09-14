import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appearance mode — mirrors `designs/08-settings.png` → 外观 / 主题.
enum Mv2ColorMode {
  system('跟随系统'),
  light('浅色'),
  dark('深色');

  const Mv2ColorMode(this.label);

  final String label;
}

/// Reading scale — mirrors `designs/08-settings.png` → 外观 / 字体大小, and the
/// legacy app's 14/16/18px root sizes.
enum Mv2FontSize {
  small('小', 0.875),
  medium('默认', 1),
  large('大', 1.125);

  const Mv2FontSize(this.label, this.scale);

  final String label;
  final double scale;
}

/// Content column width — mirrors `designs/08-settings.png` → 外观 / 内容宽度.
///
/// [maxWidth] is the pixel cap applied to reading lists on wide viewports;
/// phones are narrower than both values, so it only bites on large screens.
enum Mv2ContentWidth {
  narrow('标准', 600),
  wide('宽', 760);

  const Mv2ContentWidth(this.label, this.maxWidth);

  final String label;
  final double maxWidth;
}

/// How an external `http(s)` link opened from topic/reply content is handled.
///
/// `reader` and `original` both push the in-app reader and only differ in the
/// mode it starts in; `browser` skips the reader and hands the URL to the
/// system browser. The reader page's own mode switch can always override the
/// starting choice for that visit.
enum Mv2LinkOpenMode {
  reader('阅读模式'),
  original('原文模式'),
  browser('外部浏览器');

  const Mv2LinkOpenMode(this.label);

  final String label;
}

enum Mv2ReplySort {
  time('时间'),
  likes('热度');

  const Mv2ReplySort(this.label);

  final String label;
}

@immutable
class AppSettings {
  const AppSettings({
    this.colorMode = Mv2ColorMode.system,
    this.fontSize = Mv2FontSize.medium,
    this.contentWidth = Mv2ContentWidth.narrow,
    this.openLinkMode = Mv2LinkOpenMode.reader,
    this.autoCollapseReplies = true,
    this.hapticsEnabled = true,
    this.pushEnabled = true,
    this.replySort = Mv2ReplySort.time,
  });

  final Mv2ColorMode colorMode;
  final Mv2FontSize fontSize;
  final Mv2ContentWidth contentWidth;
  final Mv2LinkOpenMode openLinkMode;
  final bool autoCollapseReplies;
  final bool hapticsEnabled;

  /// Whether this device registers with the MV2 push worker. Enabling prompts
  /// for the OS notification permission; disabling unregisters server-side so
  /// the worker stops polling the account's feed.
  final bool pushEnabled;

  final Mv2ReplySort replySort;

  ThemeMode get themeMode => switch (colorMode) {
    Mv2ColorMode.system => ThemeMode.system,
    Mv2ColorMode.light => ThemeMode.light,
    Mv2ColorMode.dark => ThemeMode.dark,
  };

  AppSettings copyWith({
    Mv2ColorMode? colorMode,
    Mv2FontSize? fontSize,
    Mv2ContentWidth? contentWidth,
    Mv2LinkOpenMode? openLinkMode,
    bool? autoCollapseReplies,
    bool? hapticsEnabled,
    bool? pushEnabled,
    Mv2ReplySort? replySort,
  }) {
    return AppSettings(
      colorMode: colorMode ?? this.colorMode,
      fontSize: fontSize ?? this.fontSize,
      contentWidth: contentWidth ?? this.contentWidth,
      openLinkMode: openLinkMode ?? this.openLinkMode,
      autoCollapseReplies: autoCollapseReplies ?? this.autoCollapseReplies,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      replySort: replySort ?? this.replySort,
    );
  }
}

/// User preferences (a `SettingsProvider` per `docs/03` §5 — deliberately not
/// part of a global god-store).
class SettingsController extends Notifier<AppSettings> {
  static const _kColorMode = 'mv2.colorMode';
  static const _kFontSize = 'mv2.fontSize';
  static const _kContentWidth = 'mv2.contentWidth';
  static const _kOpenLinkMode = 'mv2.linkOpenMode';
  static const _kAutoCollapse = 'mv2.autoCollapseReplies';
  static const _kHaptics = 'mv2.haptics';
  static const _kPush = 'mv2.push.enabled';
  static const _kReplySort = 'mv2.replySort';

  SharedPreferences? _prefs;

  /// Set as soon as the user changes anything. Hydration is async, so without
  /// this a change made in the first frames would be silently reverted when
  /// storage answers.
  bool _dirty = false;

  @override
  AppSettings build() {
    // Kick off hydration; the UI renders defaults for the first frame and
    // rebuilds once storage answers.
    //
    // `microtask`, not `Future(...)`: the latter schedules a zero-duration
    // `Timer`, which a widget test that only pumps once reports as
    // "A Timer is still pending". A microtask is drained by that same pump.
    Future<void>.microtask(_hydrate);
    return const AppSettings();
  }

  Future<void> _hydrate() async {
    // `_hydrate` is fire-and-forget from `build()`, so an exception here is an
    // *unhandled* async error. `SharedPreferences.getInstance()` throws
    // `MissingPluginException` wherever the plugin is not registered (notably
    // `flutter test`), which used to fail whichever test first read
    // `settingsProvider`. Keep the defaults instead; a broken prefs store must
    // not brick settings.
    final SharedPreferences prefs;
    try {
      prefs = _prefs ??= await SharedPreferences.getInstance();
    } catch (error) {
      debugPrint('MV2: settings storage unavailable, using defaults: $error');
      return;
    }
    // The user already changed something while storage was answering; their
    // choice wins over whatever was on disk.
    if (_dirty || !ref.mounted) return;
    state = AppSettings(
      colorMode: _colorMode(prefs.getString(_kColorMode)),
      fontSize: _fontSize(prefs.getString(_kFontSize)),
      contentWidth: _contentWidth(prefs.getString(_kContentWidth)),
      openLinkMode: _openLinkMode(prefs.getString(_kOpenLinkMode)),
      autoCollapseReplies: prefs.getBool(_kAutoCollapse) ?? true,
      hapticsEnabled: prefs.getBool(_kHaptics) ?? true,
      pushEnabled: prefs.getBool(_kPush) ?? true,
      replySort: _replySort(prefs.getString(_kReplySort)),
    );
  }

  Future<void> setColorMode(Mv2ColorMode mode) async {
    _dirty = true;
    state = state.copyWith(colorMode: mode);
    await _save((p) => p.setString(_kColorMode, mode.name));
  }

  Future<void> setFontSize(Mv2FontSize size) async {
    _dirty = true;
    state = state.copyWith(fontSize: size);
    await _save((p) => p.setString(_kFontSize, size.name));
  }

  Future<void> setContentWidth(Mv2ContentWidth width) async {
    _dirty = true;
    state = state.copyWith(contentWidth: width);
    await _save((p) => p.setString(_kContentWidth, width.name));
  }

  Future<void> setOpenLinkMode(Mv2LinkOpenMode mode) async {
    _dirty = true;
    state = state.copyWith(openLinkMode: mode);
    await _save((p) => p.setString(_kOpenLinkMode, mode.name));
  }

  Future<void> setAutoCollapseReplies(bool value) async {
    _dirty = true;
    state = state.copyWith(autoCollapseReplies: value);
    await _save((p) => p.setBool(_kAutoCollapse, value));
  }

  Future<void> setHapticsEnabled(bool value) async {
    _dirty = true;
    state = state.copyWith(hapticsEnabled: value);
    await _save((p) => p.setBool(_kHaptics, value));
  }

  Future<void> setPushEnabled(bool value) async {
    _dirty = true;
    state = state.copyWith(pushEnabled: value);
    await _save((p) => p.setBool(_kPush, value));
  }

  Future<void> setReplySort(Mv2ReplySort sort) async {
    _dirty = true;
    state = state.copyWith(replySort: sort);
    await _save((p) => p.setString(_kReplySort, sort.name));
  }

  Future<void> _save(Future<void> Function(SharedPreferences) op) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await op(prefs);
  }

  Mv2ColorMode _colorMode(String? raw) => Mv2ColorMode.values.firstWhere(
    (m) => m.name == raw,
    orElse: () => Mv2ColorMode.system,
  );

  Mv2FontSize _fontSize(String? raw) => Mv2FontSize.values.firstWhere(
    (m) => m.name == raw,
    orElse: () => Mv2FontSize.medium,
  );

  Mv2ContentWidth _contentWidth(String? raw) => Mv2ContentWidth.values
      .firstWhere((m) => m.name == raw, orElse: () => Mv2ContentWidth.narrow);

  Mv2LinkOpenMode _openLinkMode(String? raw) => Mv2LinkOpenMode.values
      .firstWhere((m) => m.name == raw, orElse: () => Mv2LinkOpenMode.reader);

  Mv2ReplySort _replySort(String? raw) => Mv2ReplySort.values.firstWhere(
    (Mv2ReplySort sort) => sort.name == raw,
    orElse: () => Mv2ReplySort.time,
  );
}

/// Pixel cap for the content column under the active 内容宽度 preference.
///
/// Reading lists constrain their column to this value on wide viewports.
final contentMaxWidthProvider = Provider<double>(
  (ref) => ref.watch(settingsProvider).contentWidth.maxWidth,
);

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

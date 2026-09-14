import '../../settings/application/settings_controller.dart';

/// The two surfaces the reader page can show for one loaded page.
///
/// `original` is the untouched page in the live [WebView]; `reader` is the
/// native MV2-rendered article. The persisted [Mv2LinkOpenMode] only picks the
/// starting value — the in-page switch overrides it for the visit.
enum ReaderMode {
  reader('阅读模式'),
  original('原文模式');

  const ReaderMode(this.label);

  final String label;

  /// Route query value used by `/reader?url=…&mode=…`.
  String get queryValue => name;
}

/// Resolves the reader's starting mode from the route query and the persisted
/// preference.
///
/// The explicit `?mode=` wins so an in-article link can open a specific mode;
/// otherwise the 外链打开方式 setting decides, and [Mv2LinkOpenMode.browser]
/// (which never reaches this page) falls back to reader mode.
ReaderMode initialReaderMode({
  String? queryMode,
  required Mv2LinkOpenMode setting,
}) {
  if (queryMode != null) {
    for (final ReaderMode mode in ReaderMode.values) {
      if (mode.queryValue == queryMode) return mode;
    }
  }
  return setting == Mv2LinkOpenMode.original
      ? ReaderMode.original
      : ReaderMode.reader;
}

/// Builds the `/reader` location for [url], optionally pinning the starting
/// [mode].
///
/// [url] is plain (not pre-encoded); [Uri] does the query encoding so an URL
/// containing `&`/`#`/spaces survives the round-trip.
String readerRoute(String url, {ReaderMode? mode}) {
  return Uri(
    path: '/reader',
    queryParameters: <String, String>{
      'url': url,
      if (mode != null) 'mode': mode.queryValue,
    },
  ).toString();
}

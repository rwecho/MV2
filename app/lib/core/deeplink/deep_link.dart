/// Maps an incoming link onto an in-app route (`docs/02` §Deep Link).
///
/// Two sources feed this:
///
/// * the custom scheme the app registers — `mv2://topic/123`,
///   `mv2://node/python`, `mv2://member/livid`, `mv2://login`;
/// * V2EX web URLs people paste or share — `https://www.v2ex.com/t/123#reply4`.
///
/// A `https://www.v2ex.com/...` link **cannot launch the app**: iOS Universal
/// Links / Android App Links need an `apple-app-site-association` /
/// `assetlinks.json` on that domain, and v2ex.com is not ours. Those URLs are
/// still useful once they reach the app (clipboard detection), so they parse
/// here too.
abstract final class Mv2DeepLink {
  /// Matches a bare URL inside shared text ("看看这个 https://… 挺好").
  static final RegExp _urlPattern = RegExp(
    r'(mv2://[^\s]+|https?://[^\s]+)',
    caseSensitive: false,
  );

  static const Set<String> _v2exHosts = <String>{
    'v2ex.com',
    'www.v2ex.com',
    'm.v2ex.com',
  };

  /// The first URL inside [text], or `null`.
  static String? urlIn(String? text) {
    if (text == null) return null;
    return _urlPattern.firstMatch(text.trim())?.group(0);
  }

  /// The in-app route for [raw], or `null` when the link is not ours.
  static String? routeFor(String? raw) {
    final url = urlIn(raw);
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    if (uri.scheme == 'mv2') return _customSchemeRoute(uri);
    // A bare `www.v2ex.com/t/123` (no scheme) parses with an empty scheme.
    if (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme.isEmpty) {
      if (!_v2exHosts.contains(uri.host.toLowerCase())) return null;
      return _webRoute(uri);
    }
    return null;
  }

  /// `mv2://topic/123` → `/topic/123`; also accepts the web-ish `mv2://t/123`.
  static String? _customSchemeRoute(Uri uri) {
    // `mv2://topic/123` puts `topic` in host; `mv2:///topic/123` leaves it in
    // the path, so normalise both shapes into one segment list.
    final segments = <String>[
      if (uri.host.isNotEmpty) uri.host,
      ...uri.pathSegments.where((segment) => segment.isNotEmpty),
    ];
    if (segments.isEmpty) return null;
    final head = segments.first.toLowerCase();
    final rest = segments.skip(1).toList();
    final id = rest.isEmpty ? null : rest.first;

    switch (head) {
      case 'topic':
      case 't':
        return id == null ? null : '/topic/$id';
      case 'node':
      case 'go':
        return id == null ? null : '/node/${Uri.encodeComponent(id)}';
      case 'member':
      case 'u':
        return id == null ? null : '/member/${Uri.encodeComponent(id)}';
      case 'login':
        return '/login';
      default:
        return null;
    }
  }

  /// V2EX web URL → route, mirroring `Mv2RichText.internalRoute`.
  static String? _webRoute(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    switch (segments.first) {
      case 't':
        if (segments.length < 2) return null;
        final id = segments[1];
        if (int.tryParse(id) == null) return null;
        // `/t/123#reply4` carries a floor; keep it so the page can jump there.
        final floor = RegExp(
          r'reply(\d+)',
        ).firstMatch(uri.fragment)?.group(1);
        return floor == null ? '/topic/$id' : '/topic/$id?floor=$floor';
      case 'go':
        if (segments.length < 2) return null;
        return '/node/${Uri.encodeComponent(segments[1])}';
      case 'member':
        if (segments.length < 2) return null;
        return '/member/${Uri.encodeComponent(segments[1])}';
      default:
        return null;
    }
  }
}

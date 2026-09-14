import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'reader_article.dart';

/// Path of the bundled Mozilla `@mozilla/readability@0.6.0` build.
const String readabilityAssetPath = 'assets/vendor/readability.js';

/// The snippet evaluated in the page after [readabilityAssetPath] is injected.
///
/// Runs Readability against a clone of the live DOM and returns a JSON string.
/// It never throws into Dart: every failure path is reported as
/// `{"ok":false,...}`, which [decodeReaderResult] maps to `null`.
const String readabilityExtractJs = '''
(function () {
  try {
    var doc = document.cloneNode(true);
    var r = new Readability(doc).parse();
    if (!r) return JSON.stringify({ok: false});
    return JSON.stringify({
      ok: true,
      title: r.title,
      byline: r.byline,
      siteName: r.siteName,
      excerpt: r.excerpt,
      content: r.content,
      textLength: (r.textContent || '').length
    });
  } catch (e) {
    return JSON.stringify({ok: false, error: String(e)});
  }
})()
''';

/// Drives a live [WebViewController] through one extraction pass.
///
/// The controller is owned by the reader page and reused across mode switches,
/// so the page is never reloaded just to extract. Readability rewrites relative
/// `src`/`href` to absolute URLs before returning `content`, so no post-hoc URL
/// fixing is done here.
class ReaderExtractor {
  ReaderExtractor(this._controller, this._readabilitySource);

  final WebViewController _controller;
  final String _readabilitySource;

  /// Injects Readability and parses the current document.
  ///
  /// Returns `null` when Readability declines the page, when the payload is
  /// malformed, or when the platform channel throws. The caller owns the
  /// timeout; this future has no deadline of its own.
  Future<ReaderArticle?> extract(String sourceUrl) async {
    await _controller.runJavaScript(_readabilitySource);
    final raw = await _controller.runJavaScriptReturningResult(
      readabilityExtractJs,
    );
    return decodeReaderResult(normalizeJsResult(raw), sourceUrl: sourceUrl);
  }
}

/// The bundled Readability source, loaded once per app run.
final readabilitySourceProvider = FutureProvider<String>(
  (ref) => rootBundle.loadString(readabilityAssetPath),
);

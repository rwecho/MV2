import 'package:html/dom.dart';

import '../../shared/models/publish_form.dart';
import 'html_dom.dart';

/// Scrapes V2EX's topic form (`/new` or `/new/{node}`).
///
/// The page is login-only: an anonymous session is answered with `302 →
/// /signin` (the client never follows redirects, so `RemoteV2exApi` turns that
/// into an `AuthFailure` before this parser runs). The only piece the client
/// cannot synthesise is the session `once` CSRF token; the node picker is
/// filled from `/api/nodes/s2.json`, and any `<select>` the page renders is
/// kept as a fallback.
abstract final class PublishParser {
  /// Returns `null` when the markup has no usable `once` — i.e. the response is
  /// not the topic form (structure changed, or a locked account page).
  static V2TopicForm? parseForm(String html, {String? pathNode}) {
    final document = parseHtmlDocument(html);
    final root =
        document.querySelector('div#Wrapper') ?? document.documentElement;
    if (root == null) return null;

    final once =
        root.attrOf('input#once', 'value') ??
        root.attrOf('input[name="once"]', 'value');
    if (once == null) return null;

    final select = root.querySelector('select[name="node_name"]');
    final options = <V2NodeOption>[];
    if (select != null) {
      for (final option in select.querySelectorAll('option')) {
        final name = cleanText(option.attributes['value'] ?? option.text);
        final title = cleanText(option.text);
        if (name == null || title == null || name.isEmpty) continue;
        options.add(V2NodeOption(name: name, title: title));
      }
    }

    return V2TopicForm(
      once: once,
      defaultNode: pathNode ?? _selectedNode(select, root),
      nodeOptions: options,
    );
  }

  /// `POST /new` rejections arrive as a `200` with the usual `Problem` block.
  static List<String> parseErrors(String html) => parseProblemList(html);

  /// `302 → /t/123456` after a successful publish; `null` when the redirect is
  /// anything else (e.g. an anti-flood interstitial).
  static int? parseTopicId(String? location) {
    if (location == null) return null;
    final match = RegExp(r'/t/(\d+)').firstMatch(location);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Heuristic: the server re-rendered the `/new` form instead of accepting the
  /// POST, without giving us a `Problem`.
  ///
  /// V2EX answers a rejected write with `302` (success) or `200` + `Problem`.
  /// A `200` that hands the *form* back — `once` input plus the editor fields —
  /// and explains nothing is the signature of a token the session no longer
  /// accepts ([stale once] handling, `docs/12` §4: "写操作前若缺失/过期则重新
  /// 拉页面"). The phrasing of the interstitial is not documented and was not
  /// captured live, so this deliberately keys off structure rather than
  /// guessing a Chinese literal, which could swallow a real error message.
  static bool isStaleToken(String html) {
    final document = parseHtmlDocument(html);
    final root =
        document.querySelector('div#Wrapper') ?? document.documentElement;
    if (root == null) return false;
    // A real rejection always explains itself; never treat it as a stale token.
    if (root.querySelector('div.problem li') != null) return false;

    final hasOnce =
        root.querySelector('input#once') != null ||
        root.querySelector('input[name="once"]') != null;
    if (!hasOnce) return false;

    final reRenderedForm =
        root.querySelector('form[action="/new"]') != null ||
        root.querySelector('textarea[name="content"]') != null ||
        root.querySelector('input[name="title"]') != null;
    return reRenderedForm;
  }

  static String? _selectedNode(Element? select, Element root) {
    final fromSelect = select
        ?.querySelector('option[selected]')
        ?.attributes['value'];
    if (fromSelect != null && fromSelect.trim().isNotEmpty) {
      return fromSelect.trim();
    }
    // The mobile form may carry the choice in a hidden input instead of a
    // select, or mark the active node link (`div#nodes a.node.active`).
    return root.attrOf('input[name="node_name"]', 'value') ??
        _nodeKeyFromHref(root.attrOf('a.node.selected', 'href')) ??
        _nodeKeyFromHref(
          root.attrOf('a[href*="/go/"][class*="selected"]', 'href'),
        );
  }

  static String? _nodeKeyFromHref(String? href) {
    if (href == null) return null;
    final match = RegExp(r'/go/([^/?#]+)').firstMatch(href);
    return match?.group(1);
  }
}

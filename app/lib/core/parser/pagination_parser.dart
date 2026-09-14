import 'package:html/dom.dart';

import '../../shared/models/topic_detail.dart';
import 'html_dom.dart';

/// Reads V2EX's pager.
///
/// Live markup (2026-09-11) is shared by topic pages, node pages, tag pages,
/// `/my/*` and notifications:
///
/// ```html
/// <div class="cell ps_container">
///   <table><tr><td width="92%">
///     <a href="?p=1" class="page_current">1</a>
///     <a href="?p=2" class="page_normal">2</a>
///     <input type="number" class="page_input" value="1" min="1" max="2">
///   </td></tr></table>
/// </div>
/// ```
///
/// The C# reference implementation used `span.page_current` plus positional
/// `preceding-sibling::div` — the site has since changed, so this reads the
/// explicit classes instead.
V2Pagination parsePagination(Element root) {
  final current =
      parseIntOrNull(root.querySelector('a.page_current')?.text) ?? 1;

  var maximum = current;
  for (final anchor in root.querySelectorAll('a.page_normal')) {
    final value = parseIntOrNull(anchor.text);
    if (value != null && value > maximum) maximum = value;
  }

  // Some pages (notifications) only expose `<input class="page_input">`.
  final input = root.querySelector('input.page_input');
  final fromInput = parseIntOrNull(input?.attributes['max']);
  if (fromInput != null && fromInput > maximum) maximum = fromInput;
  final currentInput = parseIntOrNull(input?.attributes['value']);
  if (currentInput != null && currentInput > current) maximum = currentInput;

  return V2Pagination(current: current, maximum: maximum < 1 ? 1 : maximum);
}

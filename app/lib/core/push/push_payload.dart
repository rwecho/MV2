import '../deeplink/deep_link.dart';

/// Turns an FCM `data` payload into an in-app route.
///
/// The push worker (`cloudflare/src/index.ts`) sends
/// `{link, notificationId, topicId?}`; `topicId` is only present when the
/// notification's link was a `/t/{id}` URL. Anything the worker cannot express
/// as a topic — a `/member/…` or `/go/…` link — falls back to the general
/// [Mv2DeepLink] parser, which also understands the relative `/t/123#reply4`
/// shape.
abstract final class Mv2PushPayload {
  static final RegExp _topicPath = RegExp(r'/t/(\d+)');
  static final RegExp _floor = RegExp(r'reply(\d+)');

  /// `/topic/123` or `/topic/123?floor=4`, matching what a `#reply4` link
  /// means on the website. `null` when the payload carries no usable target.
  static String? routeFor(Map<String, Object?> data) {
    final link = _string(data['link']);
    final declared = _string(data['topicId']);

    final id = (declared != null && int.tryParse(declared) != null)
        ? declared
        : (link == null ? null : _topicPath.firstMatch(link)?.group(1));

    if (id == null) {
      // The feed can also point at `/go/…` or `/member/…`; those arrive as
      // relative paths, which the deep-link parser only understands once they
      // look like the web URL it was written for.
      final absolute = link != null && link.startsWith('/')
          ? 'https://www.v2ex.com$link'
          : link;
      return Mv2DeepLink.routeFor(absolute);
    }

    final floor = link == null
        ? null
        : _floor.firstMatch(link)?.group(1);
    return floor == null ? '/topic/$id' : '/topic/$id?floor=$floor';
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

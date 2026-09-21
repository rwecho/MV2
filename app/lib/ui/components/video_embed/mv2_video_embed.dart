import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// A video link recognized in post/reply content (`docs/06` → 视频嵌入).
///
/// V2EX renders video links (exe-hub Posts, Bilibili, YouTube) as ordinary
/// `<a>` tags — the web's inline players are JS/iframe constructs that never
/// reach the server-rendered HTML we parse. [matchVideoEmbed] upgrades those
/// anchors to [Mv2VideoEmbedCard]s; playback happens in the in-app WebView
/// player page, which follows each provider's official embed page and is
/// therefore immune to their internal player changes.
class Mv2VideoEmbed {
  const Mv2VideoEmbed({
    required this.originalUrl,
    required this.playUrl,
    required this.provider,
    this.needsRedirectResolution = false,
  });

  /// The link as the author wrote it — shown in the card and used as the
  /// fallback when redirect resolution fails.
  final String originalUrl;

  /// What the WebView loads.
  final Uri playUrl;

  /// `hub` | `bilibili` | `youtube` — badge label and analytics dimension.
  final String provider;

  /// Short links (`b23.tv`) hide the real video id behind a redirect: the
  /// player page must call [resolveVideoRedirect] and swap in the clean
  /// embed URL before loading.
  final bool needsRedirectResolution;
}

/// Recognizes a supported video link, or returns `null` for anything else.
///
/// Anchors that match are pulled out of the text flow by `Mv2RichText` and
/// rendered as a block video card, the same upgrade path a linked image takes.
Mv2VideoEmbed? matchVideoEmbed(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final host = uri.host.toLowerCase();

  // exe-hub Post: `hub.v2core.com/p/<64 hex>` — played as-is; the page is the
  // player (Livid's video service, `v2ex.com/t/1243480`).
  if (host == 'hub.v2core.com') {
    if (!RegExp(r'^/p/[0-9a-fA-F]{64}/?$').hasMatch(uri.path)) return null;
    return Mv2VideoEmbed(
      originalUrl: url,
      playUrl: uri,
      provider: 'hub',
    );
  }

  // Bilibili. The web player embed (`player.bilibili.com/player.html`) is the
  // clean surface: no page chrome, no login wall.
  if (host == 'b23.tv' || host == 'www.b23.tv') {
    // Short link: the BV id is behind a redirect, resolved at tap time.
    if (uri.pathSegments.isEmpty) return null;
    return Mv2VideoEmbed(
      originalUrl: url,
      playUrl: uri,
      provider: 'bilibili',
      needsRedirectResolution: true,
    );
  }
  if (host == 'bilibili.com' || host == 'www.bilibili.com' || host == 'm.bilibili.com') {
    final play = bilibiliPlayerUrl(uri);
    if (play == null) return null;
    return Mv2VideoEmbed(originalUrl: url, playUrl: play, provider: 'bilibili');
  }

  // YouTube's official embed surface.
  if (host == 'youtube.com' || host == 'www.youtube.com' || host == 'm.youtube.com') {
    if (uri.path == '/watch') {
      final id = uri.queryParameters['v'];
      if (id == null || !isYouTubeId(id)) return null;
      return Mv2VideoEmbed(originalUrl: url, playUrl: youtubeEmbedUrl(id), provider: 'youtube');
    }
    if (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'shorts') {
      final id = uri.pathSegments[1];
      if (!isYouTubeId(id)) return null;
      return Mv2VideoEmbed(originalUrl: url, playUrl: youtubeEmbedUrl(id), provider: 'youtube');
    }
    return null;
  }
  if (host == 'youtu.be') {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || !isYouTubeId(id)) return null;
    return Mv2VideoEmbed(originalUrl: url, playUrl: youtubeEmbedUrl(id), provider: 'youtube');
  }

  return null;
}

/// The Bilibili embed player URL for a `/video/…` page link, or `null` when
/// the path is not a video (space, search, festival pages, …).
@visibleForTesting
Uri? bilibiliPlayerUrl(Uri uri) {
  final bv = RegExp(r'^/video/(BV[0-9A-Za-z]{10})(?:[/?]|$)').firstMatch(uri.path);
  if (bv != null) {
    final page = uri.queryParameters['p'];
    return Uri.https('player.bilibili.com', '/player.html', <String, String>{
      'bvid': bv.group(1)!,
      'page': ?page,
    });
  }
  // Legacy `av` numbers still circulate; the player takes `aid`.
  final av = RegExp(r'^/video/av(\d+)(?:[/?]|$)').firstMatch(uri.path);
  if (av != null) {
    return Uri.https('player.bilibili.com', '/player.html', <String, String>{
      'aid': av.group(1)!,
    });
  }
  return null;
}

/// Extracts the `BV…` id from a landed Bilibili video URL, or `null`.
String? bilibiliBvidFromUrl(Uri uri) {
  return RegExp(r'^/video/(BV[0-9A-Za-z]{10})(?:[/?]|$)')
      .firstMatch(uri.path)
      ?.group(1);
}

Uri youtubeEmbedUrl(String id) => Uri.https('www.youtube-nocookie.com', '/embed/$id');

/// YouTube video ids are 11 chars of `[A-Za-z0-9_-]`; exact length keeps
/// ordinary paths from matching.
@visibleForTesting
bool isYouTubeId(String id) => RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id);

/// Resolves a short link (`b23.tv`) to its landing URL by following manual
/// HEAD redirects.
///
/// External hosts — deliberately NOT routed through [Mv2HttpClient]'s pacer:
/// the 350ms anti-flood gap is a v2ex.com courtesy, and a redirect chain here
/// sits behind the user's own tap. Returns `null` when the chain cannot be
/// resolved within [maxHops] (the caller then loads the short link directly).
Future<Uri?> resolveVideoRedirect(
  Uri url, {
  int maxHops = 5,
  @visibleForTesting LocationFetcher? fetchLocation,
}) async {
  if (!url.host.endsWith('b23.tv')) return url;
  var current = url;
  final follow = fetchLocation ?? headLocation;
  for (var hop = 0; hop < maxHops; hop++) {
    final (status, location) = await follow(current);
    if (location == null || status < 300 || status >= 400) return current;
    final next = current.resolveUri(location);
    if (!next.host.endsWith('b23.tv')) return next;
    current = next;
  }
  return null;
}

/// `GET` result as (status, Location) — a record so tests can stub it.
@visibleForTesting
typedef LocationFetcher = Future<(int, Uri?)> Function(Uri url);

@visibleForTesting
Future<(int, Uri?)> headLocation(Uri url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6);
  try {
    final request = await client.headUrl(url);
    final response = await request.close();
    await response.drain<void>();
    final location = response.headers.value(HttpHeaders.locationHeader);
    return (response.statusCode, location == null ? null : Uri.parse(location));
  } finally {
    client.close(force: true);
  }
}

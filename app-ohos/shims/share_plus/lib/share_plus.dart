import 'dart:ui' show Rect;

/// HarmonyOS (ohos) shim for `share_plus`.
///
/// The community `share_plus_ohos` port exists but pulls a third-party ArkTS
/// plugin into the HAP; MV2's stated ohos strategy is "copy the link to the
/// clipboard and tell the user". Both mainline call sites
/// (`reader_page._share`, `topic_detail_page._shareTopic`) already wrap
/// `SharePlus.instance.share(...)` in a `try/catch` that copies the link and
/// shows a SnackBar, so making [share] throw reproduces exactly that behaviour
/// without touching shared page code.
class SharePlus {
  SharePlus._();

  static final SharePlus instance = SharePlus._();

  static const bool isSupported = false;

  Future<ShareResult> share(ShareParams params) async {
    throw UnsupportedError(
      'share_plus is not available on HarmonyOS; the caller falls back to the '
      'clipboard.',
    );
  }
}

class ShareParams {
  const ShareParams({
    this.text,
    this.subject,
    this.title,
    this.uri,
    this.sharePositionOrigin,
    this.files,
  });

  final String? text;
  final String? subject;
  final String? title;
  final Uri? uri;
  final Rect? sharePositionOrigin;
  final List<Object>? files;
}

enum ShareResultStatus { success, dismissed, unavailable }

class ShareResult {
  const ShareResult(this.status, this.raw);

  final ShareResultStatus status;
  final String raw;

  static const ShareResult unavailable = ShareResult(
    ShareResultStatus.unavailable,
    '',
  );
}

/// HarmonyOS (ohos) shim for `app_links`.
///
/// `app_links` 7.2.1 requires Dart ^3.12.0 (the ohos fork ships 3.11.5), and the
/// only community HarmonyOS port (`app_links_ohos` 0.2.0) registers a native
/// ArkTS plugin but no `AppLinksPlatform` Dart implementation, so it cannot
/// drive the mainline `app_links` API anyway.
///
/// This shim keeps `Mv2DeepLinkListener` compiling and running with an empty
/// link stream. Consequences on ohos:
///   * warm `mv2://` / `https://www.v2ex.com/...` app-to-app links do not
///     arrive (the OS would need an ArkTS `want` handler registered by a real
///     plugin);
///   * the clipboard pasteboard fallback in `Mv2DeepLinkListener` — the path
///     that matters for links shared from a browser — is unaffected, because it
///     only uses `Clipboard.getData`.
class AppLinks {
  AppLinks();

  /// Always empty on the ohos variant.
  static const bool isSupported = false;

  Stream<Uri> get uriLinkStream => const Stream<Uri>.empty();

  Future<Uri?> getInitialLink() async => null;
}

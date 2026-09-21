import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../design_system/tokens/mv2_spacing.dart';
import 'mv2_video_embed.dart';

/// Opens the in-app full-screen video player for a recognized video link.
///
/// The WebView loads each provider's official embed/play surface, so playback
/// tracks whatever the provider serves today (no fragile direct-media
/// extraction). Returns when the page is closed.
Future<void> showMv2VideoPlayer(BuildContext context, Mv2VideoEmbed embed) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    // Fullscreen dialog: the page is a player surface, and the platform back
    // gesture / button closes it like a sheet.
    MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => Mv2VideoPlayerPage(embed: embed)),
  );
}

/// Full-screen WebView player (`docs/06` → 视频嵌入).
///
/// Short links (`b23.tv`) resolve their redirect first so the WebView can load
/// the clean `player.bilibili.com` embed instead of the whole mobile page; on
/// resolution failure it falls back to loading the original link as-is.
class Mv2VideoPlayerPage extends StatefulWidget {
  const Mv2VideoPlayerPage({super.key, required this.embed});

  final Mv2VideoEmbed embed;

  @override
  State<Mv2VideoPlayerPage> createState() => _Mv2VideoPlayerPageState();
}

class _Mv2VideoPlayerPageState extends State<Mv2VideoPlayerPage> {
  late final Future<Uri> _playUrl = _resolve();
  int _progress = 0;

  Future<Uri> _resolve() async {
    if (!widget.embed.needsRedirectResolution) return widget.embed.playUrl;
    try {
      final landed = await resolveVideoRedirect(Uri.parse(widget.embed.originalUrl));
      if (landed == null) return widget.embed.playUrl;
      final bvid = bilibiliBvidFromUrl(landed);
      if (bvid == null) return landed;
      return Uri.https('player.bilibili.com', '/player.html', <String, String>{
        'bvid': bvid,
      });
    } on Exception {
      // Network trouble resolving the short link — the original URL still
      // lands on a playable page inside the WebView.
      return widget.embed.playUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
                const Spacer(),
              ],
            ),
            Expanded(
              child: FutureBuilder<Uri>(
                future: _playUrl,
                builder: (context, snapshot) {
                  final url = snapshot.data;
                  if (url == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Stack(
                    children: <Widget>[
                      WebViewWidget(controller: _controller(url)),
                      if (_progress < 100)
                        const LinearProgressIndicator(minHeight: 2),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: Mv2Spacing.x2),
          ],
        ),
      ),
    );
  }

  WebViewController _controller(Uri url) {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _progress = progress);
          },
        ),
      )
      ..loadRequest(url);
  }
}

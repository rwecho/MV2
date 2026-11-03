import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../features/reader/application/open_external_url.dart';
import 'mv2_video_embed.dart';

Future<void> showMv2VideoPlayer(BuildContext context, Mv2VideoEmbed embed) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Mv2VideoPlayerPage(embed: embed),
    ),
  );
}

class Mv2VideoPlayerPage extends StatelessWidget {
  const Mv2VideoPlayerPage({super.key, required this.embed});
  final Mv2VideoEmbed embed;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text('视频'),
      actions: <Widget>[
        // Always available: YouTube may legitimately refuse in-app playback
        // (restricted or embed-disabled video), and the user must be able to
        // reach the original page without a dead end.
        IconButton(
          tooltip: '在浏览器中打开',
          onPressed: () => openExternalUrl(context, embed.originalUrl),
          icon: const Icon(Icons.open_in_new),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Mv2VideoSurface(embed: embed),
        ),
      ),
    ),
  );
}

/// Owns one controller for its lifetime; progress rebuilds must not reload it.
class Mv2VideoSurface extends StatefulWidget {
  const Mv2VideoSurface({super.key, required this.embed});
  final Mv2VideoEmbed embed;
  @override
  State<Mv2VideoSurface> createState() => _Mv2VideoSurfaceState();
}

class _Mv2VideoSurfaceState extends State<Mv2VideoSurface>
    with WidgetsBindingObserver {
  WebViewController? _controller;
  bool _failed = false;
  int _progress = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _failed = false;
      _progress = 0;
      _controller = null;
    });
    try {
      var url = widget.embed.playUrl;
      if (widget.embed.needsRedirectResolution) {
        try {
          final landed = await resolveVideoRedirect(
            Uri.parse(widget.embed.originalUrl),
          ).timeout(const Duration(seconds: 10));
          final player = landed == null ? null : bilibiliPlayerUrl(landed);
          if (player != null) url = player;
        } catch (error) {
          debugPrint(
            'Video redirect unresolved: ${error.runtimeType}; using web redirect',
          );
        }
      }
      if (!mounted || generation != _generation) return;
      url = url.replace(
        queryParameters: {
          ...url.queryParameters,
          'autoplay': '0',
          'playsinline': '1',
        },
      );
      final params = WebViewPlatform.instance is WebKitWebViewPlatform
          ? WebKitWebViewControllerCreationParams(
              allowsInlineMediaPlayback: true,
            )
          : const PlatformWebViewControllerCreationParams();
      final controller = WebViewController.fromPlatformCreationParams(params);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.black);
      // Real WebView identity on purpose: masking the user agent to get past
      // YouTube's player checks ("152-4") is what Play's Device and Network
      // Abuse policy treats as circumventing another service's safeguards.
      // If YouTube refuses this WebView, the failure state below offers
      // "打开原网页" instead of pretending to be Safari.
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted && generation == _generation) {
              setState(() => _progress = value);
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true &&
                mounted &&
                generation == _generation) {
              debugPrint(
                'Video main-frame error: ${error.errorCode} ${error.errorType} ${error.description}',
              );
              setState(() => _failed = true);
            }
          },
          onNavigationRequest: (request) {
            final next = Uri.tryParse(request.url);
            if (next == null ||
                (next.scheme != 'https' && request.url != 'about:blank')) {
              return NavigationDecision.prevent;
            }
            if (request.isMainFrame &&
                widget.embed.provider == 'bilibili' &&
                const {
                  'www.bilibili.com',
                  'm.bilibili.com',
                  'bilibili.com',
                }.contains(next.host)) {
              final player = bilibiliPlayerUrl(next);
              if (player != null) {
                controller.loadRequest(
                  player.replace(
                    queryParameters: {
                      ...player.queryParameters,
                      'autoplay': '0',
                      'playsinline': '1',
                    },
                  ),
                );
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
        ),
      );
      // YouTube rejects a bare main-frame embed (error 153) because it has no
      // referrer context; the host page restores the iframe semantics and is
      // loaded from our own https origin (never youtube.com).
      if (widget.embed.provider == 'youtube') {
        await controller.loadHtmlString(
          youtubeHostPage(url),
          baseUrl: youtubeEmbedOrigin,
        );
      } else {
        await controller.loadRequest(url);
      }
      if (mounted && generation == _generation) {
        setState(() => _controller = controller);
      }
    } catch (error, stack) {
      debugPrint('Video initialization failed: $error\n$stack');
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  void _pause() {
    _controller
        ?.runJavaScript(
          "document.querySelectorAll('video,audio').forEach(function(v){v.pause();});",
        )
        .catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pause();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('视频加载失败', style: TextStyle(color: Colors.white)),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton(onPressed: _load, child: const Text('重试')),
                  TextButton(
                    onPressed: () =>
                        openExternalUrl(context, widget.embed.originalUrl),
                    child: const Text('打开原网页'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          if (_controller != null)
            Positioned.fill(child: WebViewWidget(controller: _controller!)),
          if (_progress < 100)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}

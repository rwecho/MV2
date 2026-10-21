import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_spacing.dart';
import '../utils/media_presentation.dart';

/// Opens the MV2 full-screen image browser.
///
/// Every image in the same post/reply is passed as one gallery, so a swipe moves
/// between them exactly like the Weibo viewer. Returns when the viewer closes.
Future<void> showMv2ImageViewer(
  BuildContext context, {
  required List<String> images,
  int initialIndex = 0,
}) async {
  final gallery = images
      .where((url) => url.trim().isNotEmpty)
      .toList(growable: false);
  if (gallery.isEmpty) return;

  final index = initialIndex < 0
      ? 0
      : (initialIndex >= gallery.length ? gallery.length - 1 : initialIndex);

  final navigator = Navigator.of(context, rootNavigator: true);
  final releaseChrome = Mv2MediaPresentation.acquire();
  final route = PageRouteBuilder<void>(
    // Not opaque: the page behind shows through while the viewer is dragged
    // down, and the fade owns the transition.
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, animation, secondaryAnimation) =>
        Mv2ImageViewer(images: gallery, initialIndex: index),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
  );
  try {
    await navigator.push<void>(route);
    await route.completed;
  } finally {
    releaseChrome();
  }
}

/// Full-screen image browser (`docs/06` → 图片浏览).
///
/// Weibo-style gestures: swipe horizontally to page, pinch or double-tap to
/// zoom, drag down to dismiss, tap to hide/show the chrome.
class Mv2ImageViewer extends StatefulWidget {
  const Mv2ImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  final List<String> images;
  final int initialIndex;

  @override
  State<Mv2ImageViewer> createState() => _Mv2ImageViewerState();
}

class _Mv2ImageViewerState extends State<Mv2ImageViewer> {
  /// Vertical distance that commits the dismiss.
  static const double _dismissDistance = 140;

  /// A fast enough flick dismisses even before [_dismissDistance] is reached.
  static const double _flingVelocity = 800;

  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  double _drag = 0;
  bool _zoomed = false;
  bool _chromeVisible = true;
  bool _saving = false;

  Future<void> _saveImage() async {
    if (_saving) return;
    final url = widget.images[_index];
    setState(() => _saving = true);
    String message;
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      await const MethodChannel('mv2/media')
          .invokeMethod<void>('saveImage', {'path': file.path});
      message = '已保存到相册';
    } on PlatformException catch (error) {
      message = error.code == 'photo_permission_denied'
          ? '请在系统设置中允许保存照片后重试'
          : '保存失败，请稍后重试';
    } catch (_) {
      message = '图片下载失败，请检查网络后重试';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 0 → not dragged, 1 → fully dismissed; drives the backdrop fade and shrink.
  double get _dismissProgress =>
      (_drag.abs() / (_dismissDistance * 2)).clamp(0.0, 1.0);

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() => _drag += details.delta.dy);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity?.abs() ?? 0;
    if (_drag.abs() >= _dismissDistance || velocity >= _flingVelocity) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _drag = 0);
  }

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  @override
  Widget build(BuildContext context) {
    final total = widget.images.length;
    final progress = _dismissProgress;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // While zoomed the InteractiveViewer owns the pan; otherwise a vertical
        // drag shrinks and dismisses the viewer.
        onVerticalDragUpdate: _zoomed ? null : _onDragUpdate,
        onVerticalDragEnd: _zoomed ? null : _onDragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(
              color: Colors.black.withValues(
                alpha: (1 - progress * 0.85).clamp(0.0, 1.0),
              ),
            ),
            Transform.translate(
              offset: Offset(0, _drag),
              child: Transform.scale(
                scale: 1 - progress * 0.2,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: total,
                  onPageChanged: (value) => setState(() {
                    _index = value;
                    _zoomed = false;
                  }),
                  itemBuilder: (context, index) => _ZoomableImage(
                    url: widget.images[index],
                    onZoomChanged: (value) => setState(() => _zoomed = value),
                    onTap: _toggleChrome,
                  ),
                ),
              ),
            ),
            _ViewerChrome(
              visible: _chromeVisible,
              index: _index,
              total: total,
              onClose: () => Navigator.of(context).maybePop(),
              saving: _saving,
              onSave: _saveImage,
            ),
          ],
        ),
      ),
    );
  }
}

/// One page: the image plus its own zoom transform.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.url,
    required this.onZoomChanged,
    required this.onTap,
  });

  final String url;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onTap;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  static const double _doubleTapScale = 2.5;
  static const double _zoomEpsilon = 1.01;

  final TransformationController _controller = TransformationController();
  Offset _doubleTapFocus = Offset.zero;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isZoomed => _controller.value.getMaxScaleOnAxis() > _zoomEpsilon;

  void _handleDoubleTap() {
    final next = _isZoomed
        ? Matrix4.identity()
        : _scaleAbout(_doubleTapFocus, _doubleTapScale);
    _controller.value = next;
    widget.onZoomChanged(next.getMaxScaleOnAxis() > _zoomEpsilon);
  }

  /// Scales about [focus] without the deprecated `Matrix4.translate`/`scale`
  /// helpers (which the analyzer flags on the current vector_math).
  static Matrix4 _scaleAbout(Offset focus, double scale) {
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, -focus.dx * (scale - 1))
      ..setEntry(1, 3, -focus.dy * (scale - 1));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTapFocus = details.localPosition,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 4,
        // Panning a zoomed image would otherwise swallow the horizontal paging
        // gesture, so pan is only enabled once the image is actually zoomed.
        panEnabled: _isZoomed,
        onInteractionEnd: (_) => widget.onZoomChanged(_isZoomed),
        child: Center(
          child: CachedNetworkImage(
            imageUrl: widget.url,
            fit: BoxFit.contain,
            progressIndicatorBuilder: (context, url, progress) => Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: progress.progress,
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
            ),
            errorWidget: (context, url, error) => const _BrokenImage(),
          ),
        ),
      ),
    );
  }
}

/// Close button + page counter; hidden when the chrome is toggled off.
class _ViewerChrome extends StatelessWidget {
  const _ViewerChrome({
    required this.visible,
    required this.index,
    required this.total,
    required this.onClose,
    required this.onSave,
    required this.saving,
  });

  final bool visible;
  final int index;
  final int total;
  final VoidCallback onClose;
  final VoidCallback onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(Mv2Spacing.x4),
                  child: FilledButton.icon(
                    onPressed: saving ? null : onSave,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download_rounded),
                    label: Text(saving ? '保存中…' : '保存到相册'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(Mv2Spacing.x2),
                  child: IconButton(
                    onPressed: onClose,
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
              if (total > 1)
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: Mv2Spacing.x3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Mv2Spacing.x3,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${index + 1} / $total',
                      style: context.text.metadata.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.broken_image_outlined,
          size: 40,
          color: Colors.white54,
        ),
        const SizedBox(height: Mv2Spacing.x2),
        Text(
          '图片加载失败',
          style: context.text.metadata.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

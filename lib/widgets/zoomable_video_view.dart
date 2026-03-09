import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ZoomableVideoView extends StatefulWidget {
  final RTCVideoRenderer renderer;
  final RTCVideoViewObjectFit objectFit;
  final double aspectRatio;
  final BorderRadius borderRadius;
  final double minScale;
  final double maxScale;
  final bool zoomEnabled;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onScrollLockChanged;

  const ZoomableVideoView({
    super.key,
    required this.renderer,
    required this.objectFit,
    required this.aspectRatio,
    required this.borderRadius,
    this.minScale = 1.0,
    this.maxScale = 4.0,
    this.zoomEnabled = true,
    this.onTap,
    this.onScrollLockChanged,
  });

  @override
  State<ZoomableVideoView> createState() => _ZoomableVideoViewState();
}

class _ZoomableVideoViewState extends State<ZoomableVideoView> {
  static const double _epsilon = 0.001;

  double _scale = 1.0;
  double _startScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  bool _isScrollLockActive = false;

  @override
  void initState() {
    super.initState();
    _scale = widget.minScale;
    _startScale = widget.minScale;
    _isScrollLockActive = _shouldLockScroll(_scale);
  }

  @override
  void didUpdateWidget(covariant ZoomableVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.zoomEnabled && oldWidget.zoomEnabled) {
      _scale = widget.minScale;
      _offset = Offset.zero;
    }
    if (widget.minScale != oldWidget.minScale && _scale < widget.minScale) {
      _scale = widget.minScale;
      _offset = Offset.zero;
    }
    if (widget.maxScale != oldWidget.maxScale && _scale > widget.maxScale) {
      _scale = widget.maxScale;
      _offset = Offset.zero;
    }
    _notifyScrollLockIfNeeded();
  }

  @override
  void dispose() {
    if (_isScrollLockActive) {
      _dispatchScrollLockChanged(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onScaleStart: widget.zoomEnabled
                  ? (details) {
                      _startScale = _scale;
                      _startOffset = _offset;
                      _startFocal = _toCentered(details.localFocalPoint, size);
                    }
                  : null,
              onScaleUpdate: widget.zoomEnabled
                  ? (details) {
                      final focal = _toCentered(details.localFocalPoint, size);

                      if (details.pointerCount > 1) {
                        final unclamped = _startScale * details.scale;
                        final nextScale = unclamped
                            .clamp(widget.minScale, widget.maxScale)
                            .toDouble();
                        final contentFocal =
                            (_startFocal - _startOffset) / _startScale;
                        final nextOffset = focal - (contentFocal * nextScale);

                        setState(() {
                          _scale = nextScale;
                          _offset = _clampOffset(nextOffset, size, nextScale);
                          if (_scale <= widget.minScale + _epsilon) {
                            _scale = widget.minScale;
                            _offset = Offset.zero;
                          }
                        });
                        _notifyScrollLockIfNeeded();
                        return;
                      }

                      if (_scale <= widget.minScale + _epsilon) return;

                      final delta = focal - _startFocal;
                      setState(() {
                        _offset = _clampOffset(
                          _startOffset + delta,
                          size,
                          _scale,
                        );
                      });
                      _notifyScrollLockIfNeeded();
                    }
                  : null,
              onScaleEnd: widget.zoomEnabled
                  ? (_) {
                      if (_scale <= widget.minScale + _epsilon) {
                        setState(() {
                          _scale = widget.minScale;
                          _offset = Offset.zero;
                        });
                      }
                      _notifyScrollLockIfNeeded();
                    }
                  : null,
              child: ClipRect(
                child: Transform.translate(
                  offset: _offset,
                  child: Transform.scale(
                    scale: _scale,
                    child: RTCVideoView(
                      widget.renderer,
                      objectFit: widget.objectFit,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Offset _toCentered(Offset local, Size size) {
    return Offset(local.dx - (size.width / 2), local.dy - (size.height / 2));
  }

  bool _shouldLockScroll(double scale) {
    return widget.zoomEnabled && scale > widget.minScale + _epsilon;
  }

  void _notifyScrollLockIfNeeded() {
    final shouldLock = _shouldLockScroll(_scale);
    if (_isScrollLockActive == shouldLock) return;
    _isScrollLockActive = shouldLock;
    _dispatchScrollLockChanged(shouldLock);
  }

  void _dispatchScrollLockChanged(bool shouldLock) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onScrollLockChanged?.call(shouldLock);
    });
  }

  Offset _clampOffset(Offset offset, Size size, double scale) {
    final maxDx = ((size.width * scale) - size.width) / 2;
    final maxDy = ((size.height * scale) - size.height) / 2;

    return Offset(
      offset.dx.clamp(-maxDx, maxDx).toDouble(),
      offset.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }
}

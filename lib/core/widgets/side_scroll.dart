import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A sideways scroller (tables, code) that keeps its own drags on a page
/// where a full-width swipe also listens, like the AI chat's drawer swipe.
///
/// That swipe sits above the page, so with a plain [SingleChildScrollView]
/// it sees every move first and wins the drag. This one claims a clearly
/// sideways drag after a few pixels, before the swipe's slop is reached,
/// but only when it can actually scroll that way: at the start, a swipe to
/// the right still opens the drawer, and a mostly vertical drag still
/// scrolls the chat.
class SideScroll extends StatefulWidget {
  const SideScroll({super.key, required this.child, this.controller, this.padding, this.scrollbar = false});

  final Widget child;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;

  /// Shows a [Scrollbar] while scrolling.
  final bool scrollbar;

  @override
  State<SideScroll> createState() => _SideScrollState();
}

class _SideScrollState extends State<SideScroll> {
  ScrollController? _own;
  ScrollController get _controller => widget.controller ?? (_own ??= ScrollController());
  Drag? _drag;

  @override
  void dispose() {
    _drag?.cancel();
    _own?.dispose();
    super.dispose();
  }

  /// Whether a drag moving by [dx] (+ right, − left) has room to scroll.
  bool _canScroll(double dx) {
    if (!_controller.hasClients) return false;
    final p = _controller.position;
    if (!p.hasContentDimensions || p.maxScrollExtent <= p.minScrollExtent) return false;
    // The finger moving left brings in what is to the right.
    return dx < 0 ? p.pixels < p.maxScrollExtent - 0.5 : p.pixels > p.minScrollExtent + 0.5;
  }

  @override
  Widget build(BuildContext context) {
    // Its own drag recognizer is off (it could lose the race to a page-wide
    // swipe): every drag goes through the one below. Wheels still scroll.
    final view = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: const {}, scrollbars: false),
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: widget.padding,
        child: widget.child,
      ),
    );
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _EarlySideDrag: GestureRecognizerFactoryWithHandlers<_EarlySideDrag>(
          () => _EarlySideDrag(allow: _canScroll, debugOwner: this),
          (r) => r
            ..allow = _canScroll
            ..onStart = (d) {
              _drag = _controller.position.drag(d, () => _drag = null);
            }
            ..onUpdate = (d) {
              _drag?.update(d);
            }
            ..onEnd = (d) {
              _drag?.end(d);
              _drag = null;
            }
            ..onCancel = () {
              _drag?.cancel();
              _drag = null;
            },
        ),
      },
      child: widget.scrollbar ? Scrollbar(controller: _controller, child: view) : view,
    );
  }
}

/// A horizontal drag that decides within a few pixels: claimed at once when
/// sideways and [allow]ed, given up at once otherwise. A page-wide swipe
/// above it should wait longer (see [GestureSettingsScope]), or a fast first
/// move can carry it past its slop before this one gets to decide.
class _EarlySideDrag extends HorizontalDragGestureRecognizer {
  _EarlySideDrag({required this.allow, super.debugOwner});

  bool Function(double dx) allow;

  final Map<int, Offset> _origin = {};
  static const _decideAt = 6.0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _origin[event.pointer] = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    final from = _origin[event.pointer];
    if (from != null && event is PointerMoveEvent) {
      final d = event.position - from;
      if (d.distance >= _decideAt) {
        _origin.remove(event.pointer);
        if (d.dy.abs() >= d.dx.abs() || !allow(d.dx)) {
          resolvePointer(event.pointer, GestureDisposition.rejected);
          return;
        }
        // Ahead of the slop every other horizontal listener waits for.
        resolvePointer(event.pointer, GestureDisposition.accepted);
      }
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) _origin.remove(event.pointer);
    super.handleEvent(event);
  }

  @override
  void rejectGesture(int pointer) {
    _origin.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  String get debugDescription => 'early side drag';
}

/// [child] with its own gesture [settings] (null: the platform's), for
/// one part of a page. Only that one aspect of the [MediaQuery] changes, so
/// the rest of the page doesn't rebuild with it.
class GestureSettingsScope extends StatelessWidget {
  const GestureSettingsScope({super.key, required this.settings, required this.child});
  final DeviceGestureSettings? settings;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MediaQuery(data: MediaQuery.of(context).copyWith(gestureSettings: settings), child: child);
}

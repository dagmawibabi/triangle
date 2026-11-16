import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A horizontal drag that only claims the gesture when it starts the way
/// [allow] says (given the first clear sideways movement, +right / −left).
/// Anything else is rejected at once, so a drag the other way, or a mostly
/// vertical one, goes to whoever else is listening: a list, a pager, the
/// page's swipe-back.
class DirectionalDragRecognizer extends HorizontalDragGestureRecognizer {
  DirectionalDragRecognizer({required this.allow, super.debugOwner});

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
        if (d.dy.abs() > d.dx.abs() * 0.9 || !allow(d.dx)) {
          resolvePointer(event.pointer, GestureDisposition.rejected);
          return;
        }
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
  String get debugDescription => 'directional horizontal drag';
}

/// [child] with a [DirectionalDragRecognizer] around it.
class DirectionalDrag extends StatelessWidget {
  const DirectionalDrag({
    super.key,
    required this.allow,
    required this.child,
    this.onStart,
    this.onUpdate,
    this.onEnd,
    this.onCancel,
    this.behavior = HitTestBehavior.translucent,
  });

  final bool Function(double dx) allow;
  final GestureDragStartCallback? onStart;
  final GestureDragUpdateCallback? onUpdate;
  final GestureDragEndCallback? onEnd;
  final GestureDragCancelCallback? onCancel;
  final HitTestBehavior behavior;
  final Widget child;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: behavior,
    gestures: {
      DirectionalDragRecognizer: GestureRecognizerFactoryWithHandlers<DirectionalDragRecognizer>(
        () => DirectionalDragRecognizer(allow: allow, debugOwner: this),
        (r) => r
          ..allow = allow
          ..dragStartBehavior = DragStartBehavior.down
          ..onStart = onStart
          ..onUpdate = onUpdate
          ..onEnd = onEnd
          ..onCancel = onCancel,
      ),
    },
    child: child,
  );
}

/// Telegram's page motion: a new page slides in over the old one, which
/// drifts left and dims; and a swipe to the right from anywhere on a page
/// (not just its edge) drags it back off, following the finger.
///
/// Inner horizontal scrollers (folder pagers, carousels, swipe-to-reply)
/// sit deeper and win their own drags; ones built on
/// [DirectionalDragRecognizer] can hand rightward swipes back to this.
class SwipeBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const SwipeBackPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _SwipeBackTransition(route: route, animation: animation, secondary: secondaryAnimation, child: child);
}

class _SwipeBackTransition extends StatelessWidget {
  const _SwipeBackTransition({required this.route, required this.animation, required this.secondary, required this.child});
  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final Animation<double> secondary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gesture = route.navigator?.userGestureInProgressNotifier ?? ValueNotifier(false);
    return ValueListenableBuilder<bool>(
      valueListenable: gesture,
      builder: (context, dragging, _) {
        // Following a finger the motion is linear; otherwise it eases.
        final Animation<double> inAnim = dragging
            ? animation
            : CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        final Animation<double> outAnim = dragging
            ? secondary
            : CurvedAnimation(parent: secondary, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        final width = MediaQuery.sizeOf(context).width;
        return AnimatedBuilder(
          animation: Listenable.merge([inAnim, outAnim]),
          child: route.fullscreenDialog ? child : _SwipeBackDetector(route: route, child: child),
          builder: (context, page) {
            if (route.fullscreenDialog) {
              return Transform.translate(
                offset: Offset(0, (1 - inAnim.value) * MediaQuery.sizeOf(context).height),
                child: page,
              );
            }
            final inX = (1 - inAnim.value) * width;
            final outX = -outAnim.value * width * 0.28;
            final dim = outAnim.value;
            return Transform.translate(
              offset: Offset(inX + outX, 0),
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.32 * dim)),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: inAnim.value < 1
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35 * math.min(1, inAnim.value * 3)),
                              blurRadius: 18,
                              offset: const Offset(-4, 0),
                            ),
                          ]
                        : null,
                  ),
                  child: page,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SwipeBackDetector extends StatefulWidget {
  const _SwipeBackDetector({required this.route, required this.child});
  final PageRoute<dynamic> route;
  final Widget child;

  @override
  State<_SwipeBackDetector> createState() => _SwipeBackDetectorState();
}

class _SwipeBackDetectorState extends State<_SwipeBackDetector> {
  bool _active = false;

  PageRoute<dynamic> get _route => widget.route;

  // ignore: invalid_use_of_protected_member
  AnimationController? get _controller => _route.controller;

  bool get _enabled {
    final r = _route;
    final nav = r.navigator;
    if (nav == null || r.isFirst || !r.isCurrent) return false;
    if (r.willHandlePopInternally) return false;
    if (r.popDisposition == RoutePopDisposition.doNotPop) return false;
    if (r.fullscreenDialog) return false;
    if (r.animation?.status != AnimationStatus.completed) return false;
    if (r.secondaryAnimation?.status != AnimationStatus.dismissed) return false;
    if (nav.userGestureInProgress) return false;
    return true;
  }

  void _start(DragStartDetails _) {
    if (!_enabled) return;
    _active = true;
    _route.navigator!.didStartUserGesture();
  }

  void _update(DragUpdateDetails d) {
    if (!_active) return;
    final c = _controller;
    if (c == null) return;
    c.value -= (d.primaryDelta ?? d.delta.dx) / context.size!.width;
  }

  void _end(double velocity) {
    if (!_active) return;
    _active = false;
    final c = _controller;
    final nav = _route.navigator;
    if (c == null || nav == null) return;
    final v = velocity / context.size!.width;
    final pop = v > 1 ? true : (v < -1 ? false : c.value < 0.55);
    if (pop) {
      nav.pop();
    } else {
      c.animateTo(1, duration: Duration(milliseconds: (220 * (1 - c.value)).round().clamp(60, 220)), curve: Curves.easeOut);
    }
    if (c.isAnimating) {
      late final AnimationStatusListener done;
      done = (status) {
        if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
          nav.didStopUserGesture();
          c.removeStatusListener(done);
        }
      };
      c.addStatusListener(done);
    } else {
      nav.didStopUserGesture();
    }
  }

  @override
  void dispose() {
    if (_active) _route.navigator?.didStopUserGesture();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DirectionalDrag(
    allow: (dx) => dx > 0 && _enabled,
    onStart: _start,
    onUpdate: _update,
    onEnd: (d) => _end(d.primaryVelocity ?? d.velocity.pixelsPerSecond.dx),
    onCancel: () => _end(0),
    child: widget.child,
  );
}

/// A route that appears at once (switching between sibling chats from the
/// forum rail) but still slides away, and swipes back, like any page.
class InstantPageRoute<T> extends MaterialPageRoute<T> {
  InstantPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 280);
}

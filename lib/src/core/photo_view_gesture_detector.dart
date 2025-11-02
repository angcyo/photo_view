import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'photo_view_hit_corners.dart';

class PhotoViewGestureDetector extends StatelessWidget {
  const PhotoViewGestureDetector({
    Key? key,
    this.hitDetector,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.onDoubleTap,
    this.child,
    this.onTapUp,
    this.onTapDown,
    this.behavior,
  }) : super(key: key);

  final GestureDoubleTapCallback? onDoubleTap;
  final HitCornersDetector? hitDetector;

  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;

  final GestureTapUpCallback? onTapUp;
  final GestureTapDownCallback? onTapDown;

  final Widget? child;

  final HitTestBehavior? behavior;

  @override
  Widget build(BuildContext context) {
    final scope = PhotoViewGestureDetectorScope.of(context);

    final Axis? axis = scope?.axis;

    final Map<Type, GestureRecognizerFactory> gestures =
        <Type, GestureRecognizerFactory>{};

    if (onTapDown != null || onTapUp != null) {
      gestures[TapGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        () => TapGestureRecognizer(debugOwner: this),
        (TapGestureRecognizer instance) {
          instance
            ..onTapDown = onTapDown
            ..onTapUp = onTapUp;
        },
      );
    }

    gestures[DoubleTapGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
      () => DoubleTapGestureRecognizer(debugOwner: this),
      (DoubleTapGestureRecognizer instance) {
        instance..onDoubleTap = onDoubleTap;
      },
    );

    gestures[PhotoViewGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<PhotoViewGestureRecognizer>(
      () => PhotoViewGestureRecognizer(
          hitDetector: hitDetector, debugOwner: this, validateAxis: axis),
      (PhotoViewGestureRecognizer instance) {
        instance
          ..dragStartBehavior = DragStartBehavior.start
          ..onStart = onScaleStart
          ..onUpdate = onScaleUpdate
          ..onEnd = onScaleEnd;
      },
    );

    return Listener(
      child: RawGestureDetector(
        behavior: behavior,
        child: child,
        gestures: gestures,
      ),
      onPointerPanZoomStart: (event) {
        onScaleStart?.call(ScaleStartDetails(kind: event.kind));
      },
      onPointerPanZoomUpdate: (event) {
        onScaleUpdate?.call(
            ScaleUpdateDetails(scale: event.scale, focalPoint: event.position));
      },
      onPointerPanZoomEnd: (event) {
        onScaleEnd?.call(ScaleEndDetails());
      },
      onPointerSignal: (event) {
        if (event is PointerScaleEvent) {
          onScaleStart?.call(ScaleStartDetails(kind: event.kind));
          onScaleUpdate?.call(ScaleUpdateDetails(
              scale: event.scale, focalPoint: event.position));
          onScaleEnd?.call(ScaleEndDetails());
        } else if (event is PointerScrollEvent) {
          final keyboard = HardwareKeyboard.instance;
          if (keyboard.isLogicalKeyPressed(LogicalKeyboardKey.control) ||
              keyboard.isLogicalKeyPressed(LogicalKeyboardKey.controlLeft) ||
              keyboard.isLogicalKeyPressed(LogicalKeyboardKey.controlRight)) {
            onScaleStart?.call(ScaleStartDetails(kind: event.kind));
            onScaleUpdate?.call(ScaleUpdateDetails(
                scale: event.scrollDelta.dy > 0 ? 1.6 : 0.6,
                focalPoint: event.position));
            onScaleEnd?.call(ScaleEndDetails());
          }
        }
      },
    );
  }
}

class PhotoViewGestureRecognizer extends ScaleGestureRecognizer {
  PhotoViewGestureRecognizer({
    this.hitDetector,
    Object? debugOwner,
    this.validateAxis,
    PointerDeviceKind? kind,
  }) : super(debugOwner: debugOwner);
  final HitCornersDetector? hitDetector;
  final Axis? validateAxis;

  Map<int, Offset> _pointerLocations = <int, Offset>{};

  Offset? _initialFocalPoint;
  Offset? _currentFocalPoint;

  bool ready = true;

  @override
  void addAllowedPointer(event) {
    if (ready) {
      ready = false;
      _pointerLocations = <int, Offset>{};
    }
    super.addAllowedPointer(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    ready = true;
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (validateAxis != null) {
      _computeEvent(event);
      _updateDistances();
      _decideIfWeAcceptEvent(event);
    }
    super.handleEvent(event);
  }

  void _computeEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      if (!event.synthesized) {
        _pointerLocations[event.pointer] = event.position;
      }
    } else if (event is PointerDownEvent) {
      _pointerLocations[event.pointer] = event.position;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointerLocations.remove(event.pointer);
    }

    _initialFocalPoint = _currentFocalPoint;
  }

  void _updateDistances() {
    final int count = _pointerLocations.keys.length;
    Offset focalPoint = Offset.zero;
    for (int pointer in _pointerLocations.keys)
      focalPoint += _pointerLocations[pointer]!;
    _currentFocalPoint =
        count > 0 ? focalPoint / count.toDouble() : Offset.zero;
  }

  void _decideIfWeAcceptEvent(PointerEvent event) {
    if (!(event is PointerMoveEvent)) {
      return;
    }
    final move = _initialFocalPoint! - _currentFocalPoint!;
    final bool shouldMove = hitDetector!.shouldMove(move, validateAxis!);
    if (shouldMove || _pointerLocations.keys.length > 1) {
      acceptGesture(event.pointer);
    }
  }
}

/// An [InheritedWidget] responsible to give a axis aware scope to [PhotoViewGestureRecognizer].
///
/// When using this, PhotoView will test if the content zoomed has hit edge every time user pinches,
/// if so, it will let parent gesture detectors win the gesture arena
///
/// Useful when placing PhotoView inside a gesture sensitive context,
/// such as [PageView], [Dismissible], [BottomSheet].
///
/// Usage example:
/// ```
/// PhotoViewGestureDetectorScope(
///   axis: Axis.vertical,
///   child: PhotoView(
///     imageProvider: AssetImage("assets/pudim.jpg"),
///   ),
/// );
/// ```
class PhotoViewGestureDetectorScope extends InheritedWidget {
  PhotoViewGestureDetectorScope({
    this.axis,
    required Widget child,
  }) : super(child: child);

  static PhotoViewGestureDetectorScope? of(BuildContext context) {
    final PhotoViewGestureDetectorScope? scope = context
        .dependOnInheritedWidgetOfExactType<PhotoViewGestureDetectorScope>();
    return scope;
  }

  final Axis? axis;

  @override
  bool updateShouldNotify(PhotoViewGestureDetectorScope oldWidget) {
    return axis != oldWidget.axis;
  }
}

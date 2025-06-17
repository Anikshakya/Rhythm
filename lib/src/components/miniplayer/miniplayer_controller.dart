import 'package:flutter/material.dart';

class MiniPlayerController {
  static final MiniPlayerController inst = MiniPlayerController._internal();
  MiniPlayerController._internal();

  late AnimationController animation;
  double maxOffset = 0.0;
  double topInset = 0.0;
  double bottomInset = 0.0;
  double rightInset = 0.0;
  Size screenSize = Size.zero;
  double sMaxOffset = 0.0;
  bool bounceUp = false;
  bool bounceDown = false;

  void init(AnimationController controller, BuildContext context) {
    animation = controller;
    screenSize = MediaQuery.of(context).size;
    maxOffset = screenSize.height;
    sMaxOffset = screenSize.width;
    topInset = MediaQuery.of(context).padding.top;
    bottomInset = MediaQuery.of(context).padding.bottom;
    rightInset = MediaQuery.of(context).padding.right;
  }

  void onPointerDown(PointerDownEvent event) {}

  void onPointerMove(PointerMoveEvent event) {}

  void onPointerUp(PointerUpEvent event) {
    verticalSnapping(null); // Pass null for pointer-up events
  }

  void gestureDetectorOnTap() {
      animation.forward();
  }

  void gestureDetectorOnVerticalDragUpdate(DragUpdateDetails details) {
    final dragPercentage = -details.primaryDelta! / maxOffset;
    animation.value = (animation.value + dragPercentage).clamp(0.0, 1.0);
  }

  void verticalSnapping(DragEndDetails? details) {
    final velocity = details?.velocity.pixelsPerSecond.dy ?? 0.0;
    const velocityThreshold = 300.0; // Pixels per second for quick swipe detection

    if (velocity < -velocityThreshold) {
      // Quick swipe up: open
      animation.forward();
    } else if (velocity > velocityThreshold) {
      // Quick swipe down: close
      animation.reverse();
    } else {
      // Slow drag or no velocity: snap based on position
      if (animation.value > 0.3) { // Lowered threshold for more sensitivity
        animation.forward();
      } else {
        animation.reverse();
      }
    }
  }

  void gestureDetectorOnHorizontalDragStart(DragStartDetails details) {}
  void gestureDetectorOnHorizontalDragUpdate(DragUpdateDetails details) {}
  void gestureDetectorOnHorizontalDragEnd(DragEndDetails details) {}
}
 
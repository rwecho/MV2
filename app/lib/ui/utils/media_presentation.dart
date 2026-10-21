import 'package:flutter/foundation.dart';

/// Reference counted because a media route may open another media route.
abstract final class Mv2MediaPresentation {
  static final depth = ValueNotifier<int>(0);

  static VoidCallback acquire() {
    depth.value++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      depth.value--;
    };
  }
}

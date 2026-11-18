import 'dart:async';

import 'package:flutter/widgets.dart';

void dispatchTabBack(NavigatorState? navigator, Object? result) {
  // Do not move past the tab's root. Unlike pop(), maybePop() honors
  // the child route's PopScope and can return a wizard to its prior step.
  if (navigator != null && navigator.canPop()) {
    unawaited(navigator.maybePop(result));
  }
}

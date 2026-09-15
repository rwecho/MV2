import 'package:flutter/material.dart';

/// Window width (logical px) at which the app switches to the tablet
/// two-pane layout: topic lists stay on the left and the opened topic opens
/// in a right-hand pane instead of pushing a full-screen route.
///
/// Covers every iPad in landscape and the 13" models in portrait; the mini
/// and 11" models in portrait (744 / 834) stay single-column.
const double twoPaneBreakpoint = 900.0;

/// Whether the current window is wide enough for the two-pane layout.
bool mv2IsTwoPane(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= twoPaneBreakpoint;

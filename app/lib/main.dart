import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/telemetry/mv2_telemetry.dart';

/// MV2 entry point.
///
/// Kept intentionally thin: real wiring (storage hydration, HTTP client,
/// local database) belongs in `app/bootstrap.dart` once the data layer lands.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Installs the crash handlers synchronously, then boots Firebase in the
  // background so the first frame is never blocked on an SDK handshake.
  unawaited(Mv2Telemetry.start());
  runApp(const ProviderScope(child: Mv2App()));
}

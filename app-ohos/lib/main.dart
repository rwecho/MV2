import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

/// MV2 entry point.
///
/// Kept intentionally thin: real wiring (storage hydration, HTTP client,
/// local database) belongs in `app/bootstrap.dart` once the data layer lands.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: Mv2App()));
}

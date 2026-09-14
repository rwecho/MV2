import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Real app version, read from the platform bundle info (the
/// `version:` line in `pubspec.yaml`).
///
/// Rendered as `未知` only while the platform answer is pending or missing
/// (e.g. widget tests) — there is no canned fallback value.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

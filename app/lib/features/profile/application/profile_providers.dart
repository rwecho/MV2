import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../shared/models/models.dart';
import '../../auth/application/auth_controller.dart';

// The profile feature reads the signed-in username from the auth layer; re-export
// it so callers can keep importing it from here.
export '../../auth/application/auth_controller.dart'
    show currentUsernameProvider;

/// The signed-in member's profile (`/member/{username}`).
///
/// Resolves to `null` while anonymous, so the page keeps rendering its
/// logged-out call-to-action card.
final profileProvider = FutureProvider<V2Profile?>((ref) {
  final username = ref.watch(currentUsernameProvider);
  if (username == null) return Future<V2Profile?>.value(null);
  return ref.watch(v2exApiProvider).member(username);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/provider_retry.dart';
import '../../../shared/models/models.dart';

/// Public member profile (`/member/{username}`) for author navigation.
///
/// Distinct from the auth-scoped `profileProvider`: this one is keyed by the
/// username from the route and is safe to watch for any member. It resolves to
/// `null` when V2EX reports the member as missing (404).
final memberProvider = FutureProvider.family<V2Profile?, String>((
  ref,
  username,
) {
  return ref.watch(v2exApiProvider).member(username);
}, retry: mv2Retry);

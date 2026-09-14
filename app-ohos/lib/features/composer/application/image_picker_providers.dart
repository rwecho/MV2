import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'image_picker_gateway.dart';
import 'ohos_image_picker.dart';

/// ohos fork of `lib/features/composer/application/image_picker_providers.dart`.
///
/// The mainline default wraps `image_picker`, which has no HarmonyOS
/// implementation. On ohos the photo comes from the native
/// `mv2/image_picker` channel instead. The composer page only knows
/// [Mv2ImagePicker], so it is shared verbatim with the mainline.
///
/// The non-ohos branch exists for host-side widget tests (which run on macOS):
/// there is no system picker there, so it reports "no selection".
final imagePickerProvider = Provider<Mv2ImagePicker>((ref) {
  if (defaultTargetPlatform == TargetPlatform.ohos) {
    return const OhosImagePicker();
  }
  return const _UnsupportedImagePicker();
});

/// Host-test fallback: the composer button exists, but nothing is pickable.
class _UnsupportedImagePicker implements Mv2ImagePicker {
  const _UnsupportedImagePicker();

  @override
  Future<Mv2PickedImage?> pickImage() async => null;
}

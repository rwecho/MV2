import 'package:flutter/foundation.dart';

/// A photo the user picked, already decoded for upload.
///
/// Platform-agnostic on purpose: the mainline reaches it through
/// `image_picker`, while the HarmonyOS variant reads the system picker's
/// `datashare://` URI and copies it into the app sandbox first. Neither the
/// composer nor the Imgur uploader should care which happened.
@immutable
class Mv2PickedImage {
  const Mv2PickedImage({required this.bytes, required this.filename});

  /// Raw image bytes, ready for `ImgurUploader.upload`.
  final Uint8List bytes;

  /// Original (or synthesised) file name, used as the multipart file name.
  final String filename;
}

/// The composer's photo source.
///
/// Deliberately tiny and local: `image_picker` has no HarmonyOS implementation,
/// so the ohos variant supplies its own [Mv2ImagePicker] through
/// `imagePickerProvider` (see `image_picker_providers.dart`) without forking the
/// composer page. Mirrors the `Mv2PushGateway` / `pushGatewayProvider` split.
abstract interface class Mv2ImagePicker {
  /// Opens the platform picker. Resolves to `null` when the user cancels.
  Future<Mv2PickedImage?> pickImage();
}

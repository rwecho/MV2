import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel, PlatformException;

import 'image_picker_gateway.dart';

/// HarmonyOS photo picker backed by the `mv2/image_picker` platform channel.
///
/// The ArkTS half (`ohos/entry/src/main/ets/plugins/ImagePickerBridge.ets`)
/// opens the system picker through `photoAccessHelper.PhotoViewPicker`. That
/// picker hands back a `datashare://` media URI which `dart:io` cannot read, so
/// the bridge copies the selection into the app cache first and answers with
/// `{ path, name }`. A user cancel answers `null`.
class OhosImagePicker implements Mv2ImagePicker {
  const OhosImagePicker();

  /// Keep in sync with `ImagePickerBridge.METHOD_CHANNEL`.
  static const MethodChannel channel = MethodChannel('mv2/image_picker');

  @override
  Future<Mv2PickedImage?> pickImage() async {
    final result = await channel.invokeMethod<Object?>('pickImage');
    // The user dismissed the system picker.
    if (result == null) return null;
    if (result is! Map) {
      throw PlatformException(
        code: 'bad-result',
        message: 'mv2/image_picker returned an unexpected payload.',
      );
    }

    final path = result['path']?.toString() ?? '';
    if (path.isEmpty) return null;

    final name = result['name']?.toString() ?? '';
    return Mv2PickedImage(
      bytes: await File(path).readAsBytes(),
      filename: name.isNotEmpty ? name : path.split('/').last,
    );
  }
}

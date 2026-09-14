import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'image_picker_gateway.dart';

/// `image_picker`-backed [Mv2ImagePicker] for the platforms the plugin covers.
class ImagePickerImagePicker implements Mv2ImagePicker {
  const ImagePickerImagePicker();

  @override
  Future<Mv2PickedImage?> pickImage() async {
    // Width-capped so a 12 MP photo is not read/uploaded at full size.
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      imageQuality: 90,
    );
    if (picked == null) return null;
    return Mv2PickedImage(
      bytes: await picked.readAsBytes(),
      filename: picked.name,
    );
  }
}

/// The photo picker, swappable in tests (`overrideWithValue`).
final imagePickerProvider = Provider<Mv2ImagePicker>(
  (ref) => const ImagePickerImagePicker(),
);

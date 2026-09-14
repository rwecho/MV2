/*
 * HarmonyOS half of the `mv2/image_picker` bridge.
 *
 * The Dart side is `lib/features/composer/application/ohos_image_picker.dart`;
 * both must agree on the channel name and the result shape:
 *
 *   method channel `mv2/image_picker`
 *     pickImage -> null                      user cancelled
 *                -> { path: string, name: string }   a file in the app cache
 *
 * `photoAccessHelper.PhotoViewPicker` is the system gallery picker: it needs no
 * `ohos.permission.READ_IMAGEVIDEO` (the picker itself grants temporary read
 * access to the chosen item) and it is what a publisher should keep using. The
 * picked value is a `datashare://` media URI, which `dart:io` on the Flutter
 * side cannot open, so this bridge copies the bytes into the app cache and
 * hands Dart a real filesystem path. See README.md §"Image upload".
 *
 * Every call is wrapped so a dismissed picker, a revoked URI or a full cache
 * degrades to a Dart-side error/SnackBar instead of taking the app down.
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FlutterEngine, Log } from '@ohos/flutter_ohos';
import { Any, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import UIAbility from '@ohos.app.ability.UIAbility';

const TAG: string = 'Mv2ImagePicker';

/** Keep in sync with `OhosImagePicker.channel`. */
const METHOD_CHANNEL: string = 'mv2/image_picker';

/** Extensions Imgur accepts; anything else falls back to `.jpg`. */
const IMAGE_EXTENSIONS: string[] = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'];

/**
 * Owns the `mv2/image_picker` method channel. One instance per EntryAbility,
 * created in `configureFlutterEngine` next to the plugin registrant.
 */
export class ImagePickerBridge {
  private readonly ability: UIAbility;
  private methodChannel: MethodChannel | null = null;

  constructor(ability: UIAbility) {
    this.ability = ability;
  }

  /** Wires the channel onto [engine]. */
  static attach(engine: FlutterEngine, ability: UIAbility): ImagePickerBridge {
    const bridge = new ImagePickerBridge(ability);
    const messenger = engine.getDartExecutor().getBinaryMessenger();
    bridge.methodChannel = new MethodChannel(messenger, METHOD_CHANNEL);
    bridge.methodChannel.setMethodCallHandler(new ImagePickerHandler(bridge));
    return bridge;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'pickImage') {
      this.pickImage(result);
      return;
    }
    result.notImplemented();
  }

  /** Opens the system photo picker and resolves a cached file (or null). */
  private pickImage(result: MethodResult): void {
    let options: photoAccessHelper.PhotoSelectOptions;
    try {
      options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
    } catch (e) {
      result.error('picker-init-failed', ImagePickerBridge.describe(e), null);
      return;
    }

    const picker = new photoAccessHelper.PhotoViewPicker();
    picker.select(options)
      .then((selection: photoAccessHelper.PhotoSelectResult) => {
        const uris = ImagePickerBridge.selectedUris(selection);
        // Some builds answer a cancel with an empty list rather than a reject.
        if (uris.length === 0) {
          result.success(null);
          return;
        }
        this.copyToCache(uris[0])
          .then((picked: Map<string, string>) => result.success(picked))
          .catch((e: BusinessError) => {
            Log.e(TAG, 'Failed to cache the picked image: ' + ImagePickerBridge.describe(e));
            result.error('copy-failed', '无法读取所选图片，请重试。', e.code);
          });
      })
      .catch((e: BusinessError) => {
        // The system picker rejects when the user backs out on some builds.
        // There is no distinguishing code documented, so treat it as a cancel
        // and keep the code in the log for diagnosis.
        Log.i(TAG, 'PhotoViewPicker dismissed: ' + ImagePickerBridge.describe(e));
        result.success(null);
      });
  }

  /**
   * Copies the picker's `datashare://` media URI into the app cache and
   * resolves `{ path, name }`. `dart:io` cannot open a media URI, so the copy
   * is what makes `File.readAsBytes()` possible on the Flutter side.
   */
  private copyToCache(uri: string): Promise<Map<string, string>> {
    return new Promise<Map<string, string>>((resolve, reject) => {
      let source: fs.File | null = null;
      let target: fs.File | null = null;
      try {
        const name = ImagePickerBridge.fileName(uri);
        const path = `${this.ability.context.cacheDir}/${name}`;
        source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        target = fs.openSync(
          path,
          fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
        );
        fs.copyFileSync(source.fd, target.fd);
        const payload = new Map<string, string>();
        payload.set('path', path);
        payload.set('name', name);
        resolve(payload);
      } catch (e) {
        reject(e as BusinessError);
      } finally {
        ImagePickerBridge.closeQuietly(source);
        ImagePickerBridge.closeQuietly(target);
      }
    });
  }

  /** `photoUris` is documented as non-null but is optional at runtime. */
  private static selectedUris(selection: photoAccessHelper.PhotoSelectResult): string[] {
    if (selection === undefined || selection === null) return [];
    const uris = selection.photoUris;
    if (uris === undefined || uris === null) return [];
    return uris;
  }

  /**
   * Builds a cache file name that keeps a usable image extension so Imgur's
   * multipart name survives. The media URI's last segment is often opaque.
   */
  private static fileName(uri: string): string {
    let extension = 'jpg';
    const bare = uri.split('?')[0];
    const dot = bare.lastIndexOf('.');
    if (dot >= 0) {
      const candidate = bare.substring(dot + 1).toLowerCase();
      if (IMAGE_EXTENSIONS.includes(candidate)) extension = candidate;
    }
    return `mv2-pick-${Date.now()}.${extension}`;
  }

  private static closeQuietly(file: fs.File | null): void {
    if (file === null) return;
    try {
      fs.closeSync(file);
    } catch (e) {
      // Already closed / never opened: nothing useful to do.
    }
  }

  /** Error text for logs — code and message only. */
  private static describe(e: Object): string {
    const err = e as BusinessError;
    if (err !== undefined && err !== null && err.message !== undefined) {
      return `code=${err.code} message=${err.message}`;
    }
    return `${e}`;
  }
}

/** Bridges the Flutter method channel to [ImagePickerBridge]. */
class ImagePickerHandler implements MethodCallHandler {
  private bridge: ImagePickerBridge;

  constructor(bridge: ImagePickerBridge) {
    this.bridge = bridge;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.bridge.onMethodCall(call, result);
  }
}

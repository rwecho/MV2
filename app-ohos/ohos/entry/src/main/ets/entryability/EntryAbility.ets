
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { HmsPushBridge } from '../push/HmsPushBridge';
import { ImagePickerBridge } from '../plugins/ImagePickerBridge';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';

export default class EntryAbility extends FlutterAbility {
  /** The `mv2/push` bridge; null until the Flutter engine is configured. */
  private pushBridge: HmsPushBridge | null = null;
  /** The cold-start Want, kept until the bridge exists. */
  private pendingWant: Want | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // Wired next to the plugin registrant so both native halves are ready
    // before Dart runs.
    this.pushBridge = HmsPushBridge.attach(flutterEngine, this)
    // No permission prompt: the system photo picker grants temporary read
    // access to whatever the user selects (see ImagePickerBridge.ets).
    ImagePickerBridge.attach(flutterEngine, this)
    const want = this.pendingWant
    if (want !== null) {
      this.pushBridge.handleWant(want)
      this.pendingWant = null
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // A notification tap that cold-starts the app arrives here; buffer it
    // before the engine exists so the bridge can replay it to Dart.
    this.pendingWant = want
    super.onCreate(want, launchParam)
    const bridge = this.pushBridge
    const pending = this.pendingWant
    if (bridge !== null && pending !== null) {
      bridge.handleWant(pending)
      this.pendingWant = null
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam)
    const bridge = this.pushBridge
    if (bridge !== null) {
      bridge.handleWant(want)
    }
  }
}

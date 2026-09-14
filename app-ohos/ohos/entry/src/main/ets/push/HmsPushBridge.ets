/*
 * HarmonyOS half of the `mv2/push` bridge.
 *
 * The Dart side is `lib/core/push/hms_push_gateway.dart`; both must agree on
 * the two channel names below and on the shape of the event envelopes:
 *
 *   method channel `mv2/push`
 *     isConfigured     -> boolean  (is a real AGC client_id present?)
 *     getToken         -> string   (pushService.getToken())
 *     requestPermission-> boolean  (system notification enablement)
 *     initialOpened    -> map|null (notification tap that cold-started the app)
 *
 *   event channel `mv2/push/events`
 *     { type: 'token',   token: string }
 *     { type: 'message', data: map }   foreground data message
 *     { type: 'opened',  data: map }   notification tap while running
 *
 * Every Push Kit call is wrapped: a missing AppGallery Connect project, an
 * unsigned debug build, or an unsupported device must degrade to "push
 * unavailable" instead of taking the app down.
 */

import { EventChannel, EventSink, StreamHandler } from '@ohos/flutter_ohos';
import { FlutterEngine, Log } from '@ohos/flutter_ohos';
import { Any, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { pushCommon, pushService } from '@kit.PushKit';
import { notificationManager } from '@kit.NotificationKit';
import { bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';

const TAG: string = 'Mv2HmsPush';

/** Keep in sync with `HmsPushGateway.methodChannelName`. */
const METHOD_CHANNEL: string = 'mv2/push';
/** Keep in sync with `HmsPushGateway.eventChannelName`. */
const EVENT_CHANNEL: string = 'mv2/push/events';

/** `module.json5` metadata the publisher replaces with the AGC client_id. */
const CLIENT_ID_METADATA: string = 'client_id';

/**
 * The non-functional value shipped in `module.json5`. Push stays off until the
 * publisher drops in a real AppGallery Connect project.
 */
const CLIENT_ID_PLACEHOLDER: string = 'REPLACE_WITH_AGC_CLIENT_ID';

/**
 * Owns the lifetime of the two platform channels and relays Push Kit events to
 * Dart. One instance per EntryAbility, created in `configureFlutterEngine`.
 */
export class HmsPushBridge {
  private readonly ability: UIAbility;
  private methodChannel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private events: EventSink | null = null;

  private configured: boolean = false;
  private clientId: string = '';
  private receiverRegistered: boolean = false;

  /** A token rotation that arrived before Dart started listening. */
  private pendingToken: string | null = null;
  /** A notification tap that cold-started the app, kept until Dart asks. */
  private pendingOpened: Map<string, Object> | null = null;

  constructor(ability: UIAbility) {
    this.ability = ability;
  }

  /**
   * Wires both channels onto [engine] and, when a real AGC client_id is
   * present, subscribes to the Push Kit token/message callbacks.
   */
  static attach(engine: FlutterEngine, ability: UIAbility): HmsPushBridge {
    const bridge = new HmsPushBridge(ability);
    const messenger = engine.getDartExecutor().getBinaryMessenger();

    bridge.methodChannel = new MethodChannel(messenger, METHOD_CHANNEL);
    bridge.methodChannel.setMethodCallHandler(new HmsMethodHandler(bridge));

    bridge.eventChannel = new EventChannel(messenger, EVENT_CHANNEL);
    bridge.eventChannel.setStreamHandler(new HmsStreamHandler(bridge));

    bridge.configure();
    return bridge;
  }

  /** Reads the AGC client_id and, if usable, starts Push Kit callbacks. */
  private configure(): void {
    this.clientId = this.readClientId();
    this.configured = this.clientId.length > 0 && this.clientId !== CLIENT_ID_PLACEHOLDER;
    if (!this.configured) {
      Log.w(TAG, 'AGC client_id is not configured; HMS push stays disabled.');
      return;
    }
    this.registerTokenUpdates();
    this.registerMessageReceiver();
  }

  /** True only when the build carries a real AGC client_id. */
  isConfigured(): boolean {
    return this.configured;
  }

  /**
   * Entry point for a notification tap: called from `onCreate` (cold start) and
   * `onNewWant` (app already running). The payload is buffered until Dart
   * consumes it or delivered straight to a live event stream.
   */
  handleWant(want: Want): void {
    try {
      const payload = HmsPushBridge.extractPayload(want);
      if (payload === null) return;
      this.deliverOpened(payload);
    } catch (e) {
      Log.e(TAG, 'Failed to read the push want: ' + HmsPushBridge.describe(e));
    }
  }

  /** Called by `HmsMethodHandler`: request/response half of the bridge. */
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'isConfigured') {
      result.success(this.configured);
      return;
    }
    if (call.method === 'getToken') {
      this.getToken(result);
      return;
    }
    if (call.method === 'requestPermission') {
      this.requestPermission(result);
      return;
    }
    if (call.method === 'initialOpened') {
      const payload = this.pendingOpened;
      this.pendingOpened = null;
      result.success(payload);
      return;
    }
    result.notImplemented();
  }

  /** Called by `HmsStreamHandler` when Dart subscribes / unsubscribes. */
  onListen(events: EventSink): void {
    this.events = events;
    if (this.pendingToken !== null) {
      const token = this.pendingToken;
      this.pendingToken = null;
      this.emitToken(token);
    }
  }

  onCancel(): void {
    this.events = null;
  }

  private getToken(result: MethodResult): void {
    if (!this.configured) {
      result.error('not-configured', 'AGC client_id is not configured.', null);
      return;
    }
    pushService.getToken()
      .then((token: string) => {
        if (token === undefined || token === null || token.length === 0) {
          result.error('empty-token', 'Push Kit returned an empty token.', null);
          return;
        }
        result.success(token);
      })
      .catch((e: BusinessError) => {
        // Never include the token (there is none on this path); the code and
        // message are enough to diagnose AGC/signing problems.
        Log.e(TAG, 'pushService.getToken failed: ' + HmsPushBridge.describe(e));
        result.error('hms-token-failed', e.message ?? 'getToken failed', e.code);
      });
  }

  private requestPermission(result: MethodResult): void {
    notificationManager.isNotificationEnabled()
      .then((enabled: boolean) => {
        if (enabled) {
          result.success(true);
          return;
        }
        notificationManager.requestEnableNotification(this.ability.context)
          .then(() => {
            result.success(true);
          })
          .catch(() => {
            // The user declined the system prompt.
            result.success(false);
          });
      })
      .catch((e: BusinessError) => {
        Log.e(TAG, 'isNotificationEnabled failed: ' + HmsPushBridge.describe(e));
        result.success(false);
      });
  }

  private registerTokenUpdates(): void {
    try {
      pushService.on('tokenUpdate', this.ability, (token: string) => {
        if (token === undefined || token === null || token.length === 0) return;
        this.emitToken(token);
      });
    } catch (e) {
      Log.e(TAG, 'tokenUpdate subscription failed: ' + HmsPushBridge.describe(e));
    }
  }

  private registerMessageReceiver(): void {
    if (this.receiverRegistered) return;
    try {
      pushService.receiveMessage('DEFAULT', this.ability, (payload: pushCommon.PushPayload) => {
        this.emitMessage(payload);
      });
      this.receiverRegistered = true;
    } catch (e) {
      // 1000900005 means another receiver of this type is already registered;
      // either way the app keeps working.
      Log.e(TAG, 'receiveMessage failed: ' + HmsPushBridge.describe(e));
    }
  }

  private emitToken(token: string): void {
    const sink = this.events;
    if (sink === null) {
      this.pendingToken = token;
      return;
    }
    const envelope = new Map<string, Object>();
    envelope.set('type', 'token');
    envelope.set('token', token);
    HmsPushBridge.send(sink, envelope);
  }

  private emitMessage(payload: pushCommon.PushPayload): void {
    const data = HmsPushBridge.parseData(payload === null ? undefined : payload.data);
    if (data === null) return;
    const envelope = new Map<string, Object>();
    envelope.set('type', 'message');
    envelope.set('data', data);
    HmsPushBridge.send(this.events, envelope);
  }

  private deliverOpened(payload: Map<string, Object>): void {
    const sink = this.events;
    if (sink === null) {
      this.pendingOpened = payload;
      return;
    }
    const envelope = new Map<string, Object>();
    envelope.set('type', 'opened');
    envelope.set('data', payload);
    HmsPushBridge.send(sink, envelope);
  }

  private static send(sink: EventSink | null, envelope: Map<string, Object>): void {
    if (sink === null) return;
    try {
      sink.success(envelope);
    } catch (e) {
      Log.e(TAG, 'Failed to forward a push event: ' + HmsPushBridge.describe(e));
    }
  }

  /**
   * Reads the `client_id` metadata from this module. The AGC tooling consumes
   * the same entry; checking it here keeps an unconfigured build from ever
   * calling Push Kit.
   */
  private readClientId(): string {
    try {
      const flags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE;
      const info = bundleManager.getBundleInfoForSelfSync(flags);
      const modules = info.hapModulesInfo;
      if (modules === undefined || modules === null) return '';
      for (const module of modules) {
        const metadata = module.metadata;
        if (metadata === undefined || metadata === null) continue;
        for (const item of metadata) {
          if (item.name === CLIENT_ID_METADATA) {
            const value = item.value;
            return value === undefined || value === null ? '' : value;
          }
        }
      }
    } catch (e) {
      Log.e(TAG, 'Failed to read the AGC client_id metadata: ' + HmsPushBridge.describe(e));
    }
    return '';
  }

  /**
   * Finds the push payload in the Want that opened the app. Push Kit does not
   * expose the parameter key as a stable constant, so every string parameter is
   * probed for the `{link, topicId, notificationId}` object the worker sends.
   */
  private static extractPayload(want: Want): Map<string, Object> | null {
    const params = want.parameters;
    if (params === undefined || params === null) return null;
    const keys = Object.keys(params);
    for (const key of keys) {
      const value = params[key];
      if (typeof value !== 'string') continue;
      const parsed = HmsPushBridge.parseData(value as string);
      if (parsed !== null) return parsed;
    }
    return null;
  }

  /** Parses the worker's JSON payload, keeping only the keys Dart understands. */
  private static parseData(raw: string | undefined): Map<string, Object> | null {
    if (raw === undefined || raw === null) return null;
    const trimmed = raw.trim();
    if (trimmed.length === 0 || !trimmed.startsWith('{')) return null;
    try {
      const parsed = JSON.parse(trimmed) as Record<string, Object>;
      const result = new Map<string, Object>();
      const link = parsed['link'];
      const topicId = parsed['topicId'];
      const notificationId = parsed['notificationId'];
      if (typeof link === 'string' && (link as string).length > 0) {
        result.set('link', link as string);
      }
      if (typeof topicId === 'string' && (topicId as string).length > 0) {
        result.set('topicId', topicId as string);
      }
      if (typeof notificationId === 'string' && (notificationId as string).length > 0) {
        result.set('notificationId', notificationId as string);
      }
      return result.size > 0 ? result : null;
    } catch (e) {
      return null;
    }
  }

  /** Error text for logs — message and code only, never a token or secret. */
  private static describe(e: Object): string {
    const err = e as BusinessError;
    if (err !== undefined && err !== null && err.message !== undefined) {
      return `code=${err.code} message=${err.message}`;
    }
    return `${e}`;
  }
}

/** Bridges the Flutter method channel to `HmsPushBridge`. */
class HmsMethodHandler implements MethodCallHandler {
  private bridge: HmsPushBridge;

  constructor(bridge: HmsPushBridge) {
    this.bridge = bridge;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.bridge.onMethodCall(call, result);
  }
}

/** Captures the Dart event sink for the lifetime of the subscription. */
class HmsStreamHandler implements StreamHandler {
  private bridge: HmsPushBridge;

  constructor(bridge: HmsPushBridge) {
    this.bridge = bridge;
  }

  onListen(args: Any, events: EventSink): void {
    this.bridge.onListen(events);
  }

  onCancel(args: Any): void {
    this.bridge.onCancel();
  }
}

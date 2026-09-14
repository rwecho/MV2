import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  processUserNotifications,
  QUARANTINE_PROBE_MS,
  QUARANTINE_DROP_MS,
} from "../src/index";
import { isUnregisteredToken } from "../src/utils/fcm";

class FakeKV {
  private store = new Map<string, string>();

  async get(key: string): Promise<string | null> {
    return this.store.get(key) ?? null;
  }
  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
  async delete(key: string): Promise<void> {
    this.store.delete(key);
  }
  async list(): Promise<{ keys: { name: string }[]; list_complete: boolean }> {
    return {
      keys: Array.from(this.store.keys()).map((name) => ({ name })),
      list_complete: true,
    };
  }
  rawGet(key: string): string | undefined {
    return this.store.get(key);
  }
}

function makeEnv() {
  return {
    V2EX_PUSH_KV: new FakeKV() as any,
    FIREBASE_SERVICE_ACCOUNT_JSON: "{}",
    HMS_SERVICE_ACCOUNT_JSON: "",
    HMS_APP_ID: "",
    ADMIN_SECRET: "test",
  };
}

function notif(id: string, published: number): any {
  return {
    id,
    title: `Title ${id}`,
    link: `/t/123?p=1#reply${id}`,
    published,
    content: "hello",
    authorName: "alice",
  };
}

function userData(fcmToken: string, extra: Record<string, any> = {}): any {
  return {
    feedUrl: "https://www.v2ex.com/feed/notifications.xml",
    fcmToken,
    deviceType: "iOS",
    updatedAt: Date.now(),
    lastPushed: 0,
    ...extra,
  };
}

describe("FCM unregistered detection", () => {
  it("recognises the v1 UNREGISTERED error body", () => {
    const body = JSON.stringify({
      error: {
        code: 404,
        message: "Requested entity was not found.",
        status: "NOT_FOUND",
        details: [
          {
            "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
            errorCode: "UNREGISTERED",
          },
        ],
      },
    });
    expect(isUnregisteredToken(404, body)).toBe(true);
  });

  it("does not treat transient failures as unregistered", () => {
    expect(isUnregisteredToken(503, "Service Unavailable")).toBe(false);
    expect(
      isUnregisteredToken(403, JSON.stringify({ error: { status: "PERMISSION_DENIED" } })),
    ).toBe(false);
    expect(isUnregisteredToken(500, JSON.stringify({ error: { status: "INTERNAL" } }))).toBe(
      false,
    );
  });
});

describe("unregistered-token quarantine", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  it("quarantines a token FCM reports as unregistered", async () => {
    const env = makeEnv();
    // The real sender now returns a result object; the previous boolean shape is
    // still accepted (covered by the dedup/hms suites).
    const sendPush = vi
      .fn()
      .mockResolvedValue({ ok: false, unregistered: true });
    const fetchFeed = vi.fn().mockResolvedValue([notif("a", 100)]);

    const result = await processUserNotifications(
      env,
      "user:tok",
      userData("tok"),
      [],
      sendPush as any,
      fetchFeed as any,
    );

    expect(result.pushedCount).toBe(0);
    const stored = JSON.parse(env.V2EX_PUSH_KV.rawGet("user:tok")!);
    expect(stored.quarantine?.unregistered).toBe(true);
    expect(typeof stored.quarantine.since).toBe("number");
    expect(typeof stored.quarantine.probedAt).toBe("number");
  });

  it("skips a quarantined token until the probe falls due", async () => {
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue(true);
    const fetchFeed = vi.fn().mockResolvedValue([notif("a", 100)]);

    await processUserNotifications(
      env,
      "user:tok",
      userData("tok", {
        quarantine: {
          unregistered: true,
          since: Date.now() - QUARANTINE_PROBE_MS / 2,
          probedAt: Date.now(),
        },
      }),
      [],
      sendPush as any,
      fetchFeed as any,
    );

    // Not even the feed is fetched while quarantined.
    expect(fetchFeed).not.toHaveBeenCalled();
    expect(sendPush).not.toHaveBeenCalled();
  });

  it("lifts the quarantine once a probe delivers again", async () => {
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue({ ok: true, unregistered: false });
    const fetchFeed = vi.fn().mockResolvedValue([notif("a", 100)]);

    const result = await processUserNotifications(
      env,
      "user:tok",
      userData("tok", {
        quarantine: {
          unregistered: true,
          since: Date.now() - QUARANTINE_PROBE_MS * 2,
          probedAt: Date.now() - QUARANTINE_PROBE_MS * 2,
        },
      }),
      [],
      sendPush as any,
      fetchFeed as any,
    );

    expect(result.pushedCount).toBe(1);
    const stored = JSON.parse(env.V2EX_PUSH_KV.rawGet("user:tok")!);
    expect(stored.quarantine).toBeUndefined();
  });

  it("stamps the probe time on a transient probe failure", async () => {
    const env = makeEnv();
    // A 500: still failing, but *not* an unregistered verdict.
    const sendPush = vi.fn().mockResolvedValue({ ok: false, unregistered: false });
    const fetchFeed = vi.fn().mockResolvedValue([notif("a", 100)]);
    const staleProbe = Date.now() - QUARANTINE_PROBE_MS * 2;

    await processUserNotifications(
      env,
      "user:tok",
      userData("tok", {
        quarantine: {
          unregistered: true,
          since: staleProbe,
          probedAt: staleProbe,
        },
      }),
      [],
      sendPush as any,
      fetchFeed as any,
    );

    const stored = JSON.parse(env.V2EX_PUSH_KV.rawGet("user:tok")!);
    // Still quarantined, but the next probe is a day away rather than 15 minutes.
    expect(stored.quarantine?.unregistered).toBe(true);
    expect(stored.quarantine.probedAt).toBeGreaterThan(staleProbe);
    expect(stored.quarantine.since).toBe(staleProbe);
  });

  it("drops an entry that has been unregistered for over 90 days", async () => {
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue(true);
    const fetchFeed = vi.fn().mockResolvedValue([notif("a", 100)]);

    await processUserNotifications(
      env,
      "user:tok",
      userData("tok", {
        quarantine: {
          unregistered: true,
          since: Date.now() - QUARANTINE_DROP_MS - 1000,
          probedAt: Date.now() - 1000,
        },
      }),
      [],
      sendPush as any,
      fetchFeed as any,
    );

    expect(env.V2EX_PUSH_KV.rawGet("user:tok")).toBeUndefined();
    expect(sendPush).not.toHaveBeenCalled();
  });
});

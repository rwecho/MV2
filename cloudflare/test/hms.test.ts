import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { exportPKCS8, generateKeyPair } from "jose";
import {
  HMS_ACCESS_TOKEN_KV_KEY,
  getHmsAccessToken,
  isHmsDevice,
  sendHmsPush,
} from "../src/utils/hms";
import { processUserNotifications } from "../src/index";

class FakeKV {
  private store = new Map<string, string>();

  async get(key: string): Promise<string | null> {
    return this.store.get(key) ?? null;
  }
  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
  async list(): Promise<{
    keys: { name: string }[];
    list_complete: boolean;
  }> {
    return {
      keys: Array.from(this.store.keys()).map((name) => ({ name })),
      list_complete: true,
    };
  }
  async delete(key: string): Promise<void> {
    this.store.delete(key);
  }
  rawGet(key: string): string | undefined {
    return this.store.get(key);
  }
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

function hmsUser(lastPushed = 0): any {
  return {
    feedUrl: "https://www.v2ex.com/feed/notifications.xml",
    // The token field keeps its original name; only `deviceType` selects HMS.
    fcmToken: "hms-token-1",
    deviceType: "hms",
    updatedAt: Date.now(),
    lastPushed,
  };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

describe("isHmsDevice", () => {
  it("accepts the canonical hms type and the ohos Flutter target name", () => {
    expect(isHmsDevice("hms")).toBe(true);
    expect(isHmsDevice("ohos")).toBe(true);
    expect(isHmsDevice("iOS")).toBe(false);
    expect(isHmsDevice("Android")).toBe(false);
    expect(isHmsDevice(undefined)).toBe(false);
  });
});

describe("getHmsAccessToken", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("reuses the token cached in KV without calling the token endpoint", async () => {
    const kv = new FakeKV();
    await kv.put(HMS_ACCESS_TOKEN_KV_KEY, "cached-token");
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const token = await getHmsAccessToken({}, kv as any);

    expect(token).toBe("cached-token");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("mints a JWT assertion, exchanges it and caches the result", async () => {
    const kv = new FakeKV();
    const { privateKey } = await generateKeyPair("RS256", {
      extractable: true,
    });
    const pem = await exportPKCS8(privateKey);

    const fetchMock = vi
      .fn()
      .mockResolvedValue(jsonResponse({ access_token: "fresh-token", expires_in: 3600 }));
    vi.stubGlobal("fetch", fetchMock);

    const token = await getHmsAccessToken(
      {
        client_email: "svc@example.iam.gserviceaccount.com",
        private_key: pem,
        private_key_id: "kid-1",
      },
      kv as any,
    );

    expect(token).toBe("fresh-token");
    expect(fetchMock).toHaveBeenCalledTimes(1);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://oauth2.cloud.huawei.com/oauth2/v2/token");
    expect(init.method).toBe("POST");
    const body = init.body as URLSearchParams;
    expect(body.get("grant_type")).toBe("client_credentials");
    expect(body.get("client_assertion_type")).toBe(
      "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
    );
    // The assertion is a three-part JWT, not the private key.
    expect((body.get("client_assertion") as string).split(".")).toHaveLength(3);

    // Cached with a TTL that refreshes before expiry.
    expect(kv.rawGet(HMS_ACCESS_TOKEN_KV_KEY)).toBe("fresh-token");
  });

  it("returns null (no throw) when the credentials are unusable", async () => {
    const kv = new FakeKV();
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    expect(await getHmsAccessToken({}, kv as any)).toBeNull();
    expect(await getHmsAccessToken({ client_email: "x" }, kv as any)).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("sendHmsPush", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("is a clean per-device failure when the secret is missing", async () => {
    const kv = new FakeKV();
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const ok = await sendHmsPush(
      "dev-1",
      "t",
      "b",
      { link: "/t/1" },
      undefined,
      "app-1",
      kv as any,
    );

    expect(ok).toBe(false);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("is a clean per-device failure when the app id is missing", async () => {
    const kv = new FakeKV();
    await kv.put(HMS_ACCESS_TOKEN_KV_KEY, "cached-token");
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const ok = await sendHmsPush(
      "dev-1",
      "t",
      "b",
      { link: "/t/1" },
      "{}",
      undefined,
      kv as any,
    );

    expect(ok).toBe(false);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("posts the worker payload to the HMS Push REST endpoint", async () => {
    const kv = new FakeKV();
    await kv.put(HMS_ACCESS_TOKEN_KV_KEY, "cached-token");
    const fetchMock = vi
      .fn()
      .mockResolvedValue(jsonResponse({ code: "80000000", msg: "Success" }));
    vi.stubGlobal("fetch", fetchMock);

    const data = { link: "/t/123", topicId: "123", notificationId: "n1" };
    const ok = await sendHmsPush(
      "dev-1",
      "Title",
      "Body",
      data,
      "{}",
      "app-42",
      kv as any,
    );

    expect(ok).toBe(true);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(
      "https://push-api.cloud.huawei.com/v1/app-42/messages:send",
    );
    expect(init.headers.Authorization).toBe("Bearer cached-token");

    const body = JSON.parse(init.body as string);
    expect(body.message.token).toEqual(["dev-1"]);
    expect(body.message.notification).toEqual({ title: "Title", body: "Body" });
    expect(JSON.parse(body.message.data)).toEqual(data);
  });

  it("treats an application-level error code as a failed push", async () => {
    const kv = new FakeKV();
    await kv.put(HMS_ACCESS_TOKEN_KV_KEY, "cached-token");
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(jsonResponse({ code: "80100000", msg: "bad token" })),
    );

    const ok = await sendHmsPush(
      "dev-1",
      "t",
      "b",
      {},
      "{}",
      "app-42",
      kv as any,
    );

    expect(ok).toBe(false);
  });
});

describe("processUserNotifications HMS routing", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.unstubAllGlobals();
  });

  function makeEnv(extra: Record<string, unknown> = {}) {
    return {
      V2EX_PUSH_KV: new FakeKV(),
      FIREBASE_SERVICE_ACCOUNT_JSON: "{}",
      ADMIN_SECRET: "test",
      ...extra,
    };
  }

  it("routes an hms device to the HMS sender, not FCM", async () => {
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue(true);
    const sendHms = vi.fn().mockResolvedValue(true);
    const fetchFeed = vi.fn().mockResolvedValue([notif("a", 100)]);

    const result = await processUserNotifications(
      env as any,
      "user:hms-token-1",
      hmsUser(),
      [],
      sendPush as any,
      fetchFeed as any,
      sendHms as any,
    );

    expect(result.pushedCount).toBe(1);
    expect(sendHms).toHaveBeenCalledTimes(1);
    expect(sendPush).not.toHaveBeenCalled();
    // The HMS sender gets the token, title/body and the env credentials.
    expect(sendHms.mock.calls[0][0]).toBe("hms-token-1");
    expect(sendHms.mock.calls[0][4]).toBe(env.HMS_SERVICE_ACCOUNT_JSON);
    expect(sendHms.mock.calls[0][5]).toBe(env.HMS_APP_ID);
  });

  it("keeps the FCM path for a non-hms device", async () => {
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue(true);
    const sendHms = vi.fn().mockResolvedValue(true);
    const fetchFeed = vi.fn().mockResolvedValue([notif("a", 100)]);

    const user = { ...hmsUser(), deviceType: "iOS" };
    const result = await processUserNotifications(
      env as any,
      "user:tok",
      user,
      [],
      sendPush as any,
      fetchFeed as any,
      sendHms as any,
    );

    expect(result.pushedCount).toBe(1);
    expect(sendPush).toHaveBeenCalledTimes(1);
    expect(sendHms).not.toHaveBeenCalled();
  });

  it("degrades a missing HMS credential to a per-device error, not a crash", async () => {
    // No HMS_SERVICE_ACCOUNT_JSON / HMS_APP_ID in the environment: the real
    // sender runs and must fail this one device without aborting the run.
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue(true);
    const fetchFeed = vi.fn().mockResolvedValue([notif("a", 100)]);

    await expect(
      processUserNotifications(
        env as any,
        "user:hms-token-1",
        hmsUser(),
        [],
        sendPush as any,
        fetchFeed as any,
      ),
    ).resolves.toEqual({ pushedCount: 0 });

    expect(sendPush).not.toHaveBeenCalled();
  });

  it("sends an hms device through the real sender end to end", async () => {
    const kv = new FakeKV();
    await kv.put(HMS_ACCESS_TOKEN_KV_KEY, "cached-token");
    const env = {
      V2EX_PUSH_KV: kv,
      FIREBASE_SERVICE_ACCOUNT_JSON: "{}",
      ADMIN_SECRET: "test",
      HMS_SERVICE_ACCOUNT_JSON: "{}",
      HMS_APP_ID: "app-42",
    };
    const fetchFeed = vi.fn().mockResolvedValue([notif("a", 100)]);
    const fetchMock = vi
      .fn()
      .mockResolvedValue(jsonResponse({ code: "80000000", msg: "Success" }));
    vi.stubGlobal("fetch", fetchMock);

    const result = await processUserNotifications(
      env as any,
      "user:hms-token-1",
      hmsUser(),
      [],
      vi.fn().mockResolvedValue(true) as any,
      fetchFeed as any,
    );

    expect(result.pushedCount).toBe(1);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(String(fetchMock.mock.calls[0][0])).toContain(
      "/v1/app-42/messages:send",
    );
  });
});

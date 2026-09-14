import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  processUserNotifications,
  MAX_PUSH_PER_USER_PER_RUN,
  PUSHED_IDS_LIMIT,
} from "../src/index";
import worker from "../src/index";

class FakeKV {
  private store = new Map<string, string>();
  failNextPut = false;

  async get(key: string): Promise<string | null> {
    return this.store.get(key) ?? null;
  }
  async put(key: string, value: string): Promise<void> {
    if (this.failNextPut) {
      this.failNextPut = false;
      throw new Error("simulated KV write failure");
    }
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
  // Test helper
  rawGet(key: string): string | undefined {
    return this.store.get(key);
  }
}

function makeEnv(): { V2EX_PUSH_KV: FakeKV; FIREBASE_SERVICE_ACCOUNT_JSON: string; ADMIN_SECRET: string } {
  return {
    V2EX_PUSH_KV: new FakeKV(),
    FIREBASE_SERVICE_ACCOUNT_JSON: "{}",
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

function userData(fcmToken: string, lastPushed = 0): any {
  return {
    feedUrl: "https://www.v2ex.com/feed/notifications.xml",
    fcmToken,
    deviceType: "iOS",
    updatedAt: Date.now(),
    lastPushed,
  };
}

describe("processUserNotifications dedup", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("does not re-push notifications when userData.lastPushed is stale (KV lag)", async () => {
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue(true);
    const fetchFeed = vi.fn().mockResolvedValue([
      notif("a", 100),
      notif("b", 200),
      notif("c", 300),
    ]);

    const user = userData("tok1", 0);

    const r1 = await processUserNotifications(
      env,
      "user:tok1",
      user,
      [],
      sendPush as any,
      fetchFeed as any,
    );
    expect(r1.pushedCount).toBe(3);
    expect(sendPush).toHaveBeenCalledTimes(3);

    // Simulate: another edge region reads stale userData with lastPushed still 0
    const staleUser = { ...user, lastPushed: 0 };
    sendPush.mockClear();

    const r2 = await processUserNotifications(
      env,
      "user:tok1",
      staleUser,
      [],
      sendPush as any,
      fetchFeed as any,
    );
    expect(r2.pushedCount).toBe(0);
    expect(sendPush).not.toHaveBeenCalled();
  });

  it("handles items with identical published timestamps without duplicates", async () => {
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue(true);
    const fetchFeed = vi.fn().mockResolvedValue([
      notif("a", 500),
      notif("b", 500),
    ]);

    const user = userData("tok2", 0);

    const r1 = await processUserNotifications(
      env,
      "user:tok2",
      user,
      [],
      sendPush as any,
      fetchFeed as any,
    );
    expect(r1.pushedCount).toBe(2);
    expect(sendPush).toHaveBeenCalledTimes(2);

    sendPush.mockClear();
    const r2 = await processUserNotifications(
      env,
      "user:tok2",
      user,
      [],
      sendPush as any,
      fetchFeed as any,
    );
    expect(r2.pushedCount).toBe(0);
    expect(sendPush).not.toHaveBeenCalled();
  });

  it("retries failed pushes on the next run (does not advance cursor on failure)", async () => {
    const env = makeEnv();
    const fetchFeed = vi
      .fn()
      .mockResolvedValue([notif("a", 100), notif("b", 200)]);

    const user = userData("tok3", 0);

    // First push fails, second succeeds
    const sendPush = vi
      .fn()
      .mockResolvedValueOnce(false)
      .mockResolvedValueOnce(true);

    const r1 = await processUserNotifications(
      env,
      "user:tok3",
      user,
      [],
      sendPush as any,
      fetchFeed as any,
    );
    expect(r1.pushedCount).toBe(1);
    expect(sendPush).toHaveBeenCalledTimes(2);

    sendPush.mockClear();
    sendPush.mockResolvedValue(true);

    const r2 = await processUserNotifications(
      env,
      "user:tok3",
      user,
      [],
      sendPush as any,
      fetchFeed as any,
    );
    expect(r2.pushedCount).toBe(1);
    expect(sendPush).toHaveBeenCalledTimes(1);
    expect(sendPush.mock.calls[0][3].notificationId).toBe("a");
  });

  it("caps pushes per run at MAX_PUSH_PER_USER_PER_RUN (most recent first)", async () => {
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue(true);
    const fetchFeed = vi.fn().mockResolvedValue([
      notif("1", 100),
      notif("2", 200),
      notif("3", 300),
      notif("4", 400),
      notif("5", 500),
      notif("6", 600),
      notif("7", 700),
    ]);

    const user = userData("tok4", 0);

    const r1 = await processUserNotifications(
      env,
      "user:tok4",
      user,
      [],
      sendPush as any,
      fetchFeed as any,
    );
    expect(r1.pushedCount).toBe(MAX_PUSH_PER_USER_PER_RUN);
    expect(sendPush).toHaveBeenCalledTimes(MAX_PUSH_PER_USER_PER_RUN);

    const pushedIds = sendPush.mock.calls.map((c) => c[3].notificationId);
    expect(pushedIds).toEqual(["3", "4", "5", "6", "7"]);

    sendPush.mockClear();
    const r2 = await processUserNotifications(
      env,
      "user:tok4",
      user,
      [],
      sendPush as any,
      fetchFeed as any,
    );
    expect(r2.pushedCount).toBe(2);
    expect(sendPush).toHaveBeenCalledTimes(2);
  });

  it("recovers gracefully from a kv.put failure mid-loop (function rejects, next run still completes)", async () => {
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue(true);
    const fetchFeed = vi.fn().mockResolvedValue([
      notif("a", 100),
      notif("b", 200),
    ]);

    const user = userData("tok5", 0);

    // Make the FIRST kv.put throw — that's the userData write after pushing "a".
    // The thrown error should propagate and stop this user's processing.
    env.V2EX_PUSH_KV.failNextPut = true;

    await expect(
      processUserNotifications(
        env,
        "user:tok5",
        user,
        [],
        sendPush as any,
        fetchFeed as any,
      ),
    ).rejects.toThrow("simulated KV write failure");

    expect(sendPush).toHaveBeenCalledTimes(1);

    sendPush.mockClear();
    sendPush.mockResolvedValue(true);

    const r2 = await processUserNotifications(
      env,
      "user:tok5",
      user,
      [],
      sendPush as any,
      fetchFeed as any,
    );
    expect(r2.pushedCount).toBe(2);
    expect(sendPush).toHaveBeenCalledTimes(2);
  });

  it("writes pushedIds even if userData lastPushed is already ahead", async () => {
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue(true);
    const fetchFeed = vi.fn().mockResolvedValue([notif("a", 100)]);

    // Stale pushedIds collection, but with "a" already there
    await env.V2EX_PUSH_KV.put("pushed:tok6", JSON.stringify(["a"]));

    const user = userData("tok6", 0);

    const r1 = await processUserNotifications(
      env,
      "user:tok6",
      user,
      [],
      sendPush as any,
      fetchFeed as any,
    );
    expect(r1.pushedCount).toBe(0);
    expect(sendPush).not.toHaveBeenCalled();
  });

  it("trims pushedIds to PUSHED_IDS_LIMIT", async () => {
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue(true);

    // Pre-fill with 199 IDs
    const initial: string[] = [];
    for (let i = 0; i < PUSHED_IDS_LIMIT - 1; i++) initial.push(`old-${i}`);
    await env.V2EX_PUSH_KV.put("pushed:tok7", JSON.stringify(initial));

    const fetchFeed = vi
      .fn()
      .mockResolvedValue([notif("new-a", 100), notif("new-b", 200)]);

    const user = userData("tok7", 0);

    await processUserNotifications(
      env,
      "user:tok7",
      user,
      [],
      sendPush as any,
      fetchFeed as any,
    );

    const stored = JSON.parse(env.V2EX_PUSH_KV.rawGet("pushed:tok7") || "[]");
    expect(stored.length).toBe(PUSHED_IDS_LIMIT);
    expect(stored).toContain("new-a");
    expect(stored).toContain("new-b");
    // oldest entries dropped
    expect(stored).not.toContain("old-0");
  });

  it("appends history entries for each successful push", async () => {
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue(true);
    const fetchFeed = vi
      .fn()
      .mockResolvedValue([notif("a", 100), notif("b", 200)]);

    const history: any[] = [];
    const user = userData("tok8", 0);

    await processUserNotifications(
      env,
      "user:tok8",
      user,
      history,
      sendPush as any,
      fetchFeed as any,
    );

    expect(history.length).toBe(2);
    expect(history[0].type).toBe("User");
    expect(history[0].title).toBe("Title a");
    expect(history[1].title).toBe("Title b");
  });

  it("skips users without feedUrl or fcmToken", async () => {
    const env = makeEnv();
    const sendPush = vi.fn().mockResolvedValue(true);
    const fetchFeed = vi.fn();

    const r1 = await processUserNotifications(
      env,
      "user:tok9",
      { feedUrl: "", fcmToken: "tok9", lastPushed: 0 },
      [],
      sendPush as any,
      fetchFeed as any,
    );
    expect(r1.pushedCount).toBe(0);
    expect(sendPush).not.toHaveBeenCalled();
    expect(fetchFeed).not.toHaveBeenCalled();

    const r2 = await processUserNotifications(
      env,
      "user:tok10",
      { feedUrl: "http://x", fcmToken: "", lastPushed: 0 },
      [],
      sendPush as any,
      fetchFeed as any,
    );
    expect(r2.pushedCount).toBe(0);
  });
});

describe("POST /unregister", () => {
  function request(body: unknown): Request {
    return new Request("https://push.test/unregister", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  }

  it("drops the device and its dedup cursor", async () => {
    const env = makeEnv();
    await env.V2EX_PUSH_KV.put("user:tok1", JSON.stringify({ fcmToken: "tok1" }));
    await env.V2EX_PUSH_KV.put("pushed:tok1", JSON.stringify(["a"]));

    const response = await worker.fetch(
      request({ fcmToken: "tok1" }),
      env as any,
      {} as any,
    );

    expect(response.status).toBe(200);
    expect(env.V2EX_PUSH_KV.rawGet("user:tok1")).toBeUndefined();
    expect(env.V2EX_PUSH_KV.rawGet("pushed:tok1")).toBeUndefined();
  });

  it("rejects a payload without a token", async () => {
    const env = makeEnv();
    const response = await worker.fetch(request({}), env as any, {} as any);
    expect(response.status).toBe(400);
  });
});

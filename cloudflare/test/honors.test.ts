import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  handleHonorJoin,
  handleHonorsList,
  HONOR_INDEX_KEY,
  HONOR_KEY_PREFIX,
  HONOR_NAME_KEY_PREFIX,
} from "../src/honors";

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
  rawGet(key: string): string | undefined {
    return this.store.get(key);
  }
}

function makeEnv(withSecret = true): any {
  return {
    V2EX_PUSH_KV: new FakeKV(),
    FIREBASE_SERVICE_ACCOUNT_JSON: "{}",
    ADMIN_SECRET: "test",
    ...(withSecret ? { REVENUECAT_SECRET_KEY: "sk_test" } : {}),
  };
}

/** RevenueCat subscriber 响应：pro 权益可有可无、可带过期时间。 */
function rcSubscriber(entitlements: Record<string, any>): any {
  return { subscriber: { entitlements } };
}

function jsonRequest(body: any): Request {
  return new Request("https://worker/honors/join", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

describe("honor wall", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(1_700_000_000_000);
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("503s when the RevenueCat secret is not configured", async () => {
    const res = await handleHonorJoin(
      jsonRequest({ name: "livid", rcUserId: "u1" }),
      makeEnv(false),
    );
    expect(res.status).toBe(503);
  });

  it("400s on missing/overlong name and missing rcUserId", async () => {
    const env = makeEnv();
    expect((await handleHonorJoin(jsonRequest({ rcUserId: "u1" }), env)).status).toBe(400);
    expect((await handleHonorJoin(jsonRequest({ name: "x".repeat(25), rcUserId: "u1" }), env)).status).toBe(400);
    expect((await handleHonorJoin(jsonRequest({ name: "livid" }), env)).status).toBe(400);
  });

  it("403s when RevenueCat reports no active pro entitlement", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(JSON.stringify(rcSubscriber({})), { status: 200 })),
    );
    const res = await handleHonorJoin(
      jsonRequest({ name: "livid", rcUserId: "u1" }),
      makeEnv(),
    );
    expect(res.status).toBe(403);
  });

  it("403s when the entitlement is expired", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(
            JSON.stringify(
              rcSubscriber({
                pro: { expires_date: new Date(Date.now() - 1000).toISOString() },
              }),
            ),
            { status: 200 },
          ),
      ),
    );
    const res = await handleHonorJoin(
      jsonRequest({ name: "livid", rcUserId: "u1" }),
      makeEnv(),
    );
    expect(res.status).toBe(403);
  });

  it("engraves a lifetime buyer permanently: no expires_date, entry + index + name lock", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(
            JSON.stringify(rcSubscriber({ pro: { expires_date: null } })),
            { status: 200 },
          ),
      ),
    );
    const env = makeEnv();
    const res = await handleHonorJoin(
      jsonRequest({ name: "livid", rcUserId: "u1" }),
      env,
    );
    expect(res.status).toBe(200);
    const body: any = await res.json();
    expect(body).toEqual({ success: true, already: false });

    const raw = env.V2EX_PUSH_KV.rawGet(`${HONOR_KEY_PREFIX}u1`);
    expect(JSON.parse(raw!)).toEqual({ name: "livid", joinedAt: 1_700_000_000_000 });
    expect(env.V2EX_PUSH_KV.rawGet(`${HONOR_NAME_KEY_PREFIX}livid`)).toBe("u1");
    expect(JSON.parse(env.V2EX_PUSH_KV.rawGet(HONOR_INDEX_KEY)!)).toEqual(["u1"]);
  });

  it("re-joining with the same purchase reports already and keeps the original engraving", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(JSON.stringify(rcSubscriber({ pro: {} })), { status: 200 }),
      ),
    );
    const env = makeEnv();
    await handleHonorJoin(jsonRequest({ name: "livid", rcUserId: "u1" }), env);

    vi.setSystemTime(1_700_090_000_000); // 一年后再来
    const res = await handleHonorJoin(
      jsonRequest({ name: "someone else", rcUserId: "u1" }),
      env,
    );
    const body: any = await res.json();
    expect(body.already).toBe(true);
    // 首次铭刻保持原样：既不改名也不改时间。
    expect(JSON.parse(env.V2EX_PUSH_KV.rawGet(`${HONOR_KEY_PREFIX}u1`)!)).toEqual({
      name: "livid",
      joinedAt: 1_700_000_000_000,
    });
  });

  it("409s when the display name is already engraved by someone else", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(JSON.stringify(rcSubscriber({ pro: {} })), { status: 200 }),
      ),
    );
    const env = makeEnv();
    await handleHonorJoin(jsonRequest({ name: "Livid", rcUserId: "u1" }), env);
    const res = await handleHonorJoin(jsonRequest({ name: "livid", rcUserId: "u2" }), env);
    expect(res.status).toBe(409);
  });

  it("lists entries sorted by engraving time", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(JSON.stringify(rcSubscriber({ pro: {} })), { status: 200 }),
      ),
    );
    const env = makeEnv();
    await handleHonorJoin(jsonRequest({ name: "second", rcUserId: "u2" }), env);
    vi.setSystemTime(Date.now() + 1000);
    await handleHonorJoin(jsonRequest({ name: "first", rcUserId: "u1" }), env);

    const res = await handleHonorsList(env);
    const body: any = await res.json();
    expect(body.honors.map((h: any) => h.name)).toEqual(["second", "first"]);
  });

  it("list survives a corrupt entry", async () => {
    const env = makeEnv();
    await env.V2EX_PUSH_KV.put(HONOR_INDEX_KEY, JSON.stringify(["bad", "u1"]));
    await env.V2EX_PUSH_KV.put(`${HONOR_KEY_PREFIX}bad`, "{not json");
    await env.V2EX_PUSH_KV.put(
      `${HONOR_KEY_PREFIX}u1`,
      JSON.stringify({ name: "livid", joinedAt: 1 }),
    );

    const res = await handleHonorsList(env);
    const body: any = await res.json();
    expect(body.honors).toEqual([{ name: "livid", joinedAt: 1 }]);
  });
});
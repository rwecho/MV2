/**
 * 荣誉墙（永久买断用户名录）。
 *
 * RevenueCat 客户端侧拿不到"谁买过"，所以买家在购买后主动来登记：客户端把
 * {name, rcUserId} POST 到 /honors/join，这里用 RevenueCat REST API 核实该
 * app user id 确实持有 `pro` 权益（RevenueCat 是收据校验的真值来源），通过后
 * 写进 KV。**永久**：一经登记不随退款/到期移除（此为产品要求）。
 *
 * KV 布局（复用 V2EX_PUSH_KV，前缀隔离）：
 *   honor:{rcUserId}          → HonorEntry JSON（一个买断 id 一条，永久）
 *   honor:name:{lower(name)}  → rcUserId（展示名唯一，防冒用）
 *   honor:index               → rcUserId 数组（列表顺序源，量级小可全读）
 */

export interface HonorEntry {
  name: string;
  joinedAt: number;
}

export const HONOR_KEY_PREFIX = "honor:";
export const HONOR_NAME_KEY_PREFIX = "honor:name:";
export const HONOR_INDEX_KEY = "honor:index";
/** 展示名长度上限（字符）。 */
export const MAX_HONOR_NAME_LENGTH = 24;
/**
 * 荣誉墙容量护栏。产品承诺"凡购买必上墙、永久保存"，所以这个数故意放到
 * 几乎打不满 —— 真到 10000 说明产品成了，届时迁 D1 再谈。
 */
export const MAX_HONORS = 10_000;

const RC_API_BASE = "https://api.revenuecat.com/v1/subscribers";

/**
 * 用 RevenueCat REST API 核实 `pro` 权益。
 *
 * 终身买断的 entitlement 没有 `expires_date`（永不过期）；带过期时间的
 * （将来若有订阅型）按过期时间判断。
 */
export async function verifyProEntitlement(
  env: Env,
  appUserId: string,
): Promise<boolean> {
  if (!env.REVENUECAT_SECRET_KEY) return false;
  try {
    const res = await fetch(`${RC_API_BASE}/${encodeURIComponent(appUserId)}`, {
      headers: {
        Authorization: `Bearer ${env.REVENUECAT_SECRET_KEY}`,
        "Content-Type": "application/json",
      },
    });
    if (!res.ok) return false;
    const body: any = await res.json();
    const entitlement = body?.subscriber?.entitlements?.pro;
    if (!entitlement) return false;
    if (!entitlement.expires_date) return true;
    return new Date(entitlement.expires_date).getTime() > Date.now();
  } catch {
    return false;
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function handleHonorJoin(
  request: Request,
  env: Env,
): Promise<Response> {
  if (!env.REVENUECAT_SECRET_KEY) {
    return json({ error: "honors_not_configured" }, 503);
  }

  let data: any;
  try {
    data = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const name = typeof data?.name === "string" ? data.name.trim() : "";
  const rcUserId =
    typeof data?.rcUserId === "string" ? data.rcUserId.trim() : "";

  if (!name || name.length > MAX_HONOR_NAME_LENGTH) {
    return json(
      { error: "invalid_name", max: MAX_HONOR_NAME_LENGTH },
      400,
    );
  }
  if (!rcUserId || rcUserId.length > 128) {
    return json({ error: "invalid_rc_user_id" }, 400);
  }

  const entitled = await verifyProEntitlement(env, rcUserId);
  if (!entitled) {
    return json({ error: "not_entitled" }, 403);
  }

  const entryKey = `${HONOR_KEY_PREFIX}${rcUserId}`;
  const existing = await env.V2EX_PUSH_KV.get(entryKey);
  if (existing) {
    // 一次买断只铭刻一次；重装/换机重复登记不算改名。
    return json({ success: true, already: true });
  }

  // 展示名唯一（大小写不敏感），先到先得，防止有人顶替别人的名字。
  const nameKey = `${HONOR_NAME_KEY_PREFIX}${name.toLowerCase()}`;
  const nameOwner = await env.V2EX_PUSH_KV.get(nameKey);
  if (nameOwner && nameOwner !== rcUserId) {
    return json({ error: "name_taken" }, 409);
  }

  const indexRaw = await env.V2EX_PUSH_KV.get(HONOR_INDEX_KEY);
  const index: string[] = indexRaw ? JSON.parse(indexRaw) : [];
  if (index.length >= MAX_HONORS) {
    return json({ error: "wall_full", max: MAX_HONORS }, 409);
  }

  const entry: HonorEntry = { name, joinedAt: Date.now() };
  await env.V2EX_PUSH_KV.put(entryKey, JSON.stringify(entry));
  await env.V2EX_PUSH_KV.put(nameKey, rcUserId);
  index.push(rcUserId);
  await env.V2EX_PUSH_KV.put(HONOR_INDEX_KEY, JSON.stringify(index));

  return json({ success: true, already: false });
}

export async function handleHonorsList(env: Env): Promise<Response> {
  const indexRaw = await env.V2EX_PUSH_KV.get(HONOR_INDEX_KEY);
  const index: string[] = indexRaw ? JSON.parse(indexRaw) : [];

  const honors: HonorEntry[] = [];
  for (const rcUserId of index) {
    const raw = await env.V2EX_PUSH_KV.get(`${HONOR_KEY_PREFIX}${rcUserId}`);
    if (!raw) continue;
    try {
      const entry = JSON.parse(raw);
      if (typeof entry?.name === "string" && typeof entry?.joinedAt === "number") {
        honors.push({ name: entry.name, joinedAt: entry.joinedAt });
      }
    } catch {
      // 单条损坏跳过，不影响整面墙。
    }
  }

  // 最早的支持者排最前 —— 永久荣誉，按铭刻时间。
  honors.sort((a, b) => a.joinedAt - b.joinedAt);
  return json({ honors });
}
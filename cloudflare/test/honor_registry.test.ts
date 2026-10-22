import { describe, it, expect } from 'vitest';
import { HonorRegistry, verifiedPurchase, handleHonorV2 } from '../src/honor_registry';
class Store {
  data = new Map<string, any>();
  queue: Promise<any> = Promise.resolve();
  async get(k: string) { return this.data.get(k); }
  async put(k: string, v: any) { this.data.set(k, structuredClone(v)); }
  async delete(k: string) { return this.data.delete(k); }
  async list({ prefix }: { prefix: string }) { return new Map([...this.data].filter(([k]) => k.startsWith(prefix))); }
  transaction(fn: (s: Store) => Promise<any>) {
    const result = this.queue.then(() => fn(this));
    this.queue = result.catch(() => {});
    return result;
  }
}
function registry() { return new HonorRegistry({ storage: new Store() } as any); }
async function call(r: HonorRegistry, body: object) {
  const res = await r.fetch(new Request('https://registry/', { method: 'POST', body: JSON.stringify(body) }));
  return { status: res.status, body: await res.json() as any };
}
describe('transaction-owned honor registry', () => {
  it('rejects unsigned purchase proofs', async () => {
    await expect(verifiedPurchase('invalid', {} as any)).rejects.toBeDefined();
    const proof = `e30.${Buffer.from(JSON.stringify({ environment: 'Sandbox' })).toString('base64url')}.invalid`;
    await expect(verifiedPurchase(proof, {} as any)).rejects.toBeDefined();
  });
  it('never accepts a RevenueCat ID alone', async () => {
    const res = await handleHonorV2(new Request('https://worker/honors/v2/join', {
      method: 'POST', body: JSON.stringify({ name: 'x', rcUserId: 'known-buyer' }),
    }), { HONOR_REGISTRY: {} } as any);
    expect(res.status).toBe(401);
  });
  it('concurrent claims cannot occupy the same name', async () => {
    const r = registry();
    const responses = await Promise.all([
      call(r, { action: 'join', purchase: 'a', name: 'Same' }),
      call(r, { action: 'join', purchase: 'b', name: 'same' }),
    ]);
    expect(responses.map(r => r.status).sort()).toEqual([200, 409]);
    expect((await call(r, { action: 'list' })).body.honors).toHaveLength(1);
  });
  it('restore and rename keep one record and original ordering', async () => {
    const r = registry();
    await call(r, { action: 'join', purchase: 'original', name: 'first' });
    const original = (await call(r, { action: 'status', purchase: 'original' })).body.entry;
    await call(r, { action: 'join', purchase: 'original', name: 'updated' });
    expect((await call(r, { action: 'list' })).body.honors).toEqual([{ name: 'updated', joinedAt: original.joinedAt }]);
  });
  it('hide and re-display do not create another slot', async () => {
    const r = registry();
    await call(r, { action: 'join', purchase: 'a', name: 'one' });
    await call(r, { action: 'hide', purchase: 'a' });
    expect((await call(r, { action: 'list' })).body.honors).toEqual([]);
    expect((await call(r, { action: 'status', purchase: 'a' })).body.entry.hidden).toBe(true);
    await call(r, { action: 'join', purchase: 'a', name: 'one' });
    expect((await call(r, { action: 'list' })).body.honors).toHaveLength(1);
  });
  it('migrates a verified legacy owner without losing the name', async () => {
    const r = registry();
    await call(r, { action: 'seed', records: [['old-rc', { name: 'old', joinedAt: 123 }]] });
    await call(r, { action: 'status', purchase: 'apple', legacyIds: ['old-rc'] });
    await call(r, { action: 'join', purchase: 'apple', name: 'new' });
    expect((await call(r, { action: 'list' })).body.honors).toEqual([{ name: 'new', joinedAt: 123 }]);
    await call(r, { action: 'seed', records: [['old-rc', { name: 'old', joinedAt: 123 }]] });
    expect((await call(r, { action: 'list' })).body.honors).toHaveLength(1);
  });
});

// Exercise the HTTP orchestration separately from Apple's cryptographic code.
// The malformed-proof tests above always use the real verifier.
import { vi, afterEach } from 'vitest';
import { SignedDataVerifier } from '@apple/app-store-server-library';
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });
it('authenticated restoration uses transaction identity across RevenueCat aliases', async () => {
  const r = registry();
  vi.spyOn(SignedDataVerifier.prototype, 'verifyAndDecodeTransaction').mockResolvedValue({
    environment: 'Production', productId: 'mv2.pro.lifetime', type: 'Non-Consumable',
    originalTransactionId: 'original', transactionId: 'transaction',
  } as any);
  vi.stubGlobal('fetch', vi.fn().mockImplementation(async () => Response.json({ subscriber: {
    original_app_user_id: 'first-rc', entitlements: { pro: { expires_date: null } },
    non_subscriptions: { 'mv2.pro.lifetime': [{ store_transaction_id: 'transaction' }] },
  } })));
  const env: any = {
    REVENUECAT_SECRET_KEY: 'test', V2EX_PUSH_KV: { get: async () => null },
    HONOR_REGISTRY: { idFromName: (n: string) => n, get: () => ({ fetch: (req: Request) => r.fetch(req) }) },
  };
  const proof = `e30.${Buffer.from(JSON.stringify({ environment: 'Production' })).toString('base64url')}.test`;
  const send = (action: string, rcUserId: string, name?: string) => handleHonorV2(
    new Request(`https://worker/honors/v2/${action}`, {
      method: 'POST', body: JSON.stringify({ proof, rcUserId, name }),
    }), env);
  expect((await send('join', 'old-alias', 'name')).status).toBe(200);
  const restored = await send('status', 'new-alias');
  expect((await restored.json() as any).entry.name).toBe('name');
  expect((await send('join', 'new-alias', 'changed')).status).toBe(200);
  expect((await call(r, { action: 'list' })).body.honors).toHaveLength(1);
  vi.stubGlobal('fetch', vi.fn().mockImplementation(async () => Response.json({ subscriber: {
    entitlements: { pro: {} }, non_subscriptions: { 'mv2.pro.lifetime': [{ store_transaction_id: 'someone-else' }] },
  } })));
  expect((await send('hide', 'unrelated-customer')).status).toBe(403);
});

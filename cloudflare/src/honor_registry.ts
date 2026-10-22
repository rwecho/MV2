import type { Env } from './index';
import { Buffer } from 'node:buffer';
import { verifiedGooglePurchase } from './google_purchase';
import { appleRootG3 } from './certificates/apple-root';

export interface WallRecord {
  name: string;
  joinedAt: number;
  hidden: boolean;
  legacyId?: string;
}

// One Durable Object owns the wall. A storage transaction makes name claims,
// purchase deduplication and visibility updates atomic across Worker instances.
export class HonorRegistry {
  constructor(private state: DurableObjectState) {}
  async fetch(request: Request): Promise<Response> {
    const { purchase, action, name, legacyIds, records } = await request.json() as {
      purchase: string; action: string; name?: string; legacyIds?: string[]; records?: [string, WallRecord][];
    };
    const result = await this.state.storage.transaction(async tx => {
      if (action === 'seed') {
        if (!await tx.get('seeded')) {
          for (const [id, record] of records ?? []) {
            await tx.put(`purchase:legacy:${id}`, { ...record, hidden: false, legacyId: id });
            await tx.put(`name:${record.name.toLowerCase()}`, `legacy:${id}`);
          }
          await tx.put('seeded', true);
        }
        return { seeded: true };
      }
      if (action === 'initialized') return { seeded: !!await tx.get('seeded') };
      if (action === 'list') {
        const records = await tx.list<WallRecord>({ prefix: 'purchase:' });
        return { honors: [...records.values()].filter(r => !r.hidden)
          .sort((a, b) => a.joinedAt - b.joinedAt)
          .map(({ name, joinedAt }) => ({ name, joinedAt })) };
      }
      const key = `purchase:${purchase}`;
      let existing = await tx.get<WallRecord>(key);
      if (!existing) {
        for (const id of legacyIds ?? []) {
          const legacy = await tx.get<WallRecord>(`purchase:legacy:${id}`);
          if (!legacy) continue;
          existing = legacy;
          await tx.delete(`purchase:legacy:${id}`);
          await tx.put(key, legacy);
          await tx.put(`name:${legacy.name.toLowerCase()}`, purchase);
          break;
        }
      }
      if (action === 'status') return { entry: existing ?? null };
      if (action === 'hide') {
        if (existing) await tx.put(key, { ...existing, hidden: true });
        return { entry: existing ? { ...existing, hidden: true } : null };
      }
      if (action !== 'join' || !name || name.length > 24) return { error: 'invalid_name' };
      const owner = await tx.get<string>(`name:${name.toLowerCase()}`);
      if (owner && owner !== purchase) return { error: 'name_taken' };
      if (existing && existing.name.toLowerCase() !== name.toLowerCase()) {
        await tx.delete(`name:${existing.name.toLowerCase()}`);
      }
      const entry = { name, joinedAt: existing?.joinedAt ?? Date.now(), hidden: false };
      await tx.put(`name:${name.toLowerCase()}`, purchase);
      await tx.put(key, entry);
      return { entry, already: !!existing };
    });
    return Response.json(result, { status: 'error' in result ? 409 : 200 });
  }
}

export async function verifiedPurchase(proof: string, env: Env): Promise<{ purchase: string; transactionId: string }> {
  if (proof.startsWith('google:')) return verifiedGooglePurchase(proof.slice(7), env);
  // Apple's Node library initializes randomness; load it inside the request
  // handler rather than Workers' restricted global scope.
  const { SignedDataVerifier, Environment } = await import('@apple/app-store-server-library');
  // This untrusted hint only selects a verifier; the signature and environment
  // are still checked by Apple's library before any data is trusted.
  const hint = JSON.parse(Buffer.from(proof.split('.')[1], 'base64url').toString()).environment;
  if (hint !== 'Sandbox' && hint !== 'Production') throw new Error('invalid_environment');
  const environment = hint === 'Sandbox' ? Environment.SANDBOX : Environment.PRODUCTION;
  const verifier = new SignedDataVerifier(
    [Buffer.from(appleRootG3, 'base64')], false, environment,
    'tech.zb.v2ex.maui.app', 6757801437,
  );
  const transaction = await verifier.verifyAndDecodeTransaction(proof);
  if (!transaction.transactionId || transaction.productId !== 'mv2.pro.lifetime' ||
      transaction.type !== 'Non-Consumable' || transaction.revocationDate ||
      !transaction.originalTransactionId) throw new Error('invalid_purchase');
  // The same purchase keeps this ID across restores and RevenueCat aliases.
  return { purchase: `${environment}:${transaction.originalTransactionId}`,
    transactionId: transaction.transactionId! };
}

export async function handleHonorV2(request: Request, env: Env): Promise<Response> {
  if (!env.HONOR_REGISTRY) return Response.json({ error: 'not_configured' }, { status: 503 });
  const action = new URL(request.url).pathname.split('/').pop()!;
  let purchase = '';
  let name: string | undefined;
  let legacyIds: string[] = [];
  if (action === 'list') {
    try {
      const body = await request.clone().json() as { proof?: string };
      if (typeof body.proof === 'string' && body.proof.length <= 32000)
        purchase = (await verifiedPurchase(body.proof, env)).purchase;
    } catch { /* Anonymous visitors see the production wall. */ }
  }
  if (action !== 'list') {
    let body: { proof?: string; name?: string; rcUserId?: string };
    try { body = await request.json() as typeof body; }
    catch { return Response.json({ error: 'invalid_request' }, { status: 400 }); }
    if (typeof body.proof !== 'string' || body.proof.length > 32000)
      return Response.json({ error: 'proof_required' }, { status: 401 });
    if (!env.REVENUECAT_SECRET_KEY || (body.proof.startsWith('google:') && !env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON))
      return Response.json({ error: 'verification_unavailable' }, { status: 503 });
    try {
      const verified = await verifiedPurchase(body.proof, env);
      purchase = verified.purchase;
      // Check current entitlement too: a previously valid JWS can outlive a refund.
      if (!env.REVENUECAT_SECRET_KEY || typeof body.rcUserId !== 'string') throw new Error();
      const res = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(body.rcUserId)}`,
        { headers: { Authorization: `Bearer ${env.REVENUECAT_SECRET_KEY}` } });
      if (!res.ok) return Response.json({ error: 'verification_unavailable' }, { status: 503 });
      const subscriber: any = (await res.json() as any).subscriber;
      const entitlement = subscriber?.entitlements?.pro;
      const purchases = subscriber?.non_subscriptions?.['mv2.pro.lifetime'] ?? [];
      if (!entitlement || (entitlement.expires_date && Date.parse(entitlement.expires_date) <= Date.now()) ||
          !purchases.some((p: any) => String(p.store_transaction_id) === verified.transactionId)) throw new Error();
      legacyIds = [body.rcUserId, subscriber.original_app_user_id].filter((id): id is string => typeof id === 'string');
    }
    catch { return Response.json({ error: 'invalid_purchase' }, { status: 403 }); }
    name = typeof body.name === 'string' ? body.name.trim() : undefined;
  }
  if (!['list', 'status', 'join', 'hide'].includes(action)) return new Response(null, { status: 404 });
  const sandbox = purchase.startsWith('Sandbox:');
  const id = env.HONOR_REGISTRY.idFromName(sandbox ? 'wall-v2-sandbox' : 'wall-v2');
  const registry = env.HONOR_REGISTRY.get(id);
  const initialized = await registry.fetch(new Request('https://registry/', {
    method: 'POST', body: JSON.stringify({ action: 'initialized' }) }));
  if (!(await initialized.json() as { seeded: boolean }).seeded) {
    const ids: string[] = sandbox ? [] : JSON.parse(await env.V2EX_PUSH_KV.get('honor:index') ?? '[]');
    const records: [string, WallRecord][] = [];
    for (const legacyId of ids) {
      const raw = await env.V2EX_PUSH_KV.get(`honor:${legacyId}`);
      if (raw) { try { records.push([legacyId, JSON.parse(raw)]); } catch {} }
    }
    await registry.fetch(new Request('https://registry/', {
      method: 'POST', body: JSON.stringify({ action: 'seed', records }) }));
  }
  return registry.fetch(new Request('https://registry/', {
    method: 'POST', body: JSON.stringify({ purchase, action, name, legacyIds }),
  }));
}

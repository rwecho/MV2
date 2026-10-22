import { SignJWT, importPKCS8 } from 'jose';
import type { Env } from './index';

export async function verifiedGooglePurchase(token: string, env: Env) {
  if (!env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON) throw new Error('google_not_configured');
  const account = JSON.parse(env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON);
  const key = await importPKCS8(account.private_key, 'RS256');
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/androidpublisher' })
    .setProtectedHeader({ alg: 'RS256' }).setIssuer(account.client_email)
    .setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('5m').sign(key);
  const auth = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion,
    }),
  });
  if (!auth.ok) throw new Error('google_unavailable');
  const credentials = await auth.json() as { access_token: string };
  const product = 'mv2.pro.lifetime';
  const res = await fetch(`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/tech.zb.v2ex.maui.app/purchases/products/${product}/tokens/${encodeURIComponent(token)}`, {
    headers: { Authorization: `Bearer ${credentials.access_token}` },
  });
  if (!res.ok) throw new Error('invalid_google_purchase');
  const purchase = await res.json() as {
    purchaseState?: number; consumptionState?: number; purchaseType?: number;
    orderId?: string; productId?: string;
  };
  if (purchase.purchaseState !== 0 || purchase.consumptionState !== 0 ||
      (purchase.productId && purchase.productId !== product)) throw new Error('invalid_google_purchase');
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  const id = [...new Uint8Array(hash)].map(b => b.toString(16).padStart(2, '0')).join('');
  return {
    purchase: `${purchase.purchaseType === 0 ? 'Sandbox' : 'Production'}:GooglePlay:${id}`,
    transactionId: purchase.orderId ?? '',
  };
}

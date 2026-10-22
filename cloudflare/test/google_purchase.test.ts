import { it, expect, vi, afterEach } from 'vitest';
import { generateKeyPair, exportPKCS8 } from 'jose';
import { webcrypto } from 'node:crypto';
import { verifiedGooglePurchase } from '../src/google_purchase';
afterEach(() => vi.unstubAllGlobals());
async function setup(state = 0, test = false) {
  const { privateKey } = await generateKeyPair('RS256', { extractable: true });
  const pem = await exportPKCS8(privateKey);
  vi.stubGlobal('crypto', webcrypto);
  vi.stubGlobal('fetch', vi.fn(async (url: string) => url.includes('oauth2')
    ? Response.json({ access_token: 'test-access' })
    : Response.json({ purchaseState: state, consumptionState: 0,
      productId: 'mv2.pro.lifetime', orderId: 'GPA.test', ...(test ? { purchaseType: 0 } : {}) })));
  return { GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: JSON.stringify({
    client_email: 'test@example.com', private_key: pem,
  }) } as any;
}
it('Google restore uses the same token-derived purchase ID and keeps tokens private', async () => {
  const env = await setup();
  const a = await verifiedGooglePurchase('private-token', env);
  const b = await verifiedGooglePurchase('private-token', env);
  expect(a).toEqual(b);
  expect(a.purchase).toMatch(/^Production:GooglePlay:[a-f0-9]{64}$/);
  expect(a.purchase).not.toContain('private-token');
  expect(a.transactionId).toBe('GPA.test');
});
it('Google pending and cancelled purchases cannot register', async () => {
  for (const state of [1, 2]) {
    const env = await setup(state);
    await expect(verifiedGooglePurchase('token', env)).rejects.toThrow('invalid_google_purchase');
  }
});
it('Google test purchases use the Sandbox wall', async () => {
  const env = await setup(0, true);
  expect((await verifiedGooglePurchase('token', env)).purchase).toMatch(/^Sandbox:/);
});
it('Google verification fails closed without credentials', async () => {
  await expect(verifiedGooglePurchase('token', {} as any)).rejects.toThrow('google_not_configured');
});

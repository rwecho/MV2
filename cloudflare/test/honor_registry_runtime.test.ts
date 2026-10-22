import { it, expect } from 'vitest';
import { Miniflare } from 'miniflare';
import { build } from 'esbuild';

it('real Durable Object storage serializes simultaneous registrations and migrations', async () => {
  const bundled = await build({
    stdin: {
      contents: `export { HonorRegistry } from './src/honor_registry'; export default { fetch() { return new Response('not public'); } };`,
      resolveDir: process.cwd(), loader: 'ts',
    }, bundle: true, write: false, format: 'esm', platform: 'node',
  });
  const mf = new Miniflare({
    modules: true, script: bundled.outputFiles[0].text,
    compatibilityDate: '2025-06-01', compatibilityFlags: ['nodejs_compat'],
    durableObjects: { REGISTRY: { className: 'HonorRegistry', useSQLite: true } },
  });
  try {
    const ns = await mf.getDurableObjectNamespace('REGISTRY');
    const registry = ns.get(ns.idFromName('test-wall'));
    const call = (body: object) => registry.fetch('https://registry/', {
      method: 'POST', body: JSON.stringify(body),
    });
    await call({ action: 'seed', records: [['legacy', { name: 'old', joinedAt: 123 }]] });
    const sameName = await Promise.all(Array.from({ length: 8 }, (_, i) =>
      call({ action: 'join', purchase: `buyer-${i}`, name: 'same' })));
    expect(sameName.filter(r => r.status === 200)).toHaveLength(1);
    expect(sameName.filter(r => r.status === 409)).toHaveLength(7);
    await Promise.all(Array.from({ length: 5 }, () =>
      call({ action: 'status', purchase: 'restored', legacyIds: ['legacy'] })));
    const listed: any = await (await call({ action: 'list' })).json();
    expect(listed.honors).toHaveLength(2);
    expect(listed.honors.filter((e: any) => e.name === 'old')).toHaveLength(1);
    await call({ action: 'hide', purchase: 'restored' });
    const hidden: any = await (await call({ action: 'list' })).json();
    expect(hidden.honors).toHaveLength(1);
  } finally { await mf.dispose(); }
}, 20000);

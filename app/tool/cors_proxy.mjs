// Minimal local CORS proxy for running the Flutter Web build against v2ex.
//
// Usage: node tool/cors_proxy.mjs [port]   (default port 9090)
//
// Routes:
//   /v2ex/*   -> https://www.v2ex.com/*
//   /sov2ex/* -> https://www.sov2ex.com/*
//
// Every response gets `Access-Control-Allow-Origin: *` and preflight
// (OPTIONS) requests are answered directly, so the browser lets the app
// at http://127.0.0.1:8090 read the data.
import http from 'node:http';

const PORT = Number(process.argv[2] ?? 9090);
const ROUTES = {
  '/v2ex/': 'www.v2ex.com',
  '/sov2ex/': 'www.sov2ex.com',
};

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
  'Access-Control-Allow-Headers': '*',
};

const server = http.createServer(async (req, res) => {
  const cors = { ...CORS_HEADERS };

  if (req.method === 'OPTIONS') {
    res.writeHead(204, cors);
    res.end();
    return;
  }

  const route = Object.keys(ROUTES).find((p) => req.url.startsWith(p));
  if (!route) {
    res.writeHead(404, cors).end('unknown proxy route');
    return;
  }
  const target = ROUTES[route];
  const path = req.url.slice(route.length - 1); // keep leading '/'

  const headers = { ...req.headers };
  delete headers.host;
  delete headers.origin;
  delete headers.referer;

  try {
    const upstream = await fetch(`https://${target}${path}`, {
      method: req.method,
      headers,
      body: ['GET', 'HEAD'].includes(req.method) ? undefined : req,
      redirect: 'follow',
    });
    upstream.headers.forEach((value, key) => {
      if (key.startsWith('access-control-') || key === 'content-encoding' || key === 'transfer-encoding') return;
      res.setHeader(key, value);
    });
    Object.entries(cors).forEach(([k, v]) => res.setHeader(k, v));
    res.writeHead(upstream.status);
    if (upstream.body) {
      const reader = upstream.body.getReader();
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        res.write(value);
      }
    }
    res.end();
  } catch (err) {
    res.writeHead(502, cors).end(`proxy error: ${err?.message ?? err}`);
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`CORS proxy listening on http://127.0.0.1:${PORT}`);
  for (const [route, target] of Object.entries(ROUTES)) {
    console.log(`  ${route}* -> https://${target}/*`);
  }
});

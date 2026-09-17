# V2EX Push Service (Cloudflare Worker)

Polls every registered account's V2EX notification Atom feed and delivers new
items to the device. Two transports are supported:

| Device `deviceType` | Transport | Credentials |
|---|---|---|
| `iOS`, `Android`, `macOS`, … | Firebase Cloud Messaging (HTTP v1) | `FIREBASE_SERVICE_ACCOUNT_JSON` |
| `hms`, `ohos` | Huawei **HMS Push Kit** REST API | `HMS_SERVICE_ACCOUNT_JSON` + `HMS_APP_ID` |

The KV record shape is unchanged across transports — the device token always
lives in `fcmToken`, and the transport is selected by `deviceType`:

```jsonc
// user:{token}
{
  "feedUrl": "https://www.v2ex.com/feed/notifications.xml?once=...",
  "fcmToken": "<FCM registration token | HMS push token>",
  "deviceType": "iOS",        // or "hms" / "ohos"
  "updatedAt": 1700000000000,
  "lastPushed": 1700000000000
}
```

Existing records without a `deviceType` keep going through FCM.

## Endpoints

* `POST /register` — `{feedUrl, fcmToken, deviceType}`. Idempotent; preserves the
  `lastPushed` dedup cursor on re-registration (token refresh, reinstall).
* `POST /unregister` — `{fcmToken}`. Drops the device and its dedup cursor.
* `POST /honors/join` — `{name, rcUserId}`. 荣誉墙登记： verifies the `pro`
  entitlement via the RevenueCat REST API (`REVENUECAT_SECRET_KEY`), then
  engraves `{name, joinedAt}` in KV. **Permanent by product design** — entries
  are never removed, display names are globally unique (case-insensitive,
  first-come-first-served), one entry per `rcUserId`.
* `GET /honors` — the wall: `{honors: [{name, joinedAt}]}` sorted by engraving
  time (earliest supporters first).
* `GET /health` — liveness.
* `GET /admin?secret=…` — small stats/history page.
* Scheduled (`*/15 * * * *`) — the polling run.

## HMS delivery

`src/utils/hms.ts` implements the HarmonyOS path:

1. **OAuth2 access token.** The AGC *service account* key file is signed into a
   short-lived RS256 JWT assertion (`iss`/`sub` = `client_email` or `client_id`,
   `aud` = the account's `token_uri`, header `kid` = `private_key_id`). The
   assertion is exchanged at
   `https://oauth2.cloud.huawei.com/oauth2/v2/token` with
   `grant_type=client_credentials`,
   `client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer`
   and `client_assertion=<JWT>`.
2. **KV cache.** The token is stored under `hms_access_token` with an
   `expirationTtl` five minutes shorter than `expires_in`, so the cron never
   fetches a token per message.
3. **Send.** `POST https://push-api.cloud.huawei.com/v1/{HMS_APP_ID}/messages:send`
   with `Authorization: Bearer <token>`; the notification is
   `{message: {token: [deviceToken], data: "<json>", notification: {title, body}}}`.
   Huawei answers HTTP 200 with an application-level `code`; anything other than
   `80000000` is treated as a failure so the item is retried next run.

Every failure path returns `false` for that one device (missing secret, bad key,
network error, per-device rejection) — one bad device never aborts the run, and
no token or private key is ever logged (error text passes through a redactor).

## Configuration

```bash
# FCM (existing)
wrangler secret put FIREBASE_SERVICE_ACCOUNT_JSON
wrangler secret put ADMIN_SECRET

# HMS Push Kit
wrangler secret put HMS_SERVICE_ACCOUNT_JSON   # AGC service-account key file (JSON)
# HMS_APP_ID is not secret: set it in wrangler.toml [vars] (or the dashboard)
```

`HMS_APP_ID` is the AppGallery Connect **App ID** (Project settings) and appears
in the REST path. `HMS_SERVICE_ACCOUNT_JSON` is the downloaded AGC service
account key file; it contains a private key and must only ever be a secret.

## Tests

```bash
npm test        # vitest run
```

`test/dedup.test.ts` covers the FCM/dedup behaviour; `test/hms.test.ts` covers
transport routing, the OAuth token cache and the missing-credential path.

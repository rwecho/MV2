import { SignJWT, importPKCS8 } from "jose";

/**
 * HMS Push Kit (HarmonyOS) delivery path.
 *
 * A device that registered with `deviceType: "hms"` is pushed through the
 * Huawei Push REST API instead of FCM. Authentication uses the AppGallery
 * Connect **service account** key file:
 *
 *   1. sign a short-lived RS256 JWT assertion with the account's private key;
 *   2. exchange it for an OAuth2 access token at the account's `token_uri`
 *      (default `https://oauth2.cloud.huawei.com/oauth2/v2/token`);
 *   3. cache that token in KV until shortly before it expires, so the cron
 *      never fetches a token per message.
 *
 * Secrets are only ever read from the `HMS_SERVICE_ACCOUNT_JSON` secret and the
 * `HMS_APP_ID` var; nothing here is hard-coded. No function logs a token or a
 * private key — error text is passed through {@link redact} first.
 */

/** Where an access token comes from when the key file does not say. */
export const HMS_DEFAULT_TOKEN_URI =
  "https://oauth2.cloud.huawei.com/oauth2/v2/token";

/** Base of the Push REST API; the app id is appended per request. */
export const HMS_PUSH_BASE_URL = "https://push-api.cloud.huawei.com/v1";

/** KV key holding the cached access token (its TTL mirrors the token expiry). */
export const HMS_ACCESS_TOKEN_KV_KEY = "hms_access_token";

/** Huawei's success code in the JSON envelope of `messages:send`. */
const HMS_SUCCESS_CODE = "80000000";

/** The subset of the AGC service-account JSON this module uses. */
export interface HmsServiceAccount {
  project_id?: string;
  client_id?: string;
  client_secret?: string;
  private_key?: string;
  private_key_id?: string;
  client_email?: string;
  token_uri?: string;
}

/**
 * True for the device types the HMS sender owns. The untouched
 * `push_service.dart` reports the ohos Flutter fork's
 * `TargetPlatform.ohos` (`"ohos"`), while other clients may register the
 * canonical `"hms"`; both are HMS.
 */
export function isHmsDevice(deviceType: unknown): boolean {
  return deviceType === "hms" || deviceType === "ohos";
}

/** Replaces every occurrence of the given secrets in log-bound text. */
function redact(text: string, ...secrets: (string | undefined)[]): string {
  let result = text;
  for (const secret of secrets) {
    if (secret && secret.length > 0) {
      result = result.split(secret).join("[redacted]");
    }
  }
  return result;
}

/**
 * Returns a cached access token, or mints one from the service-account key.
 * Returns `null` (never throws) on any configuration or network failure so a
 * single bad device cannot abort the whole scheduled run.
 */
export async function getHmsAccessToken(
  serviceAccount: HmsServiceAccount,
  kv: KVNamespace,
): Promise<string | null> {
  const cached = await kv.get(HMS_ACCESS_TOKEN_KV_KEY);
  if (cached) return cached;

  const privateKeyPem = serviceAccount.private_key;
  const issuer = serviceAccount.client_email || serviceAccount.client_id;
  if (!privateKeyPem || !issuer) {
    console.error(
      "HMS service account JSON is missing private_key/client_email (or client_id).",
    );
    return null;
  }

  const tokenUri = serviceAccount.token_uri || HMS_DEFAULT_TOKEN_URI;

  try {
    const privateKey = await importPKCS8(privateKeyPem, "RS256");
    const protectedHeader: { alg: "RS256"; typ: string; kid?: string } = {
      alg: "RS256",
      typ: "JWT",
    };
    if (serviceAccount.private_key_id) {
      protectedHeader.kid = serviceAccount.private_key_id;
    }

    const assertion = await new SignJWT({
      iss: issuer,
      sub: issuer,
      aud: tokenUri,
    })
      .setProtectedHeader(protectedHeader)
      .setIssuedAt()
      .setExpirationTime("1h")
      .sign(privateKey);

    const params = new URLSearchParams();
    params.append("grant_type", "client_credentials");
    params.append(
      "client_assertion_type",
      "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
    );
    params.append("client_assertion", assertion);

    const response = await fetch(tokenUri, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: params,
    });

    if (!response.ok) {
      const text = await response.text();
      console.error(
        `HMS token exchange failed: ${response.status} ${redact(
          text,
          assertion,
          privateKeyPem,
        )}`,
      );
      return null;
    }

    const data = (await response.json()) as {
      access_token?: string;
      expires_in?: number;
    };
    const accessToken = data.access_token;
    if (!accessToken) {
      console.error("HMS token endpoint returned no access_token.");
      return null;
    }

    const expiresIn =
      typeof data.expires_in === "number" && data.expires_in > 0
        ? data.expires_in
        : 3600;
    // Refresh well before expiry; KV refuses TTLs below 60s.
    const ttl = Math.max(60, expiresIn - 300);
    await kv.put(HMS_ACCESS_TOKEN_KV_KEY, accessToken, {
      expirationTtl: ttl,
    });

    return accessToken;
  } catch (e) {
    console.error("Error obtaining the HMS access token", redact(String(e), privateKeyPem));
    return null;
  }
}

/**
 * Sends one notification through HMS Push Kit. Mirrors
 * `sendPushNotification`: resolves `true` only when Huawei acknowledged the
 * message, and `false` for a missing secret/app id, an auth failure or a
 * per-device rejection.
 */
export async function sendHmsPush(
  deviceToken: string,
  title: string,
  body: string,
  data: Record<string, string>,
  serviceAccountJson: string | undefined,
  appId: string | undefined,
  kv: KVNamespace,
): Promise<boolean> {
  if (!serviceAccountJson) {
    console.error("Missing HMS_SERVICE_ACCOUNT_JSON; skipping HMS push.");
    return false;
  }
  if (!appId) {
    console.error("Missing HMS_APP_ID; skipping HMS push.");
    return false;
  }

  let serviceAccount: HmsServiceAccount;
  try {
    serviceAccount = JSON.parse(serviceAccountJson) as HmsServiceAccount;
  } catch {
    console.error("Failed to parse HMS_SERVICE_ACCOUNT_JSON.");
    return false;
  }

  const accessToken = await getHmsAccessToken(serviceAccount, kv);
  if (!accessToken) {
    // getHmsAccessToken already logged the cause (with secrets redacted).
    return false;
  }

  const payload = {
    message: {
      token: [deviceToken],
      // Custom keys (link/topicId/notificationId) travel as a JSON string; the
      // HarmonyOS client parses them in HmsPushBridge.
      data: JSON.stringify(data),
      notification: {
        title,
        body,
      },
    },
  };

  try {
    const response = await fetch(
      `${HMS_PUSH_BASE_URL}/${encodeURIComponent(appId)}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify(payload),
      },
    );

    const text = await response.text();
    if (!response.ok) {
      console.error(
        `HMS Send Failed: ${response.status} ${redact(
          text,
          accessToken,
          deviceToken,
        )}`,
      );
      return false;
    }

    // Huawei answers HTTP 200 even for some application-level errors, so the
    // envelope code decides.
    if (text.length > 0) {
      try {
        const result = JSON.parse(text) as { code?: string; msg?: string };
        if (result.code && result.code !== HMS_SUCCESS_CODE) {
          console.error(
            `HMS Send rejected: code=${result.code} msg=${redact(
              result.msg ?? "",
              accessToken,
              deviceToken,
            )}`,
          );
          return false;
        }
      } catch {
        // A non-JSON body with HTTP 200 is treated as accepted.
      }
    }

    return true;
  } catch (e) {
    console.error(
      "Error sending HMS push",
      redact(String(e), accessToken, deviceToken),
    );
    return false;
  }
}

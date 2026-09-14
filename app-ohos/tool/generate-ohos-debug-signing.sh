#!/usr/bin/env bash
#
# Regenerate the LOCAL DEBUG signing material used by `ohos/build-profile.json5`.
#
# Why this is needed
# ------------------
# `flutter build hap` hard-fails while `app.signingConfigs` is empty
# (`checkOhosSignedInfo` in the ohos fork's flutter_tools). Filling it in
# requires four things that DevEco Studio normally does for you after a Huawei
# developer login:
#
#   1. a keystore,
#   2. an app signing certificate chain,
#   3. a signed provisioning profile,
#   4. DevEco-encrypted `storePassword` / `keyPassword` values plus the
#      `material/` directory hvigor derives the decryption key from.
#
# This script reproduces all four **offline**, from the OpenHarmony *public
# demo* material that ships inside DevEco Studio. The result is a debug-only
# HAP: it is NOT signed by Huawei/AppGallery and will not install on a
# production HarmonyOS device. Replace the whole `signingConfigs` block with the
# AppGallery Connect material before publishing.
#
# Usage:
#   tool/generate-ohos-debug-signing.sh
#
# Overridable environment variables:
#   DEVECO_HOME   default /Applications/DevEco-Studio.app
#   JAVA          default <JAVA_HOME>/bin/java, else a DevEco-bundled JBR
#   KEYTOOL       default <dirname of JAVA>/keytool
#   MV2_OHOS_KEYSTORE_PASS   password for the generated debug keystore
#   MV2_OHOS_BUNDLE_NAME     default com.rwecho.mv2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OHOS_DIR="$PROJECT_DIR/ohos"
SIGN_DIR="$OHOS_DIR/signing"

DEVECO_HOME="${DEVECO_HOME:-/Applications/DevEco-Studio.app}"
OHOS_SDK="${OHOS_SDK:-$DEVECO_HOME/Contents/sdk/default/openharmony}"
TOOLCHAIN_LIB="$OHOS_SDK/toolchains/lib"
BUNDLE_NAME="${MV2_OHOS_BUNDLE_NAME:-com.rwecho.mv2}"
KEYSTORE_PASS="${MV2_OHOS_KEYSTORE_PASS:-mv2ohosdebugmaterialpassword1234567890xy}"
KEYSTORE_NAME="mv2-ohos-debug.p12"

if [[ -z "${JAVA:-}" ]]; then
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
    JAVA="$JAVA_HOME/bin/java"
  elif [[ -x "$DEVECO_HOME/Contents/jbr/Contents/Home/bin/java" ]]; then
    JAVA="$DEVECO_HOME/Contents/jbr/Contents/Home/bin/java"
  else
    JAVA="java"
  fi
fi
KEYTOOL="${KEYTOOL:-$(dirname "$JAVA")/keytool}"

for required in \
  "$TOOLCHAIN_LIB/OpenHarmony.p12" \
  "$TOOLCHAIN_LIB/OpenHarmonyProfileDebug.pem" \
  "$TOOLCHAIN_LIB/UnsgnedDebugProfileTemplate.json" \
  "$TOOLCHAIN_LIB/hap-sign-tool.jar"; do
  if [[ ! -f "$required" ]]; then
    echo "error: missing OpenHarmony signing material: $required" >&2
    echo "       set DEVECO_HOME/OHOS_SDK to your DevEco Studio install." >&2
    exit 1
  fi
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> 1/4 keystore ($KEYSTORE_NAME, password overridden)"
mkdir -p "$SIGN_DIR"
cp "$TOOLCHAIN_LIB/OpenHarmony.p12" "$SIGN_DIR/$KEYSTORE_NAME"
# hvigor rejects passwords shorter than 32 chars before it even tries to decrypt
# them, so the demo keystore's default "123456" is re-keyed to a long value.
"$KEYTOOL" -storepasswd \
  -keystore "$SIGN_DIR/$KEYSTORE_NAME" -storetype PKCS12 \
  -storepass 123456 -new "$KEYSTORE_PASS" >/dev/null

echo "==> 2/4 app certificate chain"
# The keystore entry `openharmony application release` carries a *self-signed*
# certificate, so it cannot be used as a chain leaf. The real CA-signed leaf is
# embedded in the profile template; its public key matches the keystore key.
python3 - "$TOOLCHAIN_LIB/UnsgnedDebugProfileTemplate.json" "$WORK_DIR/leaf.pem" <<'PY'
import json, sys
template = json.load(open(sys.argv[1]))
open(sys.argv[2], 'w').write(template['bundle-info']['development-certificate'])
PY
"$KEYTOOL" -exportcert -alias "openharmony application ca" \
  -keystore "$SIGN_DIR/$KEYSTORE_NAME" -storetype PKCS12 -storepass "$KEYSTORE_PASS" \
  -rfc -file "$WORK_DIR/subca.pem" >/dev/null
"$KEYTOOL" -exportcert -alias "openharmony application root ca" \
  -keystore "$SIGN_DIR/$KEYSTORE_NAME" -storetype PKCS12 -storepass "$KEYSTORE_PASS" \
  -rfc -file "$WORK_DIR/rootca.pem" >/dev/null
# hap-sign-tool wants leaf -> intermediate -> root.
cat "$WORK_DIR/leaf.pem" "$WORK_DIR/subca.pem" "$WORK_DIR/rootca.pem" \
  > "$SIGN_DIR/mv2-ohos-debug.cer"
if command -v openssl >/dev/null; then
  openssl verify -CAfile "$WORK_DIR/rootca.pem" -untrusted "$WORK_DIR/subca.pem" \
    "$WORK_DIR/leaf.pem"
fi

echo "==> 3/4 provisioning profile (bundle $BUNDLE_NAME)"
python3 - \
  "$TOOLCHAIN_LIB/UnsgnedDebugProfileTemplate.json" \
  "$SIGN_DIR/mv2-ohos-debug-profile.json" \
  "$BUNDLE_NAME" <<'PY'
import json, sys, time
template = json.load(open(sys.argv[1]))
# Keep the template's `development-certificate` (it matches our signing key) and
# only retarget the bundle id and widen the validity window.
template['bundle-info']['bundle-name'] = sys.argv[3]
now = int(time.time())
template['validity'] = {'not-before': now - 86400, 'not-after': now + 10 * 365 * 86400}
json.dump(template, open(sys.argv[2], 'w'), indent=2, ensure_ascii=False)
PY
"$JAVA" -jar "$TOOLCHAIN_LIB/hap-sign-tool.jar" sign-profile \
  -mode localSign \
  -keyAlias "openharmony application profile debug" \
  -keyPwd "$KEYSTORE_PASS" \
  -profileCertFile "$TOOLCHAIN_LIB/OpenHarmonyProfileDebug.pem" \
  -inFile "$SIGN_DIR/mv2-ohos-debug-profile.json" \
  -keystoreFile "$SIGN_DIR/$KEYSTORE_NAME" \
  -keystorePwd "$KEYSTORE_PASS" \
  -outFile "$SIGN_DIR/mv2-ohos-debug.p7b" \
  -signAlg SHA256withECDSA

echo "==> 4/4 hvigor-encrypted passwords + material/"
PASSWORDS_JSON="$(node "$SCRIPT_DIR/generate-ohos-signing-material.js" \
  "$SIGN_DIR/material" "$KEYSTORE_PASS")"
echo "$PASSWORDS_JSON"
PASSWORD_HEX="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["storePassword"])' \
  <<<"$PASSWORDS_JSON")"
python3 - "$OHOS_DIR/build-profile.json5" "$PASSWORD_HEX" <<'PY'
import re, sys
path, password = sys.argv[1], sys.argv[2]
source = open(path).read()
source = re.sub(r'"storePassword": "[0-9a-fA-F]+"', f'"storePassword": "{password}"', source)
source = re.sub(r'"keyPassword": "[0-9a-fA-F]+"', f'"keyPassword": "{password}"', source)
open(path, 'w').write(source)
PY

echo
echo "Done. Now run:"
echo "  PUB_HOSTED_URL=https://pub.dev <ohos-flutter>/bin/flutter build hap --debug"
echo
echo "NOTE: debug signing only. The generated HAP is signed with the public"
echo "      OpenHarmony demo certificate and is not publishable."

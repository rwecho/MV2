#!/usr/bin/env node
/*
 * Generate DevEco/hvigor-compatible signing material for the ohos debug build.
 *
 * Why this exists
 * ---------------
 * `flutter build hap` refuses to succeed unless `ohos/build-profile.json5`
 * contains a non-empty `app.signingConfigs` (see `checkOhosSignedInfo` in the
 * ohos fork's flutter_tools). hvigor then does NOT accept plaintext passwords:
 * `CommonSignCommandBuilder.getKeyStorePwd()` calls
 * `DecipherUtil.decryptPwd(<dir of storeFile>, storePassword, ...)`, which
 *
 *   1. requires the hex password blob to be >= 32 chars and even-length,
 *   2. reads a `material/` directory next to the keystore containing
 *      `fd/<3 subdirs>/<file>`, `ac/<file>` and `ce/<file>`,
 *   3. derives an AES-128-GCM key from those bytes and decrypts the password.
 *
 * This script is the inverse of that routine: it builds a fresh `material/`
 * directory and produces the matching encrypted hex passwords. It verifies the
 * result by calling hvigor's own `DecipherUtil.decryptPwd`, so the encoding is
 * guaranteed to match this DevEco/hvigor installation.
 *
 * Usage:
 *   node tool/generate-ohos-signing-material.js <materialDir> <plaintextPassword>
 * Prints a JSON object: {"storePassword": "<hex>", "keyPassword": "<hex>"}
 */
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// Byte-for-byte copy of DecipherUtil.component from hvigor-ohos-plugin.
const COMPONENT = Buffer.from([
  49, 243, 9, 115, 214, 175, 91, 184, 211, 190, 177, 88, 101, 131, 192, 119,
]);

/**
 * Mirrors DecipherUtil.decrypt's blob layout.
 *
 * hvigor decodes it as:
 *   e = u32be(r[0..4]); i = r.length - 4 - e;
 *   iv = r[4 .. 4+i]; ct = r[4+i .. len-16]; tag = r[len-16 .. len]
 * so the 4-byte header is `ciphertextLength + 16` (the GCM tag length, which
 * the IV length is then derived from) -- NOT the IV length.
 */
function gcmEncrypt(key, plaintext) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-128-gcm', key, iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const tag = cipher.getAuthTag();
  const header = Buffer.alloc(4);
  header.writeUInt32BE(ciphertext.length + tag.length, 0);
  return Buffer.concat([header, iv, ciphertext, tag]);
}

function xorAll(parts) {
  const out = Buffer.alloc(16);
  for (const part of parts) {
    for (let i = 0; i < 16; i++) out[i] ^= part[i];
  }
  return out;
}

function writeMaterial(materialDir) {
  fs.rmSync(materialDir, { recursive: true, force: true });
  const fd = [crypto.randomBytes(16), crypto.randomBytes(16), crypto.randomBytes(16)];
  // hvigor hands the salt to crypto.pbkdf2Sync as an Int8Array, which Node
  // reads as raw binary -- not as a stringified number list.
  const saltBytes = crypto.randomBytes(16);

  const xor = xorAll([...fd, COMPONENT]);
  // xorComponents() wraps the XOR result in a Buffer, so its toString() is utf8.
  const pbkdf2Key = crypto.pbkdf2Sync(xor.toString(), saltBytes, 10000, 16, 'sha256');

  const finalKey = crypto.randomBytes(16);
  const ceBlob = gcmEncrypt(pbkdf2Key, finalKey);

  fs.mkdirSync(materialDir, { recursive: true });
  const fdNames = ['fd-a', 'fd-b', 'fd-c'];
  fd.forEach((bytes, index) => {
    const dir = path.join(materialDir, 'fd', fdNames[index]);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'key.bin'), bytes);
  });
  const acDir = path.join(materialDir, 'ac');
  fs.mkdirSync(acDir, { recursive: true });
  fs.writeFileSync(path.join(acDir, 'salt.bin'), saltBytes);
  const ceDir = path.join(materialDir, 'ce');
  fs.mkdirSync(ceDir, { recursive: true });
  fs.writeFileSync(path.join(ceDir, 'work.bin'), ceBlob);

  return finalKey;
}

function readDirBytes(dir) {
  const entries = fs.readdirSync(dir).filter((name) => name !== '.DS_Store');
  if (entries.length !== 1) {
    throw new Error(`expected exactly 1 entry in ${dir}, found ${entries.length}`);
  }
  return fs.readFileSync(path.join(dir, entries[0]));
}

/** Mirrors DecipherUtil.decrypt. */
function hvigorDecrypt(blob, key) {
  const ivLength = blob.length - 4 - blob.readUInt32BE(0);
  const iv = blob.subarray(4, 4 + ivLength);
  const ciphertext = blob.subarray(4 + ivLength, blob.length - 16);
  const tag = blob.subarray(blob.length - 16);
  const decipher = crypto.createDecipheriv('aes-128-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
}

/** Re-runs hvigor's whole derivation against the freshly written material. */
function selfCheck(materialDir, password, passwordHex) {
  const fdRoot = path.join(materialDir, 'fd');
  const fd = fs
    .readdirSync(fdRoot)
    .filter((name) => name !== '.DS_Store')
    .map((name) => readDirBytes(path.join(fdRoot, name)));
  const salt = readDirBytes(path.join(materialDir, 'ac'));
  const work = readDirBytes(path.join(materialDir, 'ce'));
  const xor = xorAll([...fd, COMPONENT]);
  const pbkdf2Key = crypto.pbkdf2Sync(xor.toString(), salt, 10000, 16, 'sha256');
  const finalKey = hvigorDecrypt(work, pbkdf2Key);
  const decoded = hvigorDecrypt(Buffer.from(passwordHex, 'hex'), finalKey).toString('utf-8');
  if (decoded !== password) {
    throw new Error(`self-check mismatch: decoded ${JSON.stringify(decoded)}`);
  }
  return true;
}

/** Loads hvigor's own DecipherUtil, stubbing the module layout DevEco uses. */
function loadHvigorDecipherUtil() {
  const deveco = process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app';
  const hvigor = path.join(deveco, 'Contents/tools/hvigor/hvigor/index.js');
  const hvigorLogger = path.join(
    deveco,
    'Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/@ohos/hvigor-logger/index.js',
  );
  const decipherUtil = path.join(
    deveco,
    'Contents/tools/hvigor/hvigor-ohos-plugin/src/utils/decipher-util.js',
  );
  for (const file of [hvigor, hvigorLogger, decipherUtil]) {
    if (!fs.existsSync(file)) return null;
  }
  const Module = require('module');
  const load = Module._load;
  Module._load = function patched(request, parent, isMain) {
    if (request === '@ohos/hvigor') return load.call(this, hvigor, parent, isMain);
    if (request === '@ohos/hvigor-logger') {
      return load.call(this, hvigorLogger, parent, isMain);
    }
    return load.apply(this, arguments);
  };
  try {
    return require(decipherUtil).DecipherUtil;
  } finally {
    Module._load = load;
  }
}

function main() {
  const [materialDir, password] = process.argv.slice(2);
  if (!materialDir || !password) {
    console.error('usage: generate-ohos-signing-material.js <materialDir> <password>');
    process.exit(2);
  }
  const finalKey = writeMaterial(materialDir);
  const passwordHex = gcmEncrypt(finalKey, Buffer.from(password, 'utf8')).toString('hex');

  // Always run the local round-trip; additionally verify with hvigor's own
  // decoder, which is the authoritative implementation.
  selfCheck(materialDir, password, passwordHex);

  let verified = null;
  try {
    const DecipherUtil = loadHvigorDecipherUtil();
    if (DecipherUtil) {
      verified = DecipherUtil.decryptPwd(path.resolve(materialDir, '..'), passwordHex, 'self-check');
    }
  } catch (error) {
    verified = null;
  }
  if (verified !== null && verified !== password) {
    console.error('FATAL: hvigor DecipherUtil round-trip mismatch');
    process.exit(1);
  }
  console.log(JSON.stringify({
    storePassword: passwordHex,
    keyPassword: passwordHex,
    verified_locally: true,
    verified_by_hvigor: verified !== null,
  }, null, 2));
}

main();

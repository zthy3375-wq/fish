import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { accessSync, constants, readFileSync, writeFileSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const variants = new Set(['regular-debug', 'parallel-preview-debug']);
const applicationIdPattern = /^[a-zA-Z][\w]*(?:\.[a-zA-Z][\w]*)+$/;

function run(executable, args) {
  try {
    return execFileSync(executable, args, { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
  } catch (error) {
    throw new Error(`${basename(executable)} ${args.slice(0, 2).join(' ')} failed: ${error.message}`);
  }
}

function singleMatch(text, pattern, field) {
  const matches = [...text.matchAll(pattern)];
  if (matches.length !== 1) throw new Error(`Expected exactly one ${field} in Android tool output.`);
  return matches[0][1];
}

function positiveInteger(value, field) {
  if (!Number.isSafeInteger(value) || value < 1) throw new Error(`Invalid ${field}: ${value}`);
  return value;
}

export function parseBadging(text) {
  const packageLine = singleMatch(text, /^(package: .+)$/gm, 'package line');
  return {
    application_id: singleMatch(packageLine, /\bname='([^']+)'/g, 'application ID'),
    version_name: singleMatch(packageLine, /\bversionName='([^']+)'/g, 'version name'),
    version_code: positiveInteger(Number(singleMatch(packageLine, /\bversionCode='(\d+)'/g, 'version code')), 'version code'),
    min_sdk: positiveInteger(Number(singleMatch(text, /^sdkVersion:'(\d+)'\s*$/gm, 'minimum SDK')), 'minimum SDK'),
    debuggable: /^application-debuggable\s*$/m.test(text),
  };
}

export function parseCertificates(text) {
  const count = positiveInteger(Number(singleMatch(text, /^Number of signers: (\d+)\s*$/gm, 'signer count')), 'signer count');
  const matches = [...text.matchAll(/^Signer #(\d+) certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$/gm)];
  if (matches.length !== count) throw new Error('apksigner did not report all signer certificate SHA-256 fingerprints.');
  const signers = matches.map((match) => ({ signer: Number(match[1]), sha256: match[2].toLowerCase() }));
  signers.sort((a, b) => a.signer - b.signer);
  if (signers.some((signer, index) => signer.signer !== index + 1)) {
    throw new Error('apksigner reported duplicate or nonsequential signer numbers.');
  }
  return signers;
}

function verifyPreviewIsolation(regular, actual, sourceCommit) {
  if (!regular) throw new Error('Parallel preview requires --regular-evidence from the verified regular build.');
  if (regular.schema_version !== 1 || regular.build_variant !== 'regular-debug' ||
      regular.signing?.verified !== true || regular.apk?.debuggable !== true ||
      !applicationIdPattern.test(regular.apk?.application_id ?? '') ||
      !/^[0-9a-f]{64}$/.test(regular.apk?.sha256 ?? '') ||
      !Number.isSafeInteger(regular.apk?.bytes) || regular.apk.bytes < 1) {
    throw new Error('Invalid verified regular-debug evidence for parallel preview comparison.');
  }
  if (regular.source_commit !== sourceCommit) throw new Error('Regular/preview source_commit mismatch.');
  if (regular.apk.application_id === actual.application_id) {
    throw new Error('Parallel preview must use a different application_id from the regular APK.');
  }
  for (const field of ['version_name', 'version_code', 'min_sdk']) {
    if (regular.apk[field] !== actual[field]) throw new Error(`Regular/preview ${field} mismatch.`);
  }
  return {
    regular_application_id: regular.apk.application_id,
    regular_apk_sha256: regular.apk.sha256,
  };
}

export function createEvidence({ apk, expected, variant, sourceCommit, buildToolsDir, regularEvidence }, execute = run) {
  if (!variants.has(variant) || expected.build_variant !== variant) {
    throw new Error(`Build variant mismatch: requested ${variant}, expected ${expected.build_variant}.`);
  }
  if (!applicationIdPattern.test(expected.application_id ?? '')) {
    throw new Error('Expected application ID is missing or invalid.');
  }
  if (typeof expected.version_name !== 'string' || !expected.version_name.trim()) {
    throw new Error('Expected version name is missing.');
  }
  positiveInteger(expected.version_code, 'expected version code');
  positiveInteger(expected.min_sdk, 'expected minimum SDK');
  if (!/^[0-9a-f]{40}$/.test(sourceCommit ?? '')) throw new Error('Source commit must be a full Git SHA-1.');
  const actualCommit = execute('git', ['rev-parse', 'HEAD']).trim();
  if (actualCommit !== sourceCommit) throw new Error(`Source commit mismatch: HEAD is ${actualCommit}.`);

  if (!buildToolsDir) throw new Error('Provide --build-tools-dir with the installed Android SDK build-tools directory.');
  const toolPaths = Object.fromEntries(['aapt', 'apksigner'].map((name) => {
    const path = resolve(buildToolsDir, name);
    try { accessSync(path, constants.X_OK); } catch {
      throw new Error(`Required Android SDK tool is unavailable or not executable: ${path}`);
    }
    return [name, path];
  }));
  const apkPath = resolve(apk);
  const bytes = readFileSync(apkPath);
  if (bytes.length === 0) throw new Error('APK is empty.');
  const actual = parseBadging(execute(toolPaths.aapt, ['dump', 'badging', apkPath]));
  for (const field of ['application_id', 'version_name', 'version_code', 'min_sdk']) {
    if (actual[field] !== expected[field]) {
      throw new Error(`APK ${field} mismatch: expected ${expected[field]}, received ${actual[field]}.`);
    }
  }
  if (!actual.debuggable) throw new Error('Expected an installable debug test APK, but it is not debuggable.');
  const parallelInstallation = variant === 'parallel-preview-debug'
    ? verifyPreviewIsolation(regularEvidence, actual, sourceCommit) : undefined;
  // A nonzero exit status aborts. Never infer a valid signature from printed certificate text alone.
  const certificates = parseCertificates(execute(toolPaths.apksigner, ['verify', '--verbose', '--print-certs', apkPath]));
  if (!bytes.equals(readFileSync(apkPath))) throw new Error('APK changed during verification.');
  return {
    schema_version: 1,
    source_commit: sourceCommit,
    build_variant: variant,
    apk: {
      file_name: basename(apkPath),
      ...actual,
      sha256: createHash('sha256').update(bytes).digest('hex'),
      bytes: bytes.length,
    },
    signing: {
      verified: true,
      certificate_sha256: certificates,
      kind: 'ci-debug-test',
      stable_upgrade_identity: false,
    },
    ...(parallelInstallation ? { parallel_installation: parallelInstallation } : {}),
  };
}

function main() {
  const { values } = parseArgs({ options: Object.fromEntries(
    ['apk', 'expected', 'variant', 'source-commit', 'build-tools-dir', 'output', 'regular-evidence'].map((name) => [name, { type: 'string' }]),
  ) });
  for (const option of ['apk', 'expected', 'variant', 'source-commit', 'build-tools-dir', 'output']) {
    if (!values[option]) throw new Error(`Missing --${option}. See docs/APK-EVIDENCE.md.`);
  }
  const expected = JSON.parse(readFileSync(values.expected, 'utf8'));
  const evidence = createEvidence({
    apk: values.apk, expected, variant: values.variant,
    sourceCommit: values['source-commit'], buildToolsDir: values['build-tools-dir'],
    regularEvidence: values['regular-evidence'] ? JSON.parse(readFileSync(values['regular-evidence'], 'utf8')) : undefined,
  });
  // Refuse accidental overwrite of an APK, expectations, or evidence from an earlier run.
  writeFileSync(values.output, `${JSON.stringify(evidence, null, 2)}\n`, { flag: 'wx' });
  console.log(`Verified ${evidence.build_variant}: ${evidence.apk.application_id} ${evidence.apk.version_name}`);
  console.log(`APK SHA-256 (not artifact ZIP): ${evidence.apk.sha256}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(); } catch (error) {
    console.error(`APK evidence failed: ${error.message}`);
    process.exitCode = 1;
  }
}

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { createEvidence, parseBadging, parseCertificates } from './apk-evidence.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const fixtures = new URL('../tests/fixtures/apk-evidence/', import.meta.url);
const fixture = (name) => readFileSync(new URL(name, fixtures), 'utf8');
const sourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();

function setup(t) {
  const directory = mkdtempSync(join(tmpdir(), 'campus-apk-evidence-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const buildToolsDir = join(directory, 'build-tools');
  mkdirSync(buildToolsDir);
  const apk = join(directory, 'fixture.apk');
  writeFileSync(apk, fixture('apk-payload.txt'));
  const expected = JSON.parse(fixture('expected-regular.json'));
  const options = { apk, expected, variant: expected.build_variant, sourceCommit, buildToolsDir };
  function mockTool(name, output, exitCode = 0) {
    const args = name === 'aapt' ? ['dump', 'badging'] : ['verify', '--verbose', '--print-certs'];
    writeFileSync(join(buildToolsDir, name), `#!/usr/bin/env node\n
if (JSON.stringify(process.argv.slice(2, -1)) !== ${JSON.stringify(JSON.stringify(args))}) process.exit(99);
process.stdout.write(${JSON.stringify(output)});
process.exitCode = ${exitCode};\n`, { mode: 0o755 });
  }
  mockTool('aapt', fixture('aapt-regular.txt'));
  mockTool('apksigner', fixture('apksigner-valid.txt'));
  function cli({ regularEvidencePath } = {}) {
    const expectedPath = join(directory, 'expected.json');
    const output = join(directory, 'build-evidence.json');
    writeFileSync(expectedPath, JSON.stringify(options.expected));
    if (regularEvidencePath === undefined && options.regularEvidence !== undefined) {
      regularEvidencePath = join(directory, 'regular-build-evidence.json');
      writeFileSync(regularEvidencePath, JSON.stringify(options.regularEvidence));
    }
    const result = spawnSync(process.execPath, [join(root, 'scripts/apk-evidence.mjs'),
      '--apk', options.apk, '--expected', expectedPath, '--variant', options.variant,
      '--source-commit', options.sourceCommit, '--build-tools-dir', options.buildToolsDir,
      '--output', output,
      ...(regularEvidencePath ? ['--regular-evidence', regularEvidencePath] : []),
    ], { cwd: root, encoding: 'utf8' });
    return { ...result, output };
  }
  return { options, directory, mockTool, cli };
}

function setupPreview(t) {
  const harness = setup(t);
  const { options, mockTool } = harness;
  options.regularEvidence = createEvidence(options);
  options.variant = options.expected.build_variant = 'parallel-preview-debug';
  options.expected.application_id += '.preview';
  mockTool('aapt', fixture('aapt-regular.txt').replace("org.example.campus'", "org.example.campus.preview'"));
  return harness;
}

test('regular APK evidence records actual fields, APK bytes/hash, certificate and commit', (t) => {
  const { options } = setup(t);
  const evidence = createEvidence(options);
  assert.equal(evidence.schema_version, 1);
  assert.equal(evidence.source_commit, sourceCommit);
  assert.equal(evidence.build_variant, 'regular-debug');
  for (const field of ['application_id', 'version_name', 'version_code', 'min_sdk']) {
    assert.equal(evidence.apk[field], options.expected[field]);
  }
  assert.equal(evidence.apk.file_name, basename(options.apk));
  assert.equal(evidence.apk.debuggable, true);
  const bytes = readFileSync(options.apk);
  assert.equal(evidence.apk.sha256, createHash('sha256').update(bytes).digest('hex'));
  assert.equal(evidence.apk.bytes, bytes.length);
  assert.deepEqual(evidence.signing.certificate_sha256, parseCertificates(fixture('apksigner-valid.txt')));
  assert.equal(evidence.signing.verified, true);
  assert.equal(evidence.signing.stable_upgrade_identity, false);
});

test('parallel preview uses its independently evaluated package and version', (t) => {
  const { options, cli } = setupPreview(t);
  const evidence = createEvidence(options);
  assert.equal(evidence.apk.application_id, options.expected.application_id);
  assert.deepEqual(evidence.parallel_installation, {
    regular_application_id: options.regularEvidence.apk.application_id,
    regular_apk_sha256: options.regularEvidence.apk.sha256,
  });
  const result = cli();
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(readFileSync(result.output, 'utf8')), evidence);
});

test('preview fails even if Gradle and APK agree on an accidentally shared application ID', (t) => {
  const { options, mockTool, cli } = setupPreview(t);
  options.expected.application_id = options.regularEvidence.apk.application_id;
  mockTool('aapt', fixture('aapt-regular.txt'));
  assert.throws(() => createEvidence(options), /must use a different application_id/);
  const result = cli();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /must use a different application_id/);
  assert.equal(existsSync(result.output), false);
});

for (const [field, wrong] of [['version_name', 'another-build'], ['version_code', 8], ['min_sdk', 24]]) {
  test(`preview requires the same ${field} as the verified regular APK`, (t) => {
    const { options } = setupPreview(t);
    options.regularEvidence.apk[field] = wrong;
    assert.throws(() => createEvidence(options), new RegExp(`Regular/preview ${field} mismatch`));
  });
}

test('preview rejects regular evidence from another source commit', (t) => {
  const { options } = setupPreview(t);
  options.regularEvidence.source_commit = '0'.repeat(40);
  assert.throws(() => createEvidence(options), /Regular\/preview source_commit mismatch/);
});

test('preview requires regular evidence and never writes output if it is absent', (t) => {
  const { options, cli } = setupPreview(t);
  delete options.regularEvidence;
  assert.throws(() => createEvidence(options), /requires --regular-evidence/);
  const result = cli();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /requires --regular-evidence/);
  assert.equal(existsSync(result.output), false);
});

test('preview rejects malformed, unverified, or non-regular baseline evidence', (t) => {
  const { options } = setupPreview(t);
  const regular = options.regularEvidence;
  for (const bad of [
    {}, { ...regular, schema_version: 2 }, { ...regular, build_variant: 'parallel-preview-debug' },
    { ...regular, signing: { verified: false } }, { ...regular, apk: {} },
    { ...regular, apk: { ...regular.apk, application_id: '' } },
    { ...regular, apk: { ...regular.apk, sha256: 'not-an-apk-hash' } },
    { ...regular, apk: { ...regular.apk, bytes: 0 } },
  ]) {
    assert.throws(() => createEvidence({ ...options, regularEvidence: bad }), /Invalid verified regular-debug evidence/);
  }
});

test('preview CLI rejects missing or invalid regular evidence files without producing output', (t) => {
  const { directory, cli } = setupPreview(t);
  const regularEvidencePath = join(directory, 'absent.json');
  let result = cli({ regularEvidencePath });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /ENOENT/);
  assert.equal(existsSync(result.output), false);
  writeFileSync(regularEvidencePath, '{invalid JSON');
  result = cli({ regularEvidencePath });
  assert.equal(result.status, 1);
  assert.equal(existsSync(result.output), false);
});

test('evidence JSON is deterministic across runs and different temporary directories', (t) => {
  const a = setup(t);
  const b = setup(t);
  assert.equal(JSON.stringify(createEvidence(a.options)), JSON.stringify(createEvidence(b.options)));
});

for (const [field, wrong] of [
  ['application_id', 'org.example.other'], ['version_name', 'wrong-version'], ['version_code', 8], ['min_sdk', 24],
]) {
  test(`rejects an APK with an unexpected ${field}`, (t) => {
    const { options } = setup(t);
    options.expected[field] = wrong;
    assert.throws(() => createEvidence(options), new RegExp(`APK ${field} mismatch`));
  });
}

test('does not label regular expectations as a parallel preview', (t) => {
  const { options } = setup(t);
  options.variant = 'parallel-preview-debug';
  assert.throws(() => createEvidence(options), /Build variant mismatch/);
});

test('rejects unknown variants and malformed expectations', (t) => {
  const { options } = setup(t);
  assert.throws(() => createEvidence({ ...options, variant: 'release' }), /Build variant mismatch/);
  for (const [field, value] of [['application_id', ''], ['version_name', ''], ['version_code', '7'], ['min_sdk', 0]]) {
    assert.throws(() => createEvidence({ ...options, expected: { ...options.expected, [field]: value } }), /missing|[Ii]nvalid/);
  }
});

test('rejects source commit mismatches and abbreviated commits', (t) => {
  const { options } = setup(t);
  assert.throws(() => createEvidence({ ...options, sourceCommit: '0'.repeat(40) }), /Source commit mismatch/);
  assert.throws(() => createEvidence({ ...options, sourceCommit: sourceCommit.slice(0, 7) }), /full Git SHA-1/);
});

test('fails clearly when a required Android SDK tool is missing or not executable', (t) => {
  const { options } = setup(t);
  const signer = join(options.buildToolsDir, 'apksigner');
  chmodSync(signer, 0o644);
  assert.throws(() => createEvidence(options), /Required Android SDK tool is unavailable or not executable.*apksigner/);
  rmSync(signer);
  assert.throws(() => createEvidence(options), /Required Android SDK tool is unavailable or not executable.*apksigner/);
  assert.throws(() => createEvidence({ ...options, buildToolsDir: undefined }), /Provide --build-tools-dir/);
});

test('rejects missing or empty APKs', (t) => {
  const { options } = setup(t);
  writeFileSync(options.apk, '');
  assert.throws(() => createEvidence(options), /APK is empty/);
  rmSync(options.apk);
  assert.throws(() => createEvidence(options), /ENOENT/);
});

test('rejects failed aapt parsing and non-debug APKs', (t) => {
  const { options, mockTool } = setup(t);
  mockTool('aapt', fixture('aapt-regular.txt'), 1);
  assert.throws(() => createEvidence(options), /aapt dump badging failed/);
  mockTool('aapt', fixture('aapt-regular.txt').replace('application-debuggable', ''));
  assert.throws(() => createEvidence(options), /not debuggable/);
});

test('never treats printed certificates as success after failed signature verification', (t) => {
  const { options, mockTool, cli } = setup(t);
  mockTool('apksigner', fixture('apksigner-valid.txt'), 1);
  assert.throws(() => createEvidence(options), /apksigner verify --verbose failed/);
  const result = cli();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /APK evidence failed/);
  assert.equal(existsSync(result.output), false);
});

test('requires one unambiguous manifest package/version/minSdk result', () => {
  const badging = fixture('aapt-regular.txt');
  assert.throws(() => parseBadging(badging.replace("sdkVersion:'23'", '')), /minimum SDK/);
  assert.throws(() => parseBadging(`${badging}\n${badging}`), /package line/);
  assert.throws(() => parseBadging(badging.replace("versionCode='7'", "versionCode='bad'")), /version code/);
});

test('requires all signer fingerprints and rejects duplicate/invalid certificates', () => {
  const signing = fixture('apksigner-valid.txt');
  assert.throws(() => parseCertificates(signing.replace('certificate SHA-256', 'certificate SHA-1')), /all signer/);
  assert.throws(() => parseCertificates(signing.replace('Number of signers: 1', 'Number of signers: 2')), /all signer/);
  assert.throws(() => parseCertificates(signing.replace('Signer #1 certificate SHA-256', 'Signer #2 certificate SHA-256')), /nonsequential/);
  const certLine = signing.split('\n').find((line) => line.includes('certificate SHA-256'));
  const two = signing.replace('Number of signers: 1', 'Number of signers: 2');
  assert.throws(() => parseCertificates(`${two}\n${certLine}`), /duplicate/);
  assert.equal(parseCertificates(`${two}\n${certLine.replace('#1', '#2')}`).length, 2);
});

test('rejects APK mutation while tools are inspecting it', (t) => {
  const { options } = setup(t);
  assert.throws(() => createEvidence(options, (tool) => {
    if (tool === 'git') return sourceCommit;
    if (basename(tool) === 'aapt') return fixture('aapt-regular.txt');
    writeFileSync(options.apk, 'changed');
    return fixture('apksigner-valid.txt');
  }), /APK changed during verification/);
});

test('CLI writes only verified evidence, labels the APK hash, and refuses overwrite', (t) => {
  const { cli } = setup(t);
  const result = cli();
  assert.equal(result.status, 0, result.stderr);
  const evidence = JSON.parse(readFileSync(result.output, 'utf8'));
  assert.equal(evidence.source_commit, sourceCommit);
  assert.match(result.stdout, /APK SHA-256 \(not artifact ZIP\)/);
  assert.equal(cli().status, 1);
  assert.deepEqual(JSON.parse(readFileSync(result.output, 'utf8')), evidence);
});

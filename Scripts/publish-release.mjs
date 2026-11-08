import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { copyFile, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Only the explicitly requested, successful main-branch release job runs this.
// Reuse the exact artifacts already validated by this workflow, not a rebuild.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const version = process.env.RELEASE_VERSION;
const sha = process.env.GITHUB_SHA;
const repository = process.env.GITHUB_REPOSITORY;
const runID = process.env.GITHUB_RUN_ID;
if (process.env.GITHUB_ACTIONS !== 'true' || process.env.GITHUB_EVENT_NAME !== 'push' ||
    process.env.GITHUB_REF !== 'refs/heads/main' ||
    !/^\d+\.\d+\.\d+$/.test(version ?? '') || !/^[a-f0-9]{40}$/.test(sha ?? '') ||
    !/^[\w.-]+\/[\w.-]+$/.test(repository ?? '') || !/^\d+$/.test(runID ?? '')) {
  throw new Error('Release publication requires an explicit main-branch CI context.');
}

const app = resolve(root, '.build/release-inputs/app/AoE2MacTrainer-macos.zip');
const xs = resolve(root, '.build/release-inputs/xs/trainer_catalog.xs');
const catalog = resolve(root, 'Sources/AoE2MacTrainer/Resources/builds.json');
const notes = resolve(root, `docs/releases/v${version}.md`);
const output = resolve(root, `.build/release-v${version}`);
const tag = `v${version}`;
const title = `AoE2 Mac Trainer ${version} — предварительная версия для macOS`;

const info = execFileSync('unzip', ['-p', app, 'AoE2MacTrainer.app/Contents/Info.plist'], { encoding: 'utf8' });
const packagedVersion = info.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)?.[1];
if (packagedVersion !== version) throw new Error('Application version does not match the requested release.');
const binary = execFileSync('unzip', ['-p', app, 'AoE2MacTrainer.app/Contents/MacOS/AoE2MacTrainer'],
                            { maxBuffer: 64 * 1024 * 1024 });
if (binary.length < 8 || binary.readUInt32LE(0) !== 0xfeedfacf || binary.readUInt32LE(4) !== 0x0100000c) {
  throw new Error('The macos-arm64 release asset must contain an ARM64 Mach-O executable.');
}
const json = JSON.parse(await readFile(catalog, 'utf8'));
if (json.schemaVersion !== 2 || !Array.isArray(json.builds) || !json.builds.length) {
  throw new Error('The release catalog is not a nonempty JSON v2 catalog.');
}
const script = await readFile(xs, 'utf8');
if (!script.includes('void main()') || script.includes('// @CATALOG_SETUP@') || script.includes('// @FOOD_OBSERVER@')) {
  throw new Error('The release XS must be the generated full catalog, not a template.');
}
const notesBody = await readFile(notes, 'utf8');
await mkdir(output, { recursive: true });
const preparedNotes = resolve(output, 'release-notes.md');
await writeFile(preparedNotes, notesBody.trim() +
  `\n\nИсходники выпуска: [${sha.slice(0, 7)}](https://github.com/${repository}/commit/${sha}). ` +
  `[Сборка и проверки этого выпуска](https://github.com/${repository}/actions/runs/${runID}).\n`, 'utf8');
const inputs = [
  [app, `AoE2MacTrainer-${version}-macos-arm64.zip`],
  [xs, `aoe2trainer_catalog-${version}.xs`],
  [catalog, `builds-${version}.json`]
];
const expected = new Map();
for (const [source, name] of inputs) {
  const destination = resolve(output, name);
  await copyFile(source, destination);
  const bytes = await readFile(destination);
  expected.set(name, { size: bytes.length, digest: `sha256:${createHash('sha256').update(bytes).digest('hex')}` });
}
const sums = [...expected].map(([name, value]) => `${value.digest.slice(7)}  ${name}`).join('\n') + '\n';
const sumsPath = resolve(output, 'SHA256SUMS.txt');
await writeFile(sumsPath, sums, 'utf8');
expected.set('SHA256SUMS.txt', {
  size: (await stat(sumsPath)).size,
  digest: `sha256:${createHash('sha256').update(sums).digest('hex')}`
});

function gh(args) {
  // The standard workflow GH_TOKEN stays in the environment, never in logs or arguments.
  return execFileSync('gh', args, { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
}
function release() {
  const result = gh(['api', `repos/${repository}/releases?per_page=100`, '--paginate', '--jq',
                     `.[] | select(.tag_name == "${tag}")`]).trim();
  return result ? JSON.parse(result) : null;
}
function verifyTag(allowMissing = false) {
  const refs = JSON.parse(gh(['api', `repos/${repository}/git/matching-refs/tags/${tag}`]));
  let object = refs.find(ref => ref.ref === `refs/tags/${tag}`)?.object;
  if (!object && allowMissing) return;
  for (let depth = 0; depth < 16 && object; depth++) {
    if (object.type === 'commit') {
      if (object.sha !== sha) throw new Error(`${tag} points to another source commit.`);
      return;
    }
    if (object.type !== 'tag' || !/^[a-f0-9]{40}$/.test(object.sha)) break;
    object = JSON.parse(gh(['api', `repos/${repository}/git/tags/${object.sha}`])).object;
  }
  throw new Error(`Cannot verify the exact commit behind ${tag}.`);
}
function validateAsset(asset, name, expectedAsset) {
  if (!asset || asset.state !== 'uploaded' || asset.size !== expectedAsset.size) {
    throw new Error(`Missing or incomplete release asset: ${name}`);
  }
  let digest = asset.digest;
  if (!digest) {
    // Older API responses may omit a digest. Verify bytes before accepting an
    // existing asset; same file size alone is not sufficient for a safe retry.
    const bytes = execFileSync('gh', ['api', `repos/${repository}/releases/assets/${asset.id}`,
                                    '-H', 'Accept: application/octet-stream'],
                               { maxBuffer: 64 * 1024 * 1024 });
    digest = `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
  }
  if (digest !== expectedAsset.digest) throw new Error(`Mismatched release asset: ${name}`);
}
function validateAssets(data) {
  for (const [name, expectedAsset] of expected) {
    const asset = data.assets.find(item => item.name === name);
    validateAsset(asset, name, expectedAsset);
  }
}

verifyTag(true);
let current = release();
if (current && current.target_commitish !== sha) {
  throw new Error(`Refusing to overwrite ${tag}: it belongs to another source commit.`);
}
if (current && !current.draft) {
  // A retry after successful publication must not modify an existing release.
  verifyTag();
  validateAssets(current);
  console.log(`Release already published with matching assets: ${current.html_url}`);
} else {
  if (!current) {
    gh(['release', 'create', tag, '--repo', repository, '--target', sha, '--draft', '--prerelease',
        '--title', title, '--notes-file', preparedNotes]);
  }
  // Resume a same-commit draft by uploading missing names only. Never clobber
  // any asset, even if somebody publishes the draft concurrently.
  for (const [name, expectedAsset] of expected) {
    current = release();
    if (!current || current.target_commitish !== sha) {
      throw new Error('Release source changed during upload; refusing to continue.');
    }
    const existing = current.assets.find(item => item.name === name);
    if (existing) {
      validateAsset(existing, name, expectedAsset);
    } else {
      if (!current.draft) throw new Error('Refusing to add missing assets to an already published release.');
      gh(['release', 'upload', tag, '--repo', repository, resolve(output, name)]);
    }
  }
  current = release();
  if (!current || current.target_commitish !== sha) {
    throw new Error('Release source changed before publication; refusing to continue.');
  }
  validateAssets(current);
  verifyTag(true);
  if (current.draft) {
    // Keep any human edits to the draft's title/notes made during the upload.
    gh(['release', 'edit', tag, '--repo', repository, '--draft=false', '--prerelease']);
  }
  current = release();
  if (!current || current.draft || current.target_commitish !== sha) {
    throw new Error('Publication has not been confirmed.');
  }
  verifyTag();
  validateAssets(current);
  console.log(`Published https://github.com/${repository}/releases/tag/${tag}`);
}

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// CI-only assembly of the runtime and food observer. The Swift exporter remains
// the source of truth for a real catalog; its generated artifact is checked too.
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const resources = resolve(repoRoot, 'Sources/AoE2MacTrainer/Resources');
const marker = '// @FOOD_OBSERVER@';
const template = await readFile(resolve(resources, 'trainer_template.xs'), 'utf8');
const observer = await readFile(resolve(resources, 'food_observation_template.xs'), 'utf8');
if (template.split(marker).length !== 2) {
  throw new Error('The runtime must have exactly one food-observer insertion point.');
}
if (observer.includes(marker)) {
  throw new Error('The food observer must not recursively contain its insertion point.');
}
const assembled = template.replace(marker, () => observer);
const output = resolve(repoRoot, '.build/ci/trainer-runtime.xs');
await mkdir(dirname(output), { recursive: true });
await writeFile(output, assembled, 'utf8');
console.log(`Assembled runtime for XS Check: ${output}`);
